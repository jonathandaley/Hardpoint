#!/usr/bin/env python3
"""T555: MP chaos playtests -- random full matches on the real dedicated server, every oracle on.

Usage: chaos.py [--seeds A-B | --seed N | --next N] [--jobs J] [--net clean|wifi|bad] [--keep] [--dry]
(--next N: the N seeds after the highest in build/chaos/results.jsonl -- the loop's idle batch)

Each seed builds one scenario (same seed = same scenario, so a failure replays with --seed N):
a map, mode, team size and bot fill; 2-3 clients that reach the server through the real menus
with a random hangar squad and random pilot skills, each flown by the game's bot AI through the
real input path (Harness "chaos": picks its next mech after a death, flies whatever it gets back
after a rejoin); a net profile; one or two matches; and lifecycle events at random ticks -- leave
mid-match and rejoin, self-destruct, killed by the server, F9 marks, the match ended early. Then
sync_compare runs the generic oracles plus agency / parity on every match.

Writes build/chaos/<seed>/ (scenario.json + run); passing runs are deleted unless --keep.
One line per match to build/chaos/results.jsonl. Exit 1 when any seed failed.
"""
import argparse
import json
import os
import queue
import random
import re
import shutil
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
OUT = os.path.join(REPO, "build", "chaos")
PORT_BASE = 9500  # + 10 per parallel job (account port +1, proxy +1000): clear of the suite's 89xx

ORACLES = ["dedicated", "menu_flow", "spawn_join", "team_assignment", "transform_desync", "health_desync",
           "ammo_desync", "reload_desync", "active_set_desync", "ability_desync", "lock_target",
           "beacon_desync", "friendly_fire", "crash_scan", "log_flood", "rpc_integrity", "loop_audio",
           "hit_confirm"]  # + sync_compare's auto set (world_invariants ... agency, parity)


def _lobby_lists():
    src = open(os.path.join(REPO, "scripts", "Lobby.gd")).read()
    maps = re.findall(r'"path":\s*"(res://resources/maps/\w+\.tres)"', src.split("const MODES")[0])
    modes = re.findall(r'\["(\w+)",\s*"[^"]+"\]', src.split("const MODES")[1].split("\n")[0])
    return maps, modes


