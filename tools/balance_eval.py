#!/usr/bin/env python3
"""T209: bot balance tester (report only -- it changes no stats).

Runs N headless all-bot matches (tools/balance/balance_match.tscn: every slot an Elite
bot, 5-mech squads of random mech + weapon-family picks, a different seed per match) and
reports per mech and per weapon family: lives sampled, win rate of the team the life was
on (95% Wilson interval), damage dealt / taken per life, kills per life, survival time.

  python3 tools/balance_eval.py -n 24            # ~6 min on 8 cores
  python3 tools/balance_eval.py -n 60 --size 4   # tighter intervals
  python3 tools/balance_eval.py --maps all --sizes 1,3,5 -n 4   # T243: every map x size, 4 each
  python3 tools/balance_eval.py --selftest       # check the aggregation maths

T243: also per map, each life's stall share (alive but not moving), and a mech-vs-mech matchup
table (damage traded, kills each way, the kill share's 95% interval -- "!" where it excludes an
even split, i.e. one mech is shown to beat the other). Raw data: build/balance/<stamp>.json.

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
PAIR = re.compile(r"^\[bal-pair\] (\{.*\})$", re.M)
MAPS = ["MathTemple", "Badlands", "City", "Forest", "Giza", "Swamp", "Factory", "Corvette"]


def run_match(job, a):
    seed, map_path, size = job
    with tempfile.TemporaryDirectory() as tmp:  # fresh user:// (no real profile / skills)
        env = dict(os.environ, XDG_DATA_HOME=tmp)
        godot = os.environ.get("GODOT", os.path.expanduser("~/bin/godot"))
        try:
            out = subprocess.run([godot, "--headless", "--fixed-fps", "60", "--path", ROOT,
                                  "res://tools/balance/balance_match.tscn", "--",
                                  "seed=%d" % seed, "size=%d" % size, "max_s=%d" % a.max_s,
                                  "mode=" + a.mode, "map=" + map_path, "diff=%d" % a.diff],
                                 capture_output=True, text=True, env=env, timeout=a.max_s * 2 + 300).stdout
        except subprocess.TimeoutExpired:
            return seed, [], None, []
    m = MATCH.search(out)
    return (seed, [json.loads(x) for x in LIFE.findall(out)], json.loads(m.group(1)) if m else None,
            [json.loads(x) for x in PAIR.findall(out)])


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
        r = rows.setdefault(L.get(key, "?"), {"n": 0, "won": 0, "dealt": 0.0, "taken": 0.0, "kills": 0, "alive": 0.0, "stall": 0.0})
        r["stall"] += L.get("stall", 0.0)
        r["n"] += 1
        r["won"] += 1 if L["won"] else 0
        r["dealt"] += L["dealt"]
        r["taken"] += L["taken"]
        r["kills"] += L["kills"]
        r["alive"] += L["alive_s"]
    return rows


def table(rows, title):
    out = ["### " + title, "",
           "| | lives | win rate (95% CI) | dealt/life | taken/life | dealt/taken | kills/life | survival s | stalled |",
           "|---|---:|---|---:|---:|---:|---:|---:|---:|"]
    for name, r in sorted(rows.items(), key=lambda kv: -kv[1]["won"] / max(1, kv[1]["n"])):
        n = r["n"]
        lo, hi = wilson(r["won"], n)
        out.append("| %s | %d | %.0f%% (%.0f-%.0f) | %.0f | %.0f | %.2f | %.2f | %.0f | %.0f%% |" % (
            name, n, 100 * r["won"] / n, 100 * lo, 100 * hi, r["dealt"] / n, r["taken"] / n,
            r["dealt"] / max(1.0, r["taken"]), r["kills"] / n, r["alive"] / n, 100 * r["stall"] / n))
    return "\n".join(out)


def matchups(pairs):
    """T243: unordered mech pairs -> damage and kills each way (mirror matches skipped)."""
    m = {}
    for p in pairs:
        a, b = p["att"], p["vic"]
        if a == b or "?" in (a, b):
            continue
        k = tuple(sorted((a, b)))
        r = m.setdefault(k, {"dmg": {k[0]: 0.0, k[1]: 0.0}, "kills": {k[0]: 0, k[1]: 0}})
        r["dmg"][a] += p["dmg"]
        r["kills"][a] += p["kills"]
    return m


def matchup_table(m):
    out = ["### Mech vs mech", "",
           "Kill share of the first mech (95% CI); \"!\" = the interval excludes 50%: one mech is shown to win the pairing.", "",
           "| A | B | damage A>B | damage B>A | kills A>B | kills B>A | A kill share |", "|---|---|---:|---:|---:|---:|---|"]
    for (a, b), r in sorted(m.items()):
        ka, kb = r["kills"][a], r["kills"][b]
        lo, hi = wilson(ka, ka + kb)
        flag = " !" if ka + kb and (hi < 0.5 or lo > 0.5) else ""
        share = "%.0f%% (%.0f-%.0f)%s" % (100 * ka / (ka + kb), 100 * lo, 100 * hi, flag) if ka + kb else "-"
        out.append("| %s | %s | %.0f | %.0f | %d | %d | %s |" % (a, b, r["dmg"][a], r["dmg"][b], ka, kb, share))
    return "\n".join(out)


DIFFS = ["Easy", "Normal", "Medium", "Hard", "Elite"]


def pct(xs, p):
    """Nearest-rank percentile of a sorted list."""
    return xs[min(len(xs) - 1, max(0, math.ceil(p / 100 * len(xs)) - 1))]


def report(lives, matches, a, pairs=()):
    lines = ["# Balance report (%s)" % datetime.datetime.now().strftime("%Y-%m-%d %H:%M"), "",
             "%d all-bot matches (%s bots, %s, maps %s, team sizes %s, up to %d s each, 5-mech squads of random mech + "
             "weapon-family picks), %d mech lives. Win rate = share of lives whose team won the match. "
             "Overlapping intervals = no demonstrated difference. Stalled = share of a life spent alive and not moving."
             % (len(matches), DIFFS[a.diff], a.mode, ", ".join(sorted({os.path.basename(p) or "default" for p in a.map_paths})),
                ", ".join(map(str, a.size_list)), a.max_s, len(lives)), "",
             table(aggregate(lives, "mech"), "Per mech"), "", table(aggregate(lives, "wpn"), "Per weapon family"), ""]
    if len(a.map_paths) > 1:
        lines += [table(aggregate(lives, "map"), "Per map"), ""]
    if pairs:
        lines += [matchup_table(matchups(pairs)), ""]
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
    m = matchups([{"att": "K", "vic": "E", "dmg": 10, "kills": 1}, {"att": "E", "vic": "K", "dmg": 90, "kills": 9},
                  {"att": "E", "vic": "E", "dmg": 5, "kills": 1}])
    assert list(m) == [("E", "K")] and m[("E", "K")]["kills"] == {"E": 9, "K": 1}, m
    assert "| E | K | 90 | 10 | 9 | 1 | 90% (60-98) ! |" in matchup_table(m), matchup_table(m)
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
    ap.add_argument("--maps", default="", help="T243: 'all' or comma map names (MathTemple,City,...); -n per map x size")
    ap.add_argument("--sizes", default="", help="T243: comma team sizes, e.g. 1,3,5 (default --size)")
    ap.add_argument("--selftest", action="store_true")
    a = ap.parse_args()
    if a.selftest:
        selftest()
        return 0
    names = MAPS if a.maps == "all" else [x for x in a.maps.split(",") if x]
    a.map_paths = ["res://resources/maps/%s.tres" % x for x in names] or [a.map]
    a.size_list = [int(x) for x in a.sizes.split(",") if x] or [a.size]
    jobs = [(a.seed0 + i, mp, sz) for mp in a.map_paths for sz in a.size_list for i in range(a.n)]
    with ThreadPoolExecutor(a.jobs) as ex:
        res = list(ex.map(lambda j: run_match(j, a), jobs))
    lives = [L for _, ls, _, _ in res for L in ls]
    matches = [m for _, _, m, _ in res if m is not None]
    pairs = [p for _, _, _, ps in res for p in ps]
    failed = [s for s, _, m, _ in res if m is None]
    if not matches:
        print("no match finished (check godot / the scene)")
        return 1
    text = report(lives, matches, a, pairs)
    if failed:
        text += "Failed seeds (no result): %s\n" % ", ".join(map(str, failed))
    os.makedirs(os.path.join(ROOT, "build", "balance"), exist_ok=True)
    path = os.path.join(ROOT, "build", "balance", "balance_%s.md" % datetime.datetime.now().strftime("%Y%m%d_%H%M%S"))
    open(path, "w").write(text)
    json.dump({"lives": lives, "pairs": pairs, "matches": matches, "failed": failed,
               "args": {k: v for k, v in vars(a).items()}}, open(path[:-3] + ".json", "w"))
    print(text)
    print("report: " + path)
    return 0


if __name__ == "__main__":
    sys.exit(main())
