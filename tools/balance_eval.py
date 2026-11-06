#!/usr/bin/env python3
"""T209: bot balance tester (report only -- it changes no stats).

Runs N headless all-bot matches (tools/balance/balance_match.tscn: every slot an Elite
bot, 5-mech squads of random mech + weapon-family picks, a different seed per match) and
reports per mech and per weapon family: lives sampled, win rate of the team the life was
on (95% Wilson interval), damage dealt / taken per life, kills per life, survival time.

  python3 tools/balance_eval.py -n 24            # ~6 min on 8 cores
  python3 tools/balance_eval.py -n 60 --size 4   # tighter intervals
  python3 tools/balance_eval.py --selftest       # check the aggregation maths

Writes build/balance/balance_<timestamp>.md and prints it. Read win rates with their
intervals: two mechs whose intervals overlap are not shown to differ."""
import argparse
import datetime
import json
import math
import os
import re
import subprocess
import sys
import tempfile
from concurrent.futures import ThreadPoolExecutor

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LIFE = re.compile(r"^\[bal\] (\{.*\})$", re.M)
MATCH = re.compile(r"^\[bal-match\] (\{.*\})$", re.M)


def run_match(seed, a):
    with tempfile.TemporaryDirectory() as tmp:  # fresh user:// (no real profile / skills)
        env = dict(os.environ, XDG_DATA_HOME=tmp)
        godot = os.environ.get("GODOT", os.path.expanduser("~/bin/godot"))
        try:
            out = subprocess.run([godot, "--headless", "--fixed-fps", "60", "--path", ROOT,
                                  "res://tools/balance/balance_match.tscn", "--",
                                  "seed=%d" % seed, "size=%d" % a.size, "max_s=%d" % a.max_s,
                                  "mode=" + a.mode, "map=" + a.map, "diff=%d" % a.diff],
                                 capture_output=True, text=True, env=env, timeout=a.max_s * 2 + 300).stdout
        except subprocess.TimeoutExpired:
            return seed, [], None
    m = MATCH.search(out)
    return seed, [json.loads(x) for x in LIFE.findall(out)], json.loads(m.group(1)) if m else None


def wilson(k, n, z=1.96):
    """95% Wilson score interval for k successes in n trials -> (lo, hi)."""
    if n == 0:
        return 0.0, 1.0
    p = k / n
    d = 1 + z * z / n
    c = (p + z * z / (2 * n)) / d
    h = z * math.sqrt(p * (1 - p) / n + z * z / (4 * n * n)) / d
    return max(0.0, c - h), min(1.0, c + h)


def aggregate(lives, key):
    rows = {}
    for L in lives:
        r = rows.setdefault(L[key], {"n": 0, "won": 0, "dealt": 0.0, "taken": 0.0, "kills": 0, "alive": 0.0})
        r["n"] += 1
        r["won"] += 1 if L["won"] else 0
        r["dealt"] += L["dealt"]
        r["taken"] += L["taken"]
        r["kills"] += L["kills"]
        r["alive"] += L["alive_s"]
    return rows


def table(rows, title):
    out = ["### " + title, "",
           "| | lives | win rate (95% CI) | dealt/life | taken/life | dealt/taken | kills/life | survival s |",
           "|---|---:|---|---:|---:|---:|---:|---:|"]
    for name, r in sorted(rows.items(), key=lambda kv: -kv[1]["won"] / max(1, kv[1]["n"])):
        n = r["n"]
        lo, hi = wilson(r["won"], n)
        out.append("| %s | %d | %.0f%% (%.0f-%.0f) | %.0f | %.0f | %.2f | %.2f | %.0f |" % (
            name, n, 100 * r["won"] / n, 100 * lo, 100 * hi, r["dealt"] / n, r["taken"] / n,
            r["dealt"] / max(1.0, r["taken"]), r["kills"] / n, r["alive"] / n))
    return "\n".join(out)


DIFFS = ["Easy", "Normal", "Medium", "Hard", "Elite"]


def pct(xs, p):
    """Nearest-rank percentile of a sorted list."""
    return xs[min(len(xs) - 1, max(0, math.ceil(p / 100 * len(xs)) - 1))]


