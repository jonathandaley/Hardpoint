#!/usr/bin/env python3
"""T394: move finished §T rows from SPEC.md to SPEC_DONE.md (same row format, grep-able).

Stays in SPEC.md: §G / §C / §I / §V / §B whole, every open row (`.` / `~`), and every done
row an open row cites (its text or its dependency column), so an open task's context is
never a second file away. Run again whenever SPEC.md has grown: `python3 tools/spec_sweep.py`
(`--dry` = report only). Rows are moved whole, never edited.
"""
import os
import re
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
SPEC, DONE = os.path.join(ROOT, "SPEC.md"), os.path.join(ROOT, "SPEC_DONE.md")
HEAD = ("# SPEC_DONE\n\nFinished §T rows moved out of SPEC.md by tools/spec_sweep.py (T394). Same format; "
        "`grep -n '^T123|' SPEC_DONE.md` finds one.\n\nid|status|task|cites\n")
ROW = re.compile(r"^(T\d+)\|([^|]*)\|")


def main():
    lines = open(SPEC).read().split("\n")
    rows = {m.group(1): (i, m.group(2)) for i, ln in enumerate(lines) for m in [ROW.match(ln)] if m}
    cited = set()
    for tid, (i, status) in rows.items():
        if status != "x":
            cited.update(re.findall(r"\bT\d+\b", lines[i]))
    move = [i for tid, (i, status) in rows.items() if status == "x" and tid not in cited]
    moved = [lines[i] for i in move]
    print("spec_sweep: %d rows, %d open, %d done kept (cited by an open row), %d to move (%d KB)" % (
        len(rows), sum(1 for _, s in rows.values() if s != "x"),
        sum(1 for t, (_, s) in rows.items() if s == "x" and t in cited), len(moved), sum(map(len, moved)) // 1024))
    if "--dry" in sys.argv or not moved:
        return 0
    old = open(DONE).read() if os.path.exists(DONE) else HEAD
    before = len("\n".join(lines)) + len(old)
    gone = set(move)
    new_spec = "\n".join(ln for i, ln in enumerate(lines) if i not in gone)
    new_done = old.rstrip("\n") + "\n" + "\n".join(moved) + "\n"
    assert len(new_spec) + len(new_done) >= before - 2, "bytes lost"  # nothing dropped on the way
    open(DONE + ".tmp", "w").write(new_done)
    os.replace(DONE + ".tmp", DONE)  # the done file lands first: a crash can duplicate rows, never lose them
    open(SPEC, "w").write(new_spec)
    return 0


if __name__ == "__main__":
    sys.exit(main())
