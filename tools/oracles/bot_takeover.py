"""bot_takeover oracle (T153, T123): when a client leaves mid-match (quit or
killed), the server hands its live mech to the bot AI and the match goes on.
Server log: `[Harness] peer_disconnected id=N at sync tick T`. In the server's
snapshots, every live mech owned by N (owner_peer_id stays N by V35) must
travel > `takeover_min_move` m within `takeover_window` ticks after T (the
leaver's script stood still, so movement = the bot driving), unless it died.
A SIGKILLed client (`[Harness] action kill_client` in its log) never says
goodbye: its mech (from its `input override done ... (mech X` line) must be
moving within `takeover_kill_window` ticks of the end of its log (T167).
"""
import glob
import math
import os
import re

from . import base

NAME = "bot_takeover"
DEFAULTS = {"takeover_window": 600, "takeover_min_move": 2.0, "takeover_kill_window": 900}


def run(ctx):
    path = os.path.join(ctx.get("run_dir") or "", "server.log")
    text = open(path, errors="replace").read() if os.path.exists(path) else ""
    gone = [(int(m.group(1)), int(m.group(2)))
            for m in re.finditer(r"\[Harness\] peer_disconnected id=(\d+) at sync tick (-?\d+)", text)]
    th = {**DEFAULTS, **ctx.get("thresholds", {})}
    server = ctx["primary"]["server"]
    killed = []
    for path in sorted(glob.glob(os.path.join(ctx.get("run_dir") or "", "*.log"))):
        role, ltext = os.path.basename(path)[: -len(".log")], open(path, errors="replace").read()
        m = re.search(r"input override done for \S+ \(mech ([^,\s]+)", ltext)
        if "[Harness] action kill_client" in ltext and m and ctx["primary"].get(role) and ctx["primary"][role].ticks:
            killed.append((role, m.group(1), ctx["primary"][role].ticks[-1]))
    for role, mid, t0 in killed:
        series = [s for s in server.snaps if s["mech_id"] == mid and t0 <= s["tick"] <= t0 + th["takeover_kill_window"]]
        if any(s["health"] <= 0 for s in series):
            continue
        moved = max((math.dist(series[0]["pos"], s["pos"]) for s in series), default=0.0)
        if moved < th["takeover_min_move"]:
            return base.verdict(NAME, base.FAIL, peer=role, mech_id=mid, first_tick=t0, magnitude=round(moved, 2),
                                note="%s killed at tick %d; its mech %s moved %.2f m in %d ticks (server never noticed?)"
                                     % (role, t0, mid, moved, th["takeover_kill_window"]))
    if not gone and not killed:
        return base.verdict(NAME, base.SKIP, note="no client left mid-match")
    for pid, t0 in gone:
        if not any(s.get("owner") == pid for s in server.snaps):
            continue  # never flew a mech (e.g. a refused mid-match joiner)
        mine = [s for s in server.snaps if s.get("owner") == pid and t0 <= s["tick"] <= t0 + th["takeover_window"]]
        if not mine:
            return base.verdict(NAME, base.FAIL, first_tick=t0,
                                note="peer %d left at tick %d: server logged none of its mechs after" % (pid, t0))
        for mid in sorted({s["mech_id"] for s in mine}):
            series = [s for s in mine if s["mech_id"] == mid]
            if any(s["health"] <= 0 for s in series):
                continue  # died before or while the bot took over
            moved = max(math.dist(series[0]["pos"], s["pos"]) for s in series)
            if moved < th["takeover_min_move"]:
                return base.verdict(NAME, base.FAIL, mech_id=mid, first_tick=t0, magnitude=round(moved, 2),
                                    note="peer %d left at tick %d; its mech %s moved only %.2f m in %d ticks (no bot?)"
                                         % (pid, t0, mid, moved, th["takeover_window"]))
    return base.verdict(NAME, base.PASS, note="%d leaver(s), %d killed: bot drove each live mech" % (len(gone), len(killed)))