def report(lives, matches, a):
    lines = ["# Balance report (%s)" % datetime.datetime.now().strftime("%Y-%m-%d %H:%M"), "",
             "%d all-bot matches (%s bots, %s, %s, team size %d, up to %d s each, 5-mech squads of random mech + "
             "weapon-family picks), %d mech lives. Win rate = share of lives whose team won the match. "
             "Overlapping intervals = no demonstrated difference." % (len(matches), DIFFS[a.diff], a.mode,
             os.path.basename(a.map) or "default map", a.size, a.max_s, len(lives)), "",
             table(aggregate(lives, "mech"), "Per mech"), "", table(aggregate(lives, "wpn"), "Per weapon family"), ""]
    draws = sum(1 for m in matches if m["winner"] < 0)
    lines.append("Matches: %d, team 0 won %d, team 1 won %d, unfinished %d (hit --max-s)." % (
        len(matches), sum(1 for m in matches if m["winner"] == 0), sum(1 for m in matches if m["winner"] == 1), draws))
    t = sorted(m["t"] for m in matches if m["winner"] >= 0)  # T285: how long finished matches ran
    if t:
        lines.append("Length of finished matches (s): p50 %.0f, p90 %.0f, max %.0f." % (
            pct(t, 50), pct(t, 90), t[-1]))
    return "\n".join(lines) + "\n"


def selftest():
    lo, hi = wilson(5, 10)
    assert abs(lo - 0.2366) < 1e-3 and abs(hi - 0.7634) < 1e-3, (lo, hi)
    assert wilson(0, 0) == (0.0, 1.0)
    lives = [{"mech": "A", "wpn": "X", "won": True, "dealt": 100, "taken": 50, "kills": 1, "alive_s": 30},
             {"mech": "A", "wpn": "Y", "won": False, "dealt": 0, "taken": 50, "kills": 0, "alive_s": 10},
             {"mech": "B", "wpn": "X", "won": True, "dealt": 20, "taken": 0, "kills": 0, "alive_s": 50}]
    r = aggregate(lives, "mech")
    assert r["A"]["n"] == 2 and r["A"]["won"] == 1 and r["A"]["dealt"] == 100 and r["B"]["won"] == 1
    t = table(r, "t")
    assert "| B | 1 | 100%" in t and "| A | 2 | 50% (9-91)" in t, t
    assert pct([1, 2, 3, 4, 5, 6, 7, 8, 9, 10], 50) == 5 and pct([1, 2, 3, 4, 5, 6, 7, 8, 9, 10], 90) == 9
    assert pct([7], 90) == 7
    print("selftest ok")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("-n", type=int, default=24, help="matches")
    ap.add_argument("--size", type=int, default=3, help="team size")
    ap.add_argument("--max-s", type=int, default=420, help="simulated seconds per match")
    ap.add_argument("--seed0", type=int, default=1)
    ap.add_argument("--jobs", type=int, default=max(1, (os.cpu_count() or 2) // 2))
    ap.add_argument("--mode", default="beacons", help="beacons | deathmatch (T285: timer off)")
    ap.add_argument("--map", default="", help="MapDef path, e.g. res://resources/maps/Badlands.tres")
    ap.add_argument("--diff", type=int, default=4, help="bot difficulty 0..4 (Elite)")
    ap.add_argument("--selftest", action="store_true")
    a = ap.parse_args()
    if a.selftest:
        selftest()
        return 0
    with ThreadPoolExecutor(a.jobs) as ex:
        res = list(ex.map(lambda s: run_match(s, a), range(a.seed0, a.seed0 + a.n)))
    lives = [L for _, ls, _ in res for L in ls]
    matches = [m for _, _, m in res if m is not None]
    failed = [s for s, _, m in res if m is None]
    if not matches:
        print("no match finished (check godot / the scene)")
        return 1
    text = report(lives, matches, a)
    if failed:
        text += "Failed seeds (no result): %s\n" % ", ".join(map(str, failed))
    os.makedirs(os.path.join(ROOT, "build", "balance"), exist_ok=True)
    path = os.path.join(ROOT, "build", "balance", "balance_%s.md" % datetime.datetime.now().strftime("%Y%m%d_%H%M%S"))
    open(path, "w").write(text)
    print(text)
    print("report: " + path)
    return 0


if __name__ == "__main__":
    sys.exit(main())
