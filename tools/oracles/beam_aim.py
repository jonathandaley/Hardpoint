"""beam_aim oracle (T142, B-b): on the owning client's screen, the laser beam the
server reports (`_rpc_beam_fx` hit point) must land where the client's own
crosshair ray hits. LaserCannon logs `beam_check` {server_hit, local_hit} on the
owner for every beam tick it receives (harness only).

Only list this oracle in scenarios that fire the laser while the shooter is
settled (not turning or walking): mid-turn the server trails by input latency,
which is normal lag, not a desync. No checks at all = FAIL (vacuous coverage,
the B33 lesson).
"""
import math

from . import base

NAME = "beam_aim"

DEFAULTS = {"beam_eps_m": 0.3}


def run(ctx):
    th = {**DEFAULTS, **ctx.get("thresholds", {})}
    eps = float(th["beam_eps_m"])
    checks = []
    for role in base.client_roles(ctx["primary"]):
        for e in ctx["primary"][role].events:
            if e.get("type") == "beam_check":
                p = e["payload"]
                checks.append((math.dist(p["server_hit"], p["local_hit"]), e["tick"], role, e["mech_id"]))
    if not checks:
        return base.verdict(NAME, base.FAIL, note="no beam_check events: scenario never fired a client-owned laser")
    worst = max(checks)
    bad = [c for c in checks if c[0] > eps]
    if bad:
        return base.verdict(NAME, base.FAIL, peer=bad[0][2], mech_id=bad[0][3], first_tick=bad[0][1],
                            magnitude=round(worst[0], 3), field="beam_hit",
                            note="%d/%d beam ticks land > %.2f m from the owner's crosshair hit (worst %.2f m)"
                                 % (len(bad), len(checks), eps, worst[0]))
    return base.verdict(NAME, base.PASS, note="%d beam ticks land on the owner's crosshair (worst %.3f m)"
                                              % (len(checks), worst[0]))
