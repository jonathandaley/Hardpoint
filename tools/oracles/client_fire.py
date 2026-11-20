"""client_fire oracle (T519): the server fires a client's mech's weapons when that client holds the
trigger -- at least `min_client_shots` `fired` events on the server stream from mechs owned by a client
peer (owner > 1 in the server's snapshots). The user's report: a client's first mech after the start
pick "could still move and look" but couldn't shoot (fire is server-side, V38). SKIPs unless a scenario
sets min_client_shots (so it never passes vacuously where it is wanted).
"""
from . import base

NAME = "client_fire"

DEFAULTS = {"min_client_shots": 0}


def run(ctx):
    primary = ctx["primary"]
    if "server" not in primary:
        return base.verdict(NAME, base.SKIP, note="no server stream")
    th = {**DEFAULTS, **ctx.get("thresholds", {})}
    need = int(th["min_client_shots"])
    if need <= 0:
        return base.verdict(NAME, base.SKIP, note="scenario sets no min_client_shots")
    server = primary["server"]
    client_mechs = {s.get("mech_id") for s in server.snaps if int(s.get("owner") or 0) > 1}
    shots = sum(1 for e in server.events if e.get("type") == "fired" and e.get("mech_id") in client_mechs)
    if shots < need:
        return base.verdict(NAME, base.FAIL, magnitude=need - shots,
                            note="the server fired %d shots for client mechs (want >= %d): their fire input never took" % (shots, need))
    return base.verdict(NAME, base.PASS, note="the server fired %d shots for client mechs" % shots)
