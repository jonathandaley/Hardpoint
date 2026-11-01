#!/usr/bin/env python3
"""T157: cut a recorded MP session down to a time window, so the oracles (and you)
look only where the player said it went weird.

Usage: session_window.py <session_dir> <from_s> <to_s> [out_dir]

Seconds count from the match start (tick 0 = that peer's first frame with mechs).
Writes trimmed *.jsonl copies to out_dir (default <session_dir>/window_<from>_<to>)
and lists the screenshots inside the window. Then run the oracles:
    python3 tools/sync_compare.py tools/sessions/real_session.json <out_dir>
"""
import glob
import json
import os
import sys


def main():
    src, a, b = sys.argv[1], float(sys.argv[2]), float(sys.argv[3])
    out = sys.argv[4] if len(sys.argv) > 4 else os.path.join(src, "window_%g_%g" % (a, b))
    os.makedirs(out, exist_ok=True)
    lo, hi = int(a * 60), int(b * 60)
    for path in sorted(glob.glob(os.path.join(src, "*.jsonl"))):
        with open(path) as f, open(os.path.join(out, os.path.basename(path)), "w") as g:
            for line in f:
                try:
                    t = json.loads(line).get("tick", 0)
                except ValueError:
                    continue  # torn last line of a crashed peer
                if lo <= t <= hi:
                    g.write(line)
    print("ticks %d..%d -> %s" % (lo, hi, out))
    for shot in sorted(glob.glob(os.path.join(src, "*.jpg"))):
        if lo <= int(shot.rsplit("_", 1)[1][:-4]) <= hi:
            print("shot", shot)


if __name__ == "__main__":
    main()
