#!/usr/bin/env python3
"""M0.4 orchestrator for the MP autodebug harness.

Launches a server + client as two separate headless Godot processes over
loopback ENet (identical code path to a real LAN game), each driven by the
ReplayInputSource from the scenario, each writing JSONL sync logs into the run
directory. Stdlib only.

Usage:
    run_scenario.py <scenario.json> <out_dir> [--godot PATH] [--timeout SEC]

Writes <out_dir>/server.jsonl, <out_dir>/client_1.jsonl (+ .events.jsonl), and
<out_dir>/server.log / client_1.log (process stdout+stderr). Exit code 0 if both
processes exit cleanly and both snapshot logs are non-empty.
"""
import argparse
import json
import os
import subprocess
import sys
import time

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT_GODOT = os.environ.get("GODOT", os.path.expanduser("~/bin/godot"))
PROXY = os.path.join(REPO, "tools", "mp_harness", "netem_proxy.py")


def user_dir_root(out_dir, sync_role):
    return os.path.join(out_dir, "userdata", sync_role)


def launch(godot, role, sync_role, scenario_abs, out_dir, extra=(), rendered=False):
    log = open(os.path.join(out_dir, f"{sync_role}.log"), "w")
    # T138: own user:// per process (Godot honors XDG_DATA_HOME on Linux), so peers
    # never share settings.cfg/profile.cfg and runs never touch the real profile.
    env = dict(os.environ, XDG_DATA_HOME=user_dir_root(out_dir, sync_role))
    # T147: a rendered peer runs on a private Xvfb display (xvfb-run) instead of
    # --headless, so screenshots show what a player sees.
    head = ["xvfb-run", "-a", "-s", "-screen 0 1280x720x24", godot] if rendered else [godot, "--headless"]
    args = head + [
        "--path", REPO,
        "--mp-scenario=" + scenario_abs,
        "--role=" + role,
        "--sync-log",
        "--sync-role=" + sync_role,
        "--sync-dir=" + out_dir,
    ] + list(extra)
    proc = subprocess.Popen(args, stdout=log, stderr=subprocess.STDOUT, env=env)
    return proc, log


def isolation_ok(out_dir, sync_role):
    """T138 check: the peer's log reports a user:// inside its own run folder."""
    want = user_dir_root(out_dir, sync_role) + os.sep
    with open(os.path.join(out_dir, f"{sync_role}.log")) as f:
        for line in f:
            if line.startswith("[Harness] user_data_dir="):
                return line.split("=", 1)[1].strip().startswith(want)
    return False


def _proxy_stats(out_dir):
    with open(os.path.join(out_dir, "proxy.log")) as f:
        for line in f:
            if line.startswith("[netem] stats "):
                return json.loads(line[len("[netem] stats "):])
    return None


def _write_meta(out_dir, meta):
    with open(os.path.join(out_dir, "meta.json"), "w") as f:
        json.dump(meta, f, indent=2)


def wait(proc, timeout, label):
    try:
        proc.wait(timeout=timeout)
    except subprocess.TimeoutExpired:
        print(f"[run_scenario] {label} timed out after {timeout}s, killing")
        proc.kill()
        proc.wait()
        return False
    return True


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("scenario")
    ap.add_argument("out_dir")
    ap.add_argument("--godot", default=DEFAULT_GODOT)
    ap.add_argument("--timeout", type=float, default=60.0)
    ap.add_argument("--render", action="append", default=[],
                    help="T147: run this peer (e.g. client_1) rendered under Xvfb; repeatable")
    ap.add_argument("--net", default=None,
                    help="T139 chaos profile (none|lan|wifi|bad|JSON); overrides scenario 'net'")
    args = ap.parse_args()

    scenario_abs = os.path.abspath(args.scenario)
    out_dir = os.path.abspath(args.out_dir)
    os.makedirs(out_dir, exist_ok=True)

    with open(scenario_abs) as f:
        scenario = json.load(f)
    print(f"[run_scenario] scenario={scenario.get('name')} seed={scenario.get('seed')} "
          f"out={out_dir}")

    meta = {"scenario": scenario.get("name"), "peers": {}}
    # T139: with a net profile, clients reach the server through netem_proxy.py.
    net = args.net if args.net is not None else scenario.get("net")
    proxy, client_extra = None, []
    if net is not None:
        port = int(scenario.get("port", 8910))
        proxy_log = open(os.path.join(out_dir, "proxy.log"), "w")
        proxy = subprocess.Popen(
            [sys.executable, PROXY, "--listen", str(port + 1000), "--target", str(port),
             "--profile", net if isinstance(net, str) else json.dumps(net),
             "--seed", str(int(scenario.get("seed", 0)))],
            stdout=proxy_log, stderr=subprocess.STDOUT)
        client_extra = ["--connect-port=%d" % (port + 1000)]
        print(f"[run_scenario] net={net} via proxy :{port + 1000}")
    server, slog = launch(args.godot, "server", "server", scenario_abs, out_dir)
    time.sleep(2.0)  # let the server bind loopback before the client connects
    if server.poll() is not None:
        print("[run_scenario] server exited early; see server.log")
        slog.close()
        if proxy is not None:
            proxy.kill()
        meta["peers"]["server"] = {"exit_code": server.returncode, "timed_out": False, "early_exit": True}
        _write_meta(out_dir, meta)
        return 1
    # M2.1: one process per non-server peer key in the scenario (client_1, client_2, ...).
    peer_keys = sorted(k for k in scenario.get("peers", {}) if k != "server")
    clients = []
    for key in peer_keys:
        proc, log = launch(args.godot, "client", key, scenario_abs, out_dir, client_extra,
                           rendered=key in args.render or key in scenario.get("render", []))
        clients.append((key, proc, log))

    ok = True
    for key, proc, log in clients:
        c_ok = wait(proc, args.timeout, key)
        ok = ok and c_ok
        log.close()
        # crash_scan oracle (M1.3) reads these: nonzero exit / timeout = process death.
        meta["peers"][key] = {"exit_code": proc.returncode, "timed_out": not c_ok}
    server_ok = wait(server, args.timeout, "server")
    ok = ok and server_ok
    slog.close()
    meta["peers"]["server"] = {"exit_code": server.returncode, "timed_out": not server_ok}
    if proxy is not None:
        proxy.terminate()
        proxy.wait(timeout=10)
        proxy_log.close()
        meta["net"] = {"profile": net, "stats": _proxy_stats(out_dir)}
        print(f"[run_scenario] proxy stats: {meta['net']['stats']}")
    _write_meta(out_dir, meta)

    # Verify all snapshot logs exist and are non-empty.
    for name in ["server.jsonl"] + [k + ".jsonl" for k in peer_keys]:
        p = os.path.join(out_dir, name)
        n = sum(1 for _ in open(p)) if os.path.exists(p) else 0
        print(f"[run_scenario] {name}: {n} lines")
        if n == 0:
            ok = False
    for role in ["server"] + peer_keys:
        if not isolation_ok(out_dir, role):
            print(f"[run_scenario] {role}: user:// NOT isolated in run folder (T138)")
            ok = False
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
