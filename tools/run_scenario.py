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


def launch(godot, role, sync_role, scenario_abs, out_dir):
    log = open(os.path.join(out_dir, f"{sync_role}.log"), "w")
    args = [
        godot, "--headless", "--path", REPO,
        "--mp-scenario=" + scenario_abs,
        "--role=" + role,
        "--sync-log",
        "--sync-role=" + sync_role,
        "--sync-dir=" + out_dir,
    ]
    proc = subprocess.Popen(args, stdout=log, stderr=subprocess.STDOUT)
    return proc, log


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
    args = ap.parse_args()

    scenario_abs = os.path.abspath(args.scenario)
    out_dir = os.path.abspath(args.out_dir)
    os.makedirs(out_dir, exist_ok=True)

    with open(scenario_abs) as f:
        scenario = json.load(f)
    print(f"[run_scenario] scenario={scenario.get('name')} seed={scenario.get('seed')} "
          f"out={out_dir}")

    meta = {"scenario": scenario.get("name"), "peers": {}}
    server, slog = launch(args.godot, "server", "server", scenario_abs, out_dir)
    time.sleep(2.0)  # let the server bind loopback before the client connects
    if server.poll() is not None:
        print("[run_scenario] server exited early; see server.log")
        slog.close()
        meta["peers"]["server"] = {"exit_code": server.returncode, "timed_out": False, "early_exit": True}
        _write_meta(out_dir, meta)
        return 1
    client, clog = launch(args.godot, "client", "client_1", scenario_abs, out_dir)

    client_ok = wait(client, args.timeout, "client")
    server_ok = wait(server, args.timeout, "server")
    ok = client_ok and server_ok
    slog.close()
    clog.close()
    # crash_scan oracle (M1.3) reads these: nonzero exit / timeout = process death.
    meta["peers"]["server"] = {"exit_code": server.returncode, "timed_out": not server_ok}
    meta["peers"]["client_1"] = {"exit_code": client.returncode, "timed_out": not client_ok}
    _write_meta(out_dir, meta)

    # Verify both snapshot logs exist and are non-empty.
    for name in ("server.jsonl", "client_1.jsonl"):
        p = os.path.join(out_dir, name)
        n = sum(1 for _ in open(p)) if os.path.exists(p) else 0
        print(f"[run_scenario] {name}: {n} lines")
        if n == 0:
            ok = False
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
