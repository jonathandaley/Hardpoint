#!/usr/bin/env python3
"""M0 determinism self-test: the M0 deliverable / green baseline gate.

Runs a scenario twice with the identical seed + script, then diffs the two
SERVER (authoritative) snapshot streams under Mode-A loopback tolerances.
Client-side logs are interpolated (V38) and intentionally NOT part of the
determinism gate -- they are for the M1 cross-peer transform oracle.

Usage:
    selftest.py [scenario.json] [--godot PATH] [--keep]

Exit 0 = green baseline (PASS), nonzero = divergence or run failure.
"""
import argparse
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))


def run(scenario, godot, work):
    for label in ("run1", "run2"):
        out = os.path.join(work, label)
        cmd = [sys.executable, os.path.join(HERE, "run_scenario.py"),
               scenario, out, "--godot", godot]
        print(f"[selftest] {label} ...")
        if subprocess.call(cmd) != 0:
            print(f"[selftest] {label} FAILED to run cleanly")
            return None
    return work


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("scenario",
                    nargs="?",
                    default=os.path.join(HERE, "scenarios", "determinism_2peer.json"))
    ap.add_argument("--godot", default=os.environ.get("GODOT", os.path.expanduser("~/bin/godot")))
    ap.add_argument("--keep", action="store_true", help="keep the work dir")
    args = ap.parse_args()

    work = tempfile.mkdtemp(prefix="mbselftest_")
    print(f"[selftest] work dir {work}")
    try:
        if run(args.scenario, args.godot, work) is None:
            return 1
        diff = [sys.executable, os.path.join(HERE, "sync_diff.py"),
                os.path.join(work, "run1", "server.jsonl"),
                os.path.join(work, "run2", "server.jsonl")]
        print("[selftest] diffing authoritative server streams ...")
        rc = subprocess.call(diff)
        if rc == 0:
            print("[selftest] GREEN: determinism baseline holds.")
        else:
            print("[selftest] RED: server streams diverged beyond tolerance.")
        return rc
    finally:
        if not args.keep:
            subprocess.call(["rm", "-rf", work])


if __name__ == "__main__":
    sys.exit(main())
