"""menu_flow oracle (T164): the run reached the match through the real menus
(Harness "menu": true) and the squad each player picked in the lobby is what
spawned, on every peer (V39: lobby squad -> roster -> Arena spawn).

FAIL on a `[Harness] MENU FAIL (<role>): ...` line (button hidden, covered or
disabled, an item missing, a step that never came), or when a peer's slot-0
pick (max_hp of the mech def + weapon scenes) differs from the mech that peer
owns in any peer's `[Harness] spawned` lines. SKIP when nothing was picked.
"""
import glob
import json
import os
import re

from . import base

NAME = "menu_flow"
_FAIL = re.compile(r"\[Harness\] MENU FAIL \((\w+)\): (.*)")
_PICK = re.compile(r"\[Harness\] menu_pick peer=(\d+) max_hp=(-?\d+) weapons=(\[.*?\]) ")
_SPAWN = re.compile(r"\[Harness\] spawned owner=(\d+) max_hp=(-?\d+) weapons=(\[.*?\]) ")


def run(ctx):
    picks, spawns = {}, {}
    for path in sorted(glob.glob(os.path.join(ctx.get("run_dir") or "", "*.log"))):
        role = os.path.basename(path)[: -len(".log")]
        text = open(path, errors="replace").read()
        m = _FAIL.search(text)
        if m:
            return base.verdict(NAME, base.FAIL, peer=m.group(1), note="menu step failed: " + m.group(2)[:160])
        for p in _PICK.finditer(text):
            picks[int(p.group(1))] = (int(p.group(2)), json.loads(p.group(3)))
        spawns[role] = {int(s.group(1)): (int(s.group(2)), json.loads(s.group(3))) for s in _SPAWN.finditer(text)}
    if not picks:
        return base.verdict(NAME, base.SKIP, note="no menu_pick lines (not a menu-flow run)")
    seen = [r for r in spawns if spawns[r]]
    if not seen:
        return base.verdict(NAME, base.FAIL, note="picked in the lobby but no peer reached a match")
    for role in seen:
        for pid, want in picks.items():
            got = spawns[role].get(pid)
            if got != want:
                return base.verdict(NAME, base.FAIL, peer=role, field="squad",
                                    note="peer %d picked max_hp/weapons %s, %s shows %s" % (pid, want, role, got))
    return base.verdict(NAME, base.PASS, note="%d lobby picks spawned as chosen on %d peers" % (len(picks), len(seen)))
