"""health_desync oracle: each client's HP for a mech must track the server.

HP is server-authoritative, pushed to clients via _sync_health RPC, so a client
can lag by the RPC latency. A FAIL requires the gap to persist for
`hp_persist_ticks` consecutive common ticks -- a real desync is a permanent gap
(e.g. dead on the server, alive on the client), not transient sync lag.
"""
from . import base

NAME = "health_desync"

DEFAULTS = {"hp_eps": 1.0, "hp_persist_ticks": 10}


def run(ctx):
    primary = ctx["primary"]
    if "server" not in primary:
        return base.verdict(NAME, base.SKIP, note="no server stream")
    clients = base.client_roles(primary)
    if not clients:
        return base.verdict(NAME, base.SKIP, note="no client peers")
    th = {**DEFAULTS, **ctx.get("thresholds", {})}
    eps = float(th["hp_eps"])
    persist = int(th["hp_persist_ticks"])
    server = primary["server"]

    worst = None
    checked = 0
    for role in clients:
        client = primary[role]
        for mid in client.mech_ids:
            series = base.cross_series(server, client, mid,
                                       lambda ss, cs: abs(ss["health"] - cs["health"]))
            if not series:
                continue
            checked += 1
            onset = base.first_persistent_run(series, eps, persist)
            if onset is None:
                continue
            pattern, ptick, peak = base.classify_pattern(series, eps)
            first_tick = onset if ptick is None else min(onset, ptick)
            v = base.verdict(NAME, base.FAIL, mech_id=mid, first_tick=first_tick,
                             field="health", magnitude=round(peak, 3),
                             pattern=pattern, peer=role,
                             note="%s vs server: HP gap > %.4g for >=%d ticks from tick %d (peak %.2f)"
                                  % (role, eps, persist, onset, peak))
            if worst is None or first_tick < worst[0]:
                worst = (first_tick, v)
    if worst is not None:
        return worst[1]
    return base.verdict(NAME, base.PASS,
                        note="all client HP tracks server within tolerance (%d mech series)" % checked)
