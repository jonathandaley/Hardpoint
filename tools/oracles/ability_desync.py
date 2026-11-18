"""ability_desync oracle (T468): every client's ability cooldowns for a mech must track the
server's -- the HUD's "RECHARGING n s" reads them on the client, and only the server runs the
ability timers (V38), so a client's copies come from the ability RPCs. A FAIL needs a gap over
`ability_eps` seconds that lasts `ability_persist_ticks` (RPC latency is a short lag, not a gap).
"""
from . import base

NAME = "ability_desync"

DEFAULTS = {"ability_eps": 0.5, "ability_persist_ticks": 30}


def _cd_gap(ss, cs):
    sa, ca = ss.get("abilities") or {}, cs.get("abilities") or {}
    return max((abs(float(sa.get(k, 0.0)) - float(ca.get(k, 0.0))) for k in set(sa) | set(ca)), default=0.0)


def run(ctx):
    primary = ctx["primary"]
    if "server" not in primary:
        return base.verdict(NAME, base.SKIP, note="no server stream")
    clients = base.client_roles(primary)
    if not clients:
        return base.verdict(NAME, base.SKIP, note="no client peers")
    th = {**DEFAULTS, **ctx.get("thresholds", {})}
    eps = float(th["ability_eps"])
    persist = int(th["ability_persist_ticks"])
    server = primary["server"]
    worst = None
    checked = 0
    for role in clients:
        client = primary[role]
        for mid in client.mech_ids:
            series = base.cross_series(server, client, mid, _cd_gap)
            if not series:
                continue
            checked += 1
            onset = base.first_persistent_run(series, eps, persist)
            if onset is None:
                continue
            pattern, ptick, peak = base.classify_pattern(series, eps)
            first_tick = onset if ptick is None else min(onset, ptick)
            v = base.verdict(NAME, base.FAIL, mech_id=mid, first_tick=first_tick, field="abilities",
                             magnitude=round(peak, 2), pattern=pattern, peer=role,
                             note="%s vs server: ability cooldown gap > %.2g s for >=%d ticks from tick %d (peak %.1f s)"
                                  % (role, eps, persist, onset, peak))
            if worst is None or first_tick < worst[0]:
                worst = (first_tick, v)
    if worst is not None:
        return worst[1]
    return base.verdict(NAME, base.PASS, note="client ability cooldowns track the server (%d mech series)" % checked)
