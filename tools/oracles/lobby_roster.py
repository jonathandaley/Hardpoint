"""lobby_roster oracle (T160, B44): after the server returns everyone to the
lobby (harness action return_to_lobby = V40 _rpc_change_scene), the server's
lobby must still list every connected peer, accept the clients' squads, and the
finished match's roster must be cleared. Harness prints
`[Harness] lobby_check peers=N expected=M squads=S roster=R` 90 ticks later.
"""
import os
import re

from . import base

NAME = "lobby_roster"


def run(ctx):
    path = os.path.join(ctx.get("run_dir") or "", "server.log")
    if not os.path.exists(path):
        return base.verdict(NAME, base.SKIP, note="no server.log")
    m = re.search(r"\[Harness\] lobby_check peers=(\d+) expected=(\d+) squads=(\d+) roster=(\d+)",
                  open(path, errors="replace").read())
    if m is None:
        if "action return_to_lobby" in open(path, errors="replace").read():
            return base.verdict(NAME, base.FAIL, note="return_to_lobby ran but the server never reached the lobby "
                                                      "(no lobby_check before the run ended)")
        return base.verdict(NAME, base.SKIP, note="no lobby_check (no return_to_lobby action)")
    peers, expected, squads, roster = map(int, m.groups())
    problems = []
    if peers != expected:
        problems.append("lobby lists %d of %d peers" % (peers, expected))
    if squads < expected - 1:
        problems.append("only %d of %d client squads accepted" % (squads, expected - 1))
    if roster:
        problems.append("finished match roster still set (%d entries)" % roster)
    if problems:
        return base.verdict(NAME, base.FAIL, magnitude=expected - peers, note="after return to lobby: " + "; ".join(problems))
    return base.verdict(NAME, base.PASS, note="lobby kept all %d peers, client squads accepted, roster cleared" % peers)
