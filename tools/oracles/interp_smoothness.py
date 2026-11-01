"""interp_smoothness oracle (T150): a mech that moves every tick on the server
must also move (nearly) every tick on each client. Clients draw mechs from
20 Hz snapshots (V37); without real interpolation the client shows a stepped
20 Hz picture -- the mech stands still for 2 of every 3 physics ticks, then
jumps. Measured pre-T150: 63-66% stalled ticks for remote AND own mechs.

Per client mech: over ticks where the server mech moved >= `interp_min_move`,
the stall ratio (client displacement < 1e-4 m) must stay <= `interp_max_stall`.
Starvation under loss (buffer ran dry -> hold) also shows up as stalls.
"""
import math

from . import base, fair_start

NAME = "interp_smoothness"

DEFAULTS = {"interp_min_move": 0.02, "interp_max_stall": 0.15, "interp_min_samples": 30, "interp_warmup_ticks": 30}


def stall_ratios(server, client, min_move, warmup=30, live=None):
    """{mech_id: (moving_ticks, stalled_ticks)} for one client. The first
    `warmup` ticks after streaming begins are skipped: the interpolation buffer
    starts empty then (T162: mechs start moving right then). Streaming begins at
    the later of the mech's first client tick and the server's `live` tick (V52;
    B56: a client that loads early idles un-streamed until live)."""
    out = {}
    for mid in client.mech_ids:
        moving = stalled = 0
        first = next((t for t in client.ticks if client.at(t, mid) is not None), None)
        for t in client.ticks:
            if first is None or t < max(first, live or first) + warmup:
                continue
            a, b = client.at(t, mid), client.at(t + 1, mid)
            sa, sb = server.at(t, mid), server.at(t + 1, mid)
            if None in (a, b, sa, sb) or math.dist(sa["pos"], sb["pos"]) < min_move:
                continue
            moving += 1
            stalled += math.dist(a["pos"], b["pos"]) < 1e-4
        out[mid] = (moving, stalled)
    return out


def run(ctx):
    primary = ctx["primary"]
    if "server" not in primary:
        return base.verdict(NAME, base.SKIP, note="no server stream")
    th = {**DEFAULTS, **ctx.get("thresholds", {})}
    worst, checked = None, 0
    for role in base.client_roles(primary):
        for mid, (moving, stalled) in stall_ratios(primary["server"], primary[role], float(th["interp_min_move"]),
                                                   int(th["interp_warmup_ticks"]),
                                                   fair_start.live_tick(ctx.get("run_dir"))).items():
            if moving < int(th["interp_min_samples"]):
                continue
            checked += 1
            ratio = stalled / moving
            if ratio > float(th["interp_max_stall"]) and (worst is None or ratio > worst[0]):
                worst = (ratio, role, mid, moving, stalled)
    if worst:
        ratio, role, mid, moving, stalled = worst
        return base.verdict(NAME, base.FAIL, peer=role, mech_id=mid, magnitude=round(ratio, 3), field="pos",
                            note="%s %s stood still on %d of %d ticks it moved on the server (%.0f%%)"
                                 % (role, mid, stalled, moving, 100 * ratio))
    if checked == 0:
        return base.verdict(NAME, base.SKIP, note="no client mech moved long enough to judge")
    return base.verdict(NAME, base.PASS, note="%d client mech series move smoothly (stalls <= %.0f%%)"
                                              % (checked, 100 * float(th["interp_max_stall"])))
