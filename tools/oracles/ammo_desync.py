"""ammo_desync oracle: after fire activity ceases and a settle window passes,
every peer must agree on every mech's per-slot ammo.

Ammo is mutated server-side (clients don't fire locally per V38), so agreement
requires the server to replicate ammo back to clients. Comparing mid-burst is
meaningless (RPC latency), and REFILLING mags regen during the settle window,
so the contract is: from `last fired event + ammo_settle_ticks` to end of run,
per-slot ammo must match exactly. Scenarios that want a persistent gap to be
detectable should pin FIXED-mag weapons (no regen masks the gap at the cap).
"""
from . import base

NAME = "ammo_desync"

DEFAULTS = {"ammo_settle_ticks": 120, "ammo_persist_ticks": 10}


def _ammo_gap(ss, cs):
    sa, ca = ss.get("ammo") or {}, cs.get("ammo") or {}
    slots = set(sa) | set(ca)
    return max((abs(float(sa.get(k, 0)) - float(ca.get(k, 0))) for k in slots), default=0.0)


def run(ctx):
    primary = ctx["primary"]
    if "server" not in primary:
        return base.verdict(NAME, base.SKIP, note="no server stream")
    clients = base.client_roles(primary)
    if not clients:
        return base.verdict(NAME, base.SKIP, note="no client peers")
    th = {**DEFAULTS, **ctx.get("thresholds", {})}
    settle = int(th["ammo_settle_ticks"])
    persist = int(th["ammo_persist_ticks"])
    server = primary["server"]

    # Fire activity is logged on the authoritative peer only (fire_weapon runs
    # server-side in MP), so the settle clock starts from server events.
    fired = [e["tick"] for e in server.events if e.get("type") == "fired"]
    if not fired:
        return base.verdict(NAME, base.SKIP, note="no fired events; scenario exercised no ammo")
    settle_start = max(fired) + settle

    worst = None
    checked = 0
    for role in clients:
        client = primary[role]
        for mid in client.mech_ids:
            series = [(t, m) for t, m in base.cross_series(server, client, mid, _ammo_gap)
                      if t >= settle_start]
            if not series:
                continue
            checked += 1
            onset = base.first_persistent_run(series, 0.0, persist)
            if onset is None:
                continue
            pattern, ptick, peak = base.classify_pattern(series, 0.0)
            first_tick = onset if ptick is None else min(onset, ptick)
            v = base.verdict(NAME, base.FAIL, mech_id=mid, first_tick=first_tick,
                             field="ammo", magnitude=round(peak, 1),
                             pattern=pattern, peer=role,
                             note="%s vs server: ammo gap for >=%d ticks after settle "
                                  "(from tick %d, peak %.0f rounds)"
                                  % (role, persist, onset, peak))
            if worst is None or first_tick < worst[0]:
                worst = (first_tick, v)
    if checked == 0:
        return base.verdict(NAME, base.SKIP,
                            note="settle window empty; raise duration_ticks past last fire + %d" % settle)
    if worst is not None:
        return worst[1]
    return base.verdict(NAME, base.PASS,
                        note="post-settle ammo agrees on all peers (%d mech series)" % checked)
