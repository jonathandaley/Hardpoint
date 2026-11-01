"""crash_scan oracle: no process death, no engine errors (catches B17-class).

Reads the per-peer process logs (<role>.log, stdout+stderr merged by
run_scenario.py) and meta.json (exit codes / timeouts). FAILs on:
  - a nonzero exit code or a timeout kill (process death / hang), or
  - SCRIPT ERROR / USER ERROR, or
  - ANY Godot "ERROR:" line not on the shutdown-noise allow-list (T143).
    That covers push_error (Godot 4.6 prints it as bare "ERROR:" + "at:
    push_error", B37) and engine errors such as "Node not found", "Failed to
    get cached node", 'Condition "!is_inside_tree()"', "Invalid packet
    received" -- the B-g/B-h class, which the old marker list ignored.
Allow-list = noise measured on green runs (31 archived suite runs, 2026-10-31).
Needs no event stream -- it is a pure log/exit scan.
"""
import glob
import json
import os
import re

from . import base

NAME = "crash_scan"

ERROR_MARKERS = ("SCRIPT ERROR", "USER ERROR")
# ponytail: allow-list, not deny-list -- unknown engine errors fail by default.
# Add an entry only with evidence it is teardown noise, never to silence a bug.
ALLOWED_ERRORS = (
    re.compile(r"^ERROR: \d+ resources still in use at exit"),        # engine exit report
    re.compile(r"^ERROR: Unable to send packet on channel \d+, max channels: \d+"),  # ENet send after close at teardown
)


def _allowed(line):
    return any(p.search(line) for p in ALLOWED_ERRORS)


def scan_log(path):
    """First (lineno, line) that is an error, or None."""
    with open(path, errors="replace") as f:
        for i, line in enumerate(f, 1):
            line = line.rstrip()
            if any(m in line for m in ERROR_MARKERS):
                return i, line
            if line.startswith("ERROR:") and not _allowed(line):
                return i, line
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
            log = os.path.join(run_dir, role + ".log")
            if rc == -9 and os.path.exists(log) and "[Harness] action kill_client" in open(log, errors="replace").read():
                continue  # T153: the scenario SIGKILLed this peer on purpose
            if rc not in (0, None):
                return base.verdict(NAME, base.FAIL, peer=role, pattern="sudden_jump",
                                    note="%s exited nonzero (code %s)" % (role, rc))

    # 2. Error lines in each peer log.
    logs = sorted(glob.glob(os.path.join(run_dir, "*.log")))
    if not logs and not os.path.exists(meta_path):
        return base.verdict(NAME, base.SKIP, note="no *.log or meta.json in run_dir")
    for path in logs:
        role = os.path.basename(path)[: -len(".log")]
        hit = scan_log(path)
        if hit is not None:
            lineno, line = hit
            return base.verdict(NAME, base.FAIL, peer=role, first_tick=None,
                                pattern="sudden_jump",
                                note="%s.log:%d %s" % (role, lineno, line[:160]))
    return base.verdict(NAME, base.PASS,
                        note="clean exits, no engine errors (%d logs scanned)" % len(logs))
