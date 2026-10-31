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


def run(ctx):
    path = os.path.join(ctx.get("run_dir") or "", "server.log")
    m = re.search(r"\[Harness\] live at sync tick (\d+)", open(path, errors="replace").read()) if os.path.exists(path) else None
    if m is None:
        return base.verdict(NAME, base.SKIP, note="no live tick logged")
    live = int(m.group(1))
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
