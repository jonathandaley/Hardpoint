"""peer_drop oracle (T167, auto-added): no player may lose the connection
mid-match unless the scenario made it leave. Server log: `[Harness]
peer_disconnected id=N at sync tick T`. In a scenario without lifecycle actions
(pause_quit, kill_client, rejoin, return_to_lobby), any drop before the end
window (live tick + duration_ticks - `drop_end_slack`) FAILs: a live player
was timed out (T167: a 6 s ENet cap dropped one on the `bad` profile).
"""
import os
import re

from . import base, fair_start

NAME = "peer_drop"
LIFECYCLE = {"pause_quit", "kill_client", "rejoin", "return_to_lobby", "quit_to_hangar"}


def run(ctx):
    scen = ctx.get("scenario") or {}
    if any(a.get("action") in LIFECYCLE for a in scen.get("actions", [])):
        return base.verdict(NAME, base.SKIP, note="scenario makes peers leave (bot_takeover / peer_closed judge it)")
    run_dir = ctx.get("run_dir") or ""
    path = os.path.join(run_dir, "server.log")
    live = fair_start.live_tick(run_dir)
    if not os.path.exists(path) or live is None:
        return base.verdict(NAME, base.SKIP, note="no server.log / live tick")
    end = live + int(scen.get("duration_ticks", 600)) - int(ctx.get("thresholds", {}).get("drop_end_slack", 120))
    for m in re.finditer(r"\[Harness\] peer_disconnected id=(\d+) at sync tick (-?\d+)", open(path, errors="replace").read()):
        if int(m.group(2)) < end:
            return base.verdict(NAME, base.FAIL, first_tick=int(m.group(2)),
                                note="peer %s dropped at tick %s, mid-match (run ends ~%d)" % (m.group(1), m.group(2), end + 120))
    return base.verdict(NAME, base.PASS, note="no mid-match drops")
