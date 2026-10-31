#!/usr/bin/env python3
"""T139 chaos proxy: UDP relay between harness clients and the server with seeded
latency / jitter / loss / duplication / reordering. Stdlib only, no root.

Usage:
    netem_proxy.py --listen PORT --target PORT --profile NAME|JSON [--seed N]
    netem_proxy.py selftest

Clients connect to --listen; each client address gets its own upstream socket so
the server sees distinct peers. Both directions (c2s, s2c) get the same profile.
Latency is one-way per direction. Without "reorder", jittered packets keep their
send order (like most real links); with it, each packet is delayed independently.
SIGTERM/SIGINT -> prints one `[netem] stats {...}` JSON line and exits 0.
"""
import argparse
import asyncio
import collections
import json
import os
import random
import signal
import socket
import subprocess
import sys
import time

# ponytail: fixed profiles from MP_AUTODEBUG_PLAN §9; tune here if they prove unrealistic
PROFILES = {
    "none": {},
    "lan": {"latency_ms": 2},
    "wifi": {"latency_ms": 20, "jitter_ms": 10, "loss": 0.01},
    "bad": {"latency_ms": 80, "jitter_ms": 30, "loss": 0.05, "reorder": True},
}


def resolve(profile):
    """Profile name or JSON object -> impairment dict."""
    if profile in PROFILES:
        return dict(PROFILES[profile])
    cfg = json.loads(profile)
    if not isinstance(cfg, dict):
        raise ValueError("profile must be a name or JSON object: %r" % profile)
    return cfg


class Lane:
    """One direction of traffic with its own impairment schedule."""

    def __init__(self, name, cfg, rng, stats, t0=0.0):
        self.name, self.cfg, self.rng, self.stats = name, cfg, rng, stats
        self.last_due = 0.0
        self.t0 = t0  # proxy start (loop time); "outage": [start_s, end_s] is relative to it

    def push(self, loop, send, data):
        c, s = self.cfg, self.stats
        s[self.name + "_in"] += 1
        out = c.get("outage")  # T151: total blackout window, both directions
        if out and out[0] <= loop.time() - self.t0 < out[1]:
            s[self.name + "_outage"] += 1
            return
        if self.rng.random() < c.get("loss", 0.0):
            s[self.name + "_drop"] += 1
            return
        copies = 2 if self.rng.random() < c.get("dup", 0.0) else 1
        s[self.name + "_dup"] += copies - 1
        for _ in range(copies):
            delay = (c.get("latency_ms", 0) + self.rng.uniform(-1.0, 1.0) * c.get("jitter_ms", 0)) / 1000.0
            due = loop.time() + max(0.0, delay)
            if not c.get("reorder", False):
                due = max(due, self.last_due)
                self.last_due = due
            loop.call_at(due, self._send, send, data)

    def _send(self, send, data):
        try:
            send(data)
            self.stats[self.name + "_out"] += 1
        except OSError:  # peer not up yet / gone; same as a lost packet
            self.stats[self.name + "_send_err"] += 1


def run(listen, target, cfg, seed):
    loop = asyncio.new_event_loop()
    stats = collections.Counter()
    # one RNG per lane: a lane's drop pattern depends only on its own packet order,
    # not on how c2s/s2c traffic interleaves (which varies run to run)
    c2s = Lane("c2s", cfg, random.Random(seed * 2), stats, loop.time())
    s2c = Lane("s2c", cfg, random.Random(seed * 2 + 1), stats, loop.time())
    down = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    down.bind(("127.0.0.1", listen))
    down.setblocking(False)
    ups = {}

    def on_up(up, addr):
        while True:
            try:
                data = up.recv(65535)
            except (BlockingIOError, ConnectionRefusedError):
                return
            s2c.push(loop, lambda d, a=addr: down.sendto(d, a), data)

    def on_down():
        while True:
            try:
                data, addr = down.recvfrom(65535)
            except (BlockingIOError, ConnectionRefusedError):
                return
            up = ups.get(addr)
            if up is None:
                up = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
                up.bind(("127.0.0.1", 0))
                up.connect(("127.0.0.1", target))
                up.setblocking(False)
                ups[addr] = up
                loop.add_reader(up, on_up, up, addr)
            c2s.push(loop, up.send, data)

    loop.add_reader(down, on_down)
    for sig in (signal.SIGTERM, signal.SIGINT):
        loop.add_signal_handler(sig, loop.stop)
    print("[netem] listen=%d target=%d seed=%s cfg=%s" % (listen, target, seed, json.dumps(cfg)), flush=True)
    loop.run_forever()
    stats["clients"] = len(ups)
    print("[netem] stats " + json.dumps(dict(stats), sort_keys=True), flush=True)


