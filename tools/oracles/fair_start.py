"""fair_start oracle (T162): on a multiplayer server nothing simulates until
every client is in the match (Game.mp_live, V52). Harness prints
`[Harness] live at sync tick N`; no server-side mech may move or turn before N.
Pre-T162 the host's mech and bots ran while clients were still loading Arena
(~1 s on a lossy link when the reliable match-start had to be resent).
"""
import os
import re

from . import base

NAME = "fair_start"


def live_tick(run_dir):
    """N-th `live at` line of server.log; match N >= 2 of a session is judged in
    <run>/match<N>/ with the process logs one level up (T163)."""
    run_dir = (run_dir or "").rstrip("/")
    m = re.fullmatch(r"match(\d+)", os.path.basename(run_dir))
    path = os.path.join(os.path.dirname(run_dir) if m else run_dir, "server.log")
    if not os.path.exists(path):
        return None
    ticks = re.findall(r"\[Harness\] live at sync tick (\d+)", open(path, errors="replace").read())
    n = int(m.group(1)) if m else 1
    return int(ticks[n - 1]) if len(ticks) >= n else None


def run(ctx):
    live = live_tick(ctx.get("run_dir"))
    if live is None:
        return base.verdict(NAME, base.SKIP, note="no live tick logged")
    server = ctx["primary"]["server"]
    first = {}
    for s in server.snaps:
        if s["tick"] >= live:
            continue
        f = first.setdefault(s["mech_id"], s)
        if base.vmax_diff(f["pos"], s["pos"]) > 0.05 or s.get("aim") != f.get("aim"):
            return base.verdict(NAME, base.FAIL, mech_id=s["mech_id"], first_tick=s["tick"], magnitude=live,
                                note="%s moved at tick %d, before every client was in (live at %d)"
                                     % (s["mech_id"], s["tick"], live))
    return base.verdict(NAME, base.PASS, note="no server mech moved before live (tick %d)" % live)
