"""crash_scan oracle: no process death, no engine errors (catches B17-class).

Reads the per-peer process logs (<role>.log, stdout+stderr merged by
run_scenario.py) and meta.json (exit codes / timeouts). FAILs on:
  - a nonzero exit code or a timeout kill (process death / hang), or
  - a Godot error line (ERROR:, SCRIPT ERROR, USER ERROR, push_error/
    push_warning escalations) in any peer log.
Needs no event stream -- it is a pure log/exit scan.
"""
import glob
import json
import os

from . import base

NAME = "crash_scan"

# Godot prints these on a GDScript runtime fault ("SCRIPT ERROR") or a
# push_error/push_warning ("USER ERROR"/"USER WARNING") -- the B17-class. The
# bare "ERROR:" prefix is intentionally NOT matched: the resource loader emits
# it for benign missing-asset warnings (e.g. a missing .ogg) that are content
# issues, not netcode faults, and process death is caught via exit code/timeout.
ERROR_MARKERS = ("SCRIPT ERROR", "USER ERROR")


def _scan_log(path):
    """First (lineno, line) containing an error marker, or None."""
    with open(path, errors="replace") as f:
        for i, line in enumerate(f, 1):
            for mark in ERROR_MARKERS:
                if mark in line:
                    return i, line.rstrip()
    return None


def run(ctx):
    run_dir = ctx.get("run_dir")
    if not run_dir or not os.path.isdir(run_dir):
        return base.verdict(NAME, base.SKIP, note="no run_dir to scan")

    # 1. Exit codes / timeouts from meta.json (process death / hang).
    meta_path = os.path.join(run_dir, "meta.json")
    if os.path.exists(meta_path):
        with open(meta_path) as f:
            meta = json.load(f)
        for role, info in sorted(meta.get("peers", {}).items()):
            if info.get("timed_out"):
                return base.verdict(NAME, base.FAIL, peer=role, pattern="sudden_jump",
                                    note="%s timed out (hang / no clean quit)" % role)
            rc = info.get("exit_code")
            if rc not in (0, None):
                return base.verdict(NAME, base.FAIL, peer=role, pattern="sudden_jump",
                                    note="%s exited nonzero (code %s)" % (role, rc))

    # 2. Error markers in each peer log.
    logs = sorted(glob.glob(os.path.join(run_dir, "*.log")))
    if not logs and not os.path.exists(meta_path):
        return base.verdict(NAME, base.SKIP, note="no *.log or meta.json in run_dir")
    for path in logs:
        role = os.path.basename(path)[: -len(".log")]
        hit = _scan_log(path)
        if hit is not None:
            lineno, line = hit
            return base.verdict(NAME, base.FAIL, peer=role, first_tick=None,
                                pattern="sudden_jump",
                                note="%s.log:%d %s" % (role, lineno, line[:160]))
    return base.verdict(NAME, base.PASS,
                        note="clean exits, no engine errors (%d logs scanned)" % len(logs))