def _free_port():
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.bind(("127.0.0.1", 0))
    port = s.getsockname()[1]
    s.close()
    return port


def _selftest_case(profile, n):
    """Send n packets client->server, server echoes each back. Returns
    (server_got, client_got, first_c2s_latency_s, proxy_stats)."""
    listen, target = _free_port(), _free_port()
    srv = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    srv.bind(("127.0.0.1", target))
    srv.settimeout(0.3)
    proxy = subprocess.Popen([sys.executable, os.path.abspath(__file__), "--listen", str(listen),
                              "--target", str(target), "--profile", profile, "--seed", "7"],
                             stdout=subprocess.PIPE, text=True)
    proxy.stdout.readline()  # "[netem] listen=..." = bound and serving
    cli = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    cli.settimeout(0.3)
    t0 = time.monotonic()
    for i in range(n):
        cli.sendto(b"%d" % i, ("127.0.0.1", listen))
    server_got, first = 0, None
    try:
        while True:
            data, addr = srv.recvfrom(100)
            first = first if first is not None else time.monotonic() - t0
            server_got += 1
            srv.sendto(data, addr)
    except socket.timeout:
        pass
    client_got = 0
    try:
        while True:
            cli.recvfrom(100)
            client_got += 1
    except socket.timeout:
        pass
    proxy.send_signal(signal.SIGTERM)
    out = proxy.communicate(timeout=5)[0]
    stats = json.loads(out.split("[netem] stats ", 1)[1])
    return server_got, client_got, first, stats


def selftest():
    got, back, first, st = _selftest_case("none", 100)
    assert got == 100 and back == 100, ("clean relay must be lossless", got, back)
    assert st["clients"] == 1, st
    got, back, first, st = _selftest_case('{"latency_ms": 40}', 20)
    assert got == 20 and first >= 0.035, ("latency not applied", got, first)
    # ponytail: n stays under ~170 packets; the test reads after sending, and the
    # kernel's default UDP receive buffer drops beyond that (not a proxy fault)
    got, back, first, st = _selftest_case('{"loss": 0.5}', 150)
    assert 45 <= got <= 105, ("~50%% c2s loss expected", got)
    assert st.get("c2s_drop", 0) == 150 - got, st
    assert back < got, ("s2c loss expected too", got, back)
    got, back, first, st = _selftest_case('{"loss": 1.0}', 50)
    assert got == 0 and back == 0, ("total loss must drop everything", got, back)
    got, back, first, st = _selftest_case('{"outage": [0, 30]}', 20)
    assert got == 0 and st.get("c2s_outage") == 20, ("outage window must black out the link", got, st)
    print("netem_proxy selftest ok")


def main():
    if sys.argv[1:] == ["selftest"]:
        selftest()
        return 0
    ap = argparse.ArgumentParser()
    ap.add_argument("--listen", type=int, required=True)
    ap.add_argument("--target", type=int, required=True)
    ap.add_argument("--profile", default="none")
    ap.add_argument("--seed", type=int, default=0)
    args = ap.parse_args()
    run(args.listen, args.target, resolve(args.profile), args.seed)
    return 0


if __name__ == "__main__":
    sys.exit(main())
