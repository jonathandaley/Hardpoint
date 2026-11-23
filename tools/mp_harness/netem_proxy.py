#!/usr/bin/env python3
"""T139 chaos proxy, TCP since T422 (the game runs over WebSocket): a relay between harness
clients and the server with seeded latency / jitter / loss / outages. Stdlib only, no root.

Usage:
    netem_proxy.py --listen PORT --target PORT --profile NAME|JSON [--seed N]
    netem_proxy.py selftest

Each client connection gets its own upstream connection. Both directions (c2s, s2c) get the same
profile; latency is one-way per direction. TCP never loses or reorders bytes, so the impairments
are what a real lossy link does to a TCP stream:
  - "loss": a read chunk counts as a lost segment -- it and everything behind it wait for the
    resend (RESEND_S + one round trip): the head-of-line stall a browser player sees on bad wifi;
  - "reorder" / "dup": nothing (TCP hides both);
  - "outage": [start_s, end_s] holds the stream and lets it all through when the link is back.
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


# How long past one round trip a lost segment waits: the game is a steady stream both ways (inputs 30 a
# second, snapshots 20+), so TCP's fast retransmit catches a loss from the next ~3 segments' duplicate
# acks (~0.1 s) rather than the 0.2 s minimum retransmit timeout a quiet link waits for.
# ponytail: a burst of losses (or a lost last packet) waits the timeout; the model doesn't stack them.
RESEND_S = 0.1


class Lane:
    """One direction of one connection: delivers chunks in order, each at its due time."""

    def __init__(self, name, cfg, rng, stats, t0=0.0):
        self.name, self.cfg, self.rng, self.stats = name, cfg, rng, stats
        self.last_due = 0.0
        self.t0 = t0  # proxy start (loop time); "outage" is relative to it
        self.q = collections.deque()

    def push(self, loop, send, data):
        c, s = self.cfg, self.stats
        s[self.name + "_in"] += 1
        s[self.name + "_bytes"] += len(data)  # T152: bandwidth budget
        lat = c.get("latency_ms", 0) / 1000.0
        due = loop.time() + max(0.0, lat + self.rng.uniform(-1.0, 1.0) * c.get("jitter_ms", 0) / 1000.0)
        out = c.get("outage")  # T151: blackout window, both directions -- held, not lost
        if out and out[0] <= loop.time() - self.t0 < out[1]:
            s[self.name + "_outage"] += 1
            due = max(due, self.t0 + out[1] + lat)
        if self.rng.random() < c.get("loss", 0.0):
            s[self.name + "_drop"] += 1  # resent: late, never gone
            due += RESEND_S + 2.0 * lat
        due = max(due, self.last_due)  # a stream: nothing overtakes
        self.last_due = due
        # one queue, drained in order (asyncio's timer heap doesn't keep equal times in order)
        self.q.append((due, send, data))
        if len(self.q) == 1:
            loop.call_at(due, self._drain, loop)

    def _drain(self, loop):
        while self.q and self.q[0][0] <= loop.time():
            _, send, data = self.q.popleft()
            try:
                send(data)
                self.stats[self.name + "_out"] += 1
            except OSError:  # gone; same as a closed connection
                self.stats[self.name + "_send_err"] += 1
        if self.q:
            loop.call_at(self.q[0][0], self._drain, loop)


def run(listen, target, cfg, seed):
    loop = asyncio.new_event_loop()
    stats = collections.Counter()
    t0 = loop.time()
    n = [0]

    async def pump(reader, writer, lane):
        while True:
            try:
                data = await reader.read(65536)
            except OSError:
                data = b""
            if not data:
                break
            lane.push(loop, writer.write, data)
        # close once everything queued ahead of the EOF has gone out
        loop.call_at(max(loop.time(), lane.last_due) + 0.001, writer.close)

    async def on_client(creader, cwriter):
        # one RNG per lane: a lane's resend pattern depends only on its own chunk order
        k = n[0]
        n[0] += 1
        stats["clients"] += 1
        try:
            ureader, uwriter = await asyncio.open_connection("127.0.0.1", target)
        except OSError:
            cwriter.close()
            return
        for w in (cwriter, uwriter):
            w.get_extra_info("socket").setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
        c2s = Lane("c2s", cfg, random.Random(seed * 1000 + k * 2), stats, t0)
        s2c = Lane("s2c", cfg, random.Random(seed * 1000 + k * 2 + 1), stats, t0)
        await asyncio.gather(pump(creader, uwriter, c2s), pump(ureader, cwriter, s2c))

    server = loop.run_until_complete(asyncio.start_server(on_client, "127.0.0.1", listen))
    for sig in (signal.SIGTERM, signal.SIGINT):
        loop.add_signal_handler(sig, loop.stop)
    print("[netem] listen=%d target=%d seed=%s cfg=%s" % (listen, target, seed, json.dumps(cfg)), flush=True)
    loop.run_forever()
    server.close()
    print("[netem] stats " + json.dumps(dict(stats), sort_keys=True), flush=True)
    os._exit(0)  # open connections' tasks would only log "Task was destroyed" at exit


def _free_port():
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.bind(("127.0.0.1", 0))
    port = s.getsockname()[1]
    s.close()
    return port


def _selftest_case(profile, n, gap=0.0):
    """Send n numbered lines client->server, the server echoes each. Returns
    (lines the server got in order, client got back, seconds to the last echo, stats)."""
    listen, target = _free_port(), _free_port()
    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.bind(("127.0.0.1", target))
    srv.listen(1)
    proxy = subprocess.Popen([sys.executable, os.path.abspath(__file__), "--listen", str(listen),
                              "--target", str(target), "--profile", profile, "--seed", "7"],
                             stdout=subprocess.PIPE, text=True)
    proxy.stdout.readline()  # "[netem] listen=..." = bound and serving
    cli = socket.create_connection(("127.0.0.1", listen))
    cli.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
    conn, _ = srv.accept()
    conn.settimeout(3.0)
    cli.settimeout(3.0)
    t0 = time.monotonic()
    for i in range(n):
        cli.sendall(b"%d\n" % i)
        time.sleep(gap)  # separate chunks, so loss can hit some of them
    got = b""
    while got.count(b"\n") < n:
        got += conn.recv(65536)
    conn.sendall(got)
    back = b""
    while back.count(b"\n") < n:
        back += cli.recv(65536)
    took = time.monotonic() - t0
    cli.close()
    conn.close()
    proxy.send_signal(signal.SIGTERM)
    out = proxy.communicate(timeout=5)[0]
    stats = json.loads(out.split("[netem] stats ", 1)[1])
    return [int(x) for x in got.split()], back.count(b"\n"), took, stats


def selftest():
    got, back, took, st = _selftest_case("none", 100)
    assert got == list(range(100)) and back == 100, ("clean relay must be lossless", got[:5], back)
    assert st["clients"] == 1, st
    got, back, took, st = _selftest_case('{"latency_ms": 40}', 20)
    assert back == 20 and took >= 0.075, ("latency not applied both ways", took)  # one trip each way
    got, back, took, st = _selftest_case('{"loss": 0.5, "jitter_ms": 20}', 30, gap=0.005)
    assert got == list(range(30)) and back == 30, ("loss must delay, never drop or reorder", got)
    assert st.get("c2s_drop", 0) > 0 and took >= RESEND_S, ("loss should stall the stream", st, took)
    got, back, took, st = _selftest_case('{"outage": [0, 0.6]}', 10)
    assert got == list(range(10)) and took >= 0.5 and st.get("c2s_outage", 0) > 0, \
        ("an outage holds the stream until the link is back", took, st)
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