def build(seed, net=None):
    """The scenario for `seed` (deterministic)."""
    rng = random.Random(seed)
    maps, modes = _lobby_lists()
    clients = rng.choice([2, 2, 3])
    team_size = rng.randint(max(2, (clients + 1) // 2), 4)
    matches = rng.choice([1, 1, 2])
    dur = rng.randint(2400, 3600)
    net = net or rng.choices(["clean", "wifi", "bad"], [4, 3, 2])[0]
    scen = {
        "name": "chaos_%d" % seed, "seed": seed, "dedicated": True, "menu": True, "chaos": True,
        "map_path": rng.choice(maps), "mode": rng.choice(modes), "matches": matches, "duration_ticks": dur,
        "server_opts": {"team_size": team_size, "min_players": clients, "bot_fill": rng.random() < 0.7},
        "net": None if net == "clean" else net,
        "peers": {"server": {}}, "actions": [], "oracles": list(ORACLES),
        # B123: bot-flown clients brawl -- a predicting client brushing a remote mech (where it sees it, a few
        # ticks in the past) spikes its error; dedicated_server allows the same (chaos_17: p95 0.17 clean)
        "thresholds": {"pred_p95_m": 0.25},
    }
    scen["server_opts"]["map_path"] = scen["map_path"]
    scen["server_opts"]["mode"] = scen["mode"]
    acts = scen["actions"]
    left = False
    for i in range(1, clients + 1):
        key = "client_%d" % i
        scen["peers"][key] = {"bot": True, "squad": "random", "skills": "random"}
        if matches == 1 and rng.random() < 0.35:  # leave and come back (one match only: see Harness chaos)
            t = rng.randint(400, dur - 1200)
            acts += [{"tick": t, "peer": key, "action": "pause_quit"},
                     {"tick": t + rng.randint(180, 900), "peer": key, "action": "rejoin"}]
            left = True
        if rng.random() < 0.3:
            acts.append({"tick": rng.randint(300, dur - 300), "peer": key, "action": "self_destruct"})
        if rng.random() < 0.3:
            acts.append({"tick": rng.randint(300, dur - 300), "peer": "server", "action": "kill_mech", "slot": key})
        if rng.random() < 0.25:
            acts.append({"tick": rng.randint(200, dur - 200), "peer": key, "action": "mark"})
    if matches == 2:
        end = rng.randint(dur // 2, dur - 300)
        acts.append({"tick": end, "peer": "server", "action": "end_match", "winner": rng.randint(0, 1), "match": 1})
        for a in acts:  # match 1's actions inside match 1 (chaos_19: an F9 on the results screen has no match to mark)
            if a["action"] != "end_match":
                a["tick"] = min(a["tick"], end - 120)
    if left:
        scen["oracles"] += ["peer_closed", "bot_takeover"]
    # ponytail: no profile_parity -- its formula leaves out skill bonuses, kill coins and bot opponents
    # (scripted scenarios check it); chaos checks that every peer agrees, not the arithmetic
    return scen


def summary(scen):
    acts = ",".join(sorted({a["action"] for a in scen["actions"]})) or "-"
    return "%s %s %s net=%s clients=%d team=%d bots=%s matches=%d acts=%s" % (
        scen["name"], os.path.basename(scen["map_path"])[:-5], scen["mode"], scen["net"] or "clean",
        len(scen["peers"]) - 1, scen["server_opts"]["team_size"], scen["server_opts"]["bot_fill"],
        scen["matches"], acts)


def run_one(seed, slots, args):
    slot = slots.get()  # a port block no other running seed holds
    try:
        return _run_one(seed, slot, args)
    finally:
        slots.put(slot)


def _run_one(seed, slot, args):
    scen = build(seed, args.net)
    scen["port"] = PORT_BASE + 10 * slot
    out = os.path.join(OUT, str(seed))
    shutil.rmtree(out, ignore_errors=True)
    os.makedirs(out)
    spath = os.path.join(out, "scenario.json")
    with open(spath, "w") as f:
        json.dump(scen, f, indent=1)
    timeout = scen["duration_ticks"] * scen["matches"] / 60.0 + 180.0
    cmd = [sys.executable, os.path.join(HERE, "run_scenario.py"), spath, os.path.join(out, "run"),
           "--timeout", str(timeout)] + (["--net", scen["net"]] if scen["net"] else [])
    rc = subprocess.run(cmd, capture_output=True, text=True).returncode
    lines, rows, bad = [], [], rc != 0
    if rc != 0:
        lines.append("  run_scenario exit %d" % rc)
    for n in range(1, scen["matches"] + 1):
        d = os.path.join(out, "run") if n == 1 else os.path.join(out, "run", "match%d" % n)
        if not os.path.exists(os.path.join(d, "server.jsonl")):
            lines.append("  match %d: no server log" % n)
            bad = True
            continue
        r = subprocess.run([sys.executable, os.path.join(HERE, "sync_compare.py"), spath, d],
                           capture_output=True, text=True)
        fails = [l.strip() for l in r.stdout.splitlines() if l.strip().startswith("[FAIL]")]
        bad = bad or r.returncode != 0
        lines += ["  m%d %s" % (n, f) for f in fails]
        rows.append({"seed": seed, "match": n, "pass": r.returncode == 0, "fails": fails, "scenario": summary(scen)})
    with open(os.path.join(OUT, "results.jsonl"), "a") as f:
        for row in rows:
            f.write(json.dumps(row) + "\n")
    if not bad and not args.keep:
        shutil.rmtree(os.path.join(out, "run"), ignore_errors=True)
    return seed, bad, summary(scen), lines


def main(argv):
    ap = argparse.ArgumentParser()
    ap.add_argument("--seeds", default=None, help="A-B")
    ap.add_argument("--seed", type=int, default=None)
    ap.add_argument("--next", type=int, default=None, help="the N seeds after the highest run so far")
    ap.add_argument("--jobs", type=int, default=2)
    ap.add_argument("--net", default=None)
    ap.add_argument("--keep", action="store_true")
    ap.add_argument("--dry", action="store_true", help="print the scenarios only")
    args = ap.parse_args(argv)
    if args.next is not None:
        top = 0
        if os.path.exists(os.path.join(OUT, "results.jsonl")):
            for line in open(os.path.join(OUT, "results.jsonl")):
                top = max(top, int(json.loads(line).get("seed", 0)))
        seeds = list(range(top + 1, top + 1 + args.next))
    elif args.seed is not None:
        seeds = [args.seed]
    else:
        a, b = (args.seeds or "1-4").split("-")
        seeds = list(range(int(a), int(b) + 1))
    if args.dry:
        for s in seeds:
            print(summary(build(s, args.net)))
        return 0
    os.makedirs(OUT, exist_ok=True)
    failed = 0
    slots = queue.Queue()
    for k in range(max(1, args.jobs)):
        slots.put(k)
    with ThreadPoolExecutor(max(1, args.jobs)) as pool:
        futs = [pool.submit(run_one, s, slots, args) for s in seeds]
        for fu in futs:
            seed, bad, desc, lines = fu.result()
            failed += bad
            print(("FAIL " if bad else "pass ") + desc, flush=True)
            for ln in lines:
                print(ln, flush=True)
    print("%d/%d seeds clean" % (len(seeds) - failed, len(seeds)))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
