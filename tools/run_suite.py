#!/usr/bin/env python3
"""M2.5 suite runner: execute every scenario in tools/scenarios/ and aggregate.

For each scenario: run it (twice when its oracle list includes `determinism`,
so the second run serves as the baseline), then evaluate with sync_compare.
This is the permanent multiplayer regression net -- rerun after every netcode
change. Exit 0 only if every scenario's aggregate verdict is PASS.

Usage:
    run_suite.py [out_root] [--godot PATH] [--timeout SEC] [--only NAME ...]
"""
import argparse
import glob
import json
import os
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))


def sh(args, **kw):
    return subprocess.run([sys.executable] + args, **kw).returncode


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("out_root", nargs="?",
                    default=os.path.join(HERE, "..", "build", "suite_runs", time.strftime("%Y%m%d_%H%M%S")))
    ap.add_argument("--godot", default=None)
    ap.add_argument("--timeout", type=float, default=120.0)
    ap.add_argument("--only", action="append", default=None, help="scenario name(s) to run")
    ap.add_argument("--net", default=None,
                    help="T139/T151 chaos profile(s) for every scenario, comma-separated (e.g. lan,wifi,bad)")
    ap.add_argument("--no-probes", action="store_true", help="skip tools/gd_probes (e.g. for --net sweeps)")
    ap.add_argument("--soak", action="store_true", help="T152: also run 'soak' scenarios (one full match, ~15 min)")
    args = ap.parse_args()

    scenarios = sorted(glob.glob(os.path.join(HERE, "scenarios", "*.json")))
    results = []
    # T151: one pass per profile; None = each scenario's own "net" (usually lossless loopback)
    profiles = args.net.split(",") if args.net else [None]
    for net in profiles:
        _run_scenarios(args, scenarios, net, len(profiles) > 1, results)

    # T146: engine-level probes (run once; network-independent)
    if not args.only and not args.no_probes:
        _run_probes(args, results)

    print("\n=== suite summary ===")
    bad = 0
    for name, verdict in results:
        print("%-28s %s" % (name, verdict))
        bad += verdict != "PASS"
    if not results:
        print("no scenarios matched")
        return 2
    print("%d/%d scenarios pass" % (len(results) - bad, len(results)))
    return 1 if bad else 0


def _run_scenarios(args, scenarios, net, label, results):
    for spath in scenarios:
        with open(spath) as f:
            scen = json.load(f)
        name = scen.get("name", os.path.basename(spath))
        if args.only and name not in args.only:
            continue
        if scen.get("soak") and not (args.soak or (args.only and name in args.only)):
            continue  # T152: soaks run on request (--soak / --only), not every verify
        if scen.get("review") and not (args.only and name in args.only):
            continue  # T156: rendered screenshot runs are for review, not verdicts
        out = os.path.join(os.path.abspath(args.out_root), name + ("@" + net if label else ""))
        run_args = ["--timeout", str(max(args.timeout, 1800.0) if scen.get("soak") else args.timeout)]
        if args.godot:
            run_args += ["--godot", args.godot]
        if net is not None:
            run_args += ["--net", net]
        print("=== %s ===" % name, flush=True)
        rc = sh([os.path.join(HERE, "run_scenario.py"), spath, os.path.join(out, "run1")] + run_args)
        cmp_args = [os.path.join(HERE, "sync_compare.py"), spath, os.path.join(out, "run1")]
        # T151: a second run only means something on a lossless link (random delay shifts input ticks)
        if rc == 0 and "determinism" in scen.get("oracles", []) and net in (None, "none"):
            rc = sh([os.path.join(HERE, "run_scenario.py"), spath, os.path.join(out, "run2")] + run_args)
            cmp_args += ["--baseline-run", os.path.join(out, "run2")]
        if rc != 0:
            print("!!! %s: run_scenario failed (exit %d)" % (name, rc))
            results.append((name + ("@" + net if label else ""), "ERROR"))
            continue
        rc = sh(cmp_args)
        results.append((name + ("@" + net if label else ""), "PASS" if rc == 0 else "FAIL"))
        # T163: match 2+ of a multi-match scenario, judged on its own logs (Game writes run1/match<n>/)
        for n in range(2, int(scen.get("matches", 1)) + 1):
            mdir = os.path.join(out, "run1", "match%d" % n)
            ok = os.path.exists(os.path.join(mdir, "server.jsonl")) and sh(cmp_args[:2] + [mdir]) == 0
            results.append((name + "#m%d" % n + ("@" + net if label else ""), "PASS" if ok else "FAIL"))


def _run_probes(args, results):
    # T146: engine-level probes (tools/gd_probes/*.tscn) -- tiny scenes that drive
    # one code path headless and must exit 0, print their done line, and log no
    # engine errors (crash_scan rules).
    sys.path.insert(0, HERE)
    from oracles import crash_scan
    for probe in sorted(glob.glob(os.path.join(HERE, "gd_probes", "*.tscn"))):
        name = "probe:" + os.path.basename(probe)[:-5]
        out = os.path.join(os.path.abspath(args.out_root), name.replace(":", "_"))
        os.makedirs(out, exist_ok=True)
        log = os.path.join(out, "probe.log")
        env = dict(os.environ, XDG_DATA_HOME=os.path.join(out, "userdata"))
        godot = args.godot or os.environ.get("GODOT", os.path.expanduser("~/bin/godot"))
        with open(log, "w") as f:
            try:
                rc = subprocess.run([godot, "--headless", "--path", os.path.dirname(HERE),
                                     "res://tools/gd_probes/" + os.path.basename(probe), "--quit-after", "6000"],
                                    stdout=f, stderr=subprocess.STDOUT, env=env, timeout=120).returncode
            except subprocess.TimeoutExpired:
                rc = -1
        done = "[probe]" in open(log, errors="replace").read()
        hit = crash_scan.scan_log(log)
        ok = rc == 0 and done and hit is None
        print("=== %s === %s%s" % (name, "PASS" if ok else "FAIL",
                                   "" if ok else " (exit %s, done=%s, %s)" % (rc, done, hit)))
        results.append((name, "PASS" if ok else "FAIL"))


if __name__ == "__main__":
    sys.exit(main())
