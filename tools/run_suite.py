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
    args = ap.parse_args()

    scenarios = sorted(glob.glob(os.path.join(HERE, "scenarios", "*.json")))
    results = []
    for spath in scenarios:
        with open(spath) as f:
            scen = json.load(f)
        name = scen.get("name", os.path.basename(spath))
        if args.only and name not in args.only:
            continue
        out = os.path.join(os.path.abspath(args.out_root), name)
        run_args = ["--timeout", str(args.timeout)]
        if args.godot:
            run_args += ["--godot", args.godot]
        print("=== %s ===" % name, flush=True)
        rc = sh([os.path.join(HERE, "run_scenario.py"), spath, os.path.join(out, "run1")] + run_args)
        cmp_args = [os.path.join(HERE, "sync_compare.py"), spath, os.path.join(out, "run1")]
        if rc == 0 and "determinism" in scen.get("oracles", []):
            rc = sh([os.path.join(HERE, "run_scenario.py"), spath, os.path.join(out, "run2")] + run_args)
            cmp_args += ["--baseline-run", os.path.join(out, "run2")]
        if rc != 0:
            print("!!! %s: run_scenario failed (exit %d)" % (name, rc))
            results.append((name, "ERROR"))
            continue
        rc = sh(cmp_args)
        results.append((name, "PASS" if rc == 0 else "FAIL"))

    print("\n=== suite summary ===")
    bad = 0
    for name, verdict in results:
        print("%-24s %s" % (name, verdict))
        bad += verdict != "PASS"
    if not results:
        print("no scenarios matched")
        return 2
    print("%d/%d scenarios pass" % (len(results) - bad, len(results)))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
