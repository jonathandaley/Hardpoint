#!/usr/bin/env python3
"""T172: bot-vs-bot win rates. Runs tools/bot_eval/bot_eval.tscn N times headless at
--fixed-fps (~7x real time), alternating sides, and tallies side A's record.

  python3 tools/bot_eval.py --a 4 --b 4 --legacy b -n 12          # live Elite vs T169 Elite
  python3 tools/bot_eval.py --a 4 --b 1 --legacy none --mech Pegasus
Mechs are picked per match from --mech (comma list, cycled)."""
import argparse, os, re, subprocess, sys, tempfile
from concurrent.futures import ThreadPoolExecutor

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LINE = re.compile(r"\[eval\] winner=(\w+) t=(\d+) alive=(\d+),(\d+) dealt=(\d+),(\d+) score=(-?\d+),(-?\d+) wpn=(\S*)")


def one(i, a):
    mech = a.mech.split(",")[i % len(a.mech.split(","))]
    user = ["a=%s" % a.a, "b=%s" % a.b, "legacy=%s" % a.legacy, "size=%d" % a.size,
            "mech=%s" % mech, "swap=%d" % (i % 2), "max_s=%d" % a.max_s]
    if a.size_b:
        user.append("size_b=%d" % a.size_b)
    if a.wa:
        user.append("wa=%s" % a.wa)
    if a.wb:
        user.append("wb=%s" % a.wb)
    with tempfile.TemporaryDirectory() as tmp:  # fresh user:// (no real profile / skills)
        env = dict(os.environ, XDG_DATA_HOME=tmp)
        godot = os.environ.get("GODOT", os.path.expanduser("~/bin/godot"))
        out = subprocess.run([godot, "--headless", "--fixed-fps", "60", "--path", ROOT,
                              "res://tools/bot_eval/bot_eval.tscn", "--"] + user,
                             capture_output=True, text=True, env=env, timeout=a.max_s + 300).stdout
    m = LINE.search(out)
    if a.keep:
        open(os.path.join(a.keep, "match_%02d_%s.log" % (i, mech)), "w").write(out)
    return mech, i % 2, m


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--a", type=int, default=4)
    ap.add_argument("--b", type=int, default=4)
    ap.add_argument("--legacy", default="b", choices=["a", "b", "none"])
    ap.add_argument("--size", type=int, default=3)
    ap.add_argument("--size-b", type=int, help="side B team size (uneven teams; default --size)")
    ap.add_argument("--mech", default="Hippogriff,Pegasus,Hornet,Kestrel,Everest,Slip")
    ap.add_argument("-n", type=int, default=12)
    ap.add_argument("--jobs", type=int, default=max(1, (os.cpu_count() or 2) // 2))
    ap.add_argument("--max-s", type=int, default=600)
    ap.add_argument("--keep", help="dir to keep per-match logs")
    ap.add_argument("--wa", help="force side A's weapon family (RIFLE, SNIPER, MG, SHOTGUN, MISSILE, ROCKET, LASER, ARC, AERIAL, PATIENCE)")
    ap.add_argument("--wb", help="force side B's weapon family")
    a = ap.parse_args()
    if a.keep:
        os.makedirs(a.keep, exist_ok=True)
    with ThreadPoolExecutor(a.jobs) as ex:
        res = list(ex.map(lambda i: one(i, a), range(a.n)))
    tally = {"A": 0, "B": 0, "draw": 0, "error": 0}
    for mech, swap, m in res:
        if m is None:
            tally["error"] += 1
            print("%-10s side=%d  ERROR (no [eval] line)" % (mech, swap))
            continue
        tally[m.group(1)] += 1
        print("%-10s side=%d  winner=%-4s t=%4ss alive=%s-%s dealt=%s-%s score=%s-%s  %s" % ((mech, swap) + m.groups()))
    print("A (diff %d%s) vs B (diff %d%s): A %d  B %d  draw %d  error %d" % (
        a.a, " legacy" if a.legacy == "a" else "", a.b, " legacy" if a.legacy == "b" else "",
        tally["A"], tally["B"], tally["draw"], tally["error"]))
    return 1 if tally["error"] else 0


if __name__ == "__main__":
    sys.exit(main())
