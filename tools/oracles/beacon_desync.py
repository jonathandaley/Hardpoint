"""beacon_desync oracle: beacon ownership, state, and capture progress on every
client must track the server.

Server runs capture logic (V20); clients receive owner/state via the reliable
_sync_state RPC and progress via the periodic unreliable _sync_progress RPC
(T105 / V33: visible within 200ms). So: owner_team + state mismatches may only
be transient (RPC in flight) -- a mismatch persisting past the lag window is a
FAIL; progress gets a magnitude epsilon on top since it's sampled at 5Hz.
"""
from . import base

NAME = "beacon_desync"

# 15 ticks = 250ms at 60Hz: V33's 200ms visibility bound plus scheduling slack.
# progress is normalized 0..1 over capture_time (3s), synced at 5Hz -> one
# broadcast interval is ~0.067; eps 0.15 gives >2x headroom.
DEFAULTS = {"beacon_lag_ticks": 15, "beacon_progress_eps": 0.15}


def _series(server, client, bid, mag_fn):
    st = set(b["tick"] for b in server.beacons if b["beacon_id"] == bid)
    out = []
    for t in sorted(b["tick"] for b in client.beacons if b["beacon_id"] == bid):
        if t not in st:
            continue
        sb, cb = server.beacon_at(t, bid), client.beacon_at(t, bid)
        if sb is not None and cb is not None:
            out.append((t, mag_fn(sb, cb)))
    return out


def run(ctx):
    primary = ctx["primary"]
    if "server" not in primary:
        return base.verdict(NAME, base.SKIP, note="no server stream")
    clients = base.client_roles(primary)
    if not clients:
        return base.verdict(NAME, base.SKIP, note="no client peers")
    server = primary["server"]
    if not server.beacons:
        return base.verdict(NAME, base.SKIP, note="no beacon rows logged (pre-M2.1 run?)")
    th = {**DEFAULTS, **ctx.get("thresholds", {})}
    lag = int(th["beacon_lag_ticks"])
    peps = float(th["beacon_progress_eps"])

    worst = None
    checked = 0
    for role in clients:
        client = primary[role]
        for bid in server.beacon_ids:
            checks = [
                ("owner_team", 0.0,
                 lambda sb, cb: 0.0 if sb.get("owner_team") == cb.get("owner_team") else 1.0),
                ("state", 0.0,
                 lambda sb, cb: 0.0 if sb.get("state") == cb.get("state") else 1.0),
                ("progress", peps,
                 lambda sb, cb: abs(float(sb.get("progress", 0)) - float(cb.get("progress", 0)))),
            ]
            for field, eps, fn in checks:
                series = _series(server, client, bid, fn)
                if not series:
                    continue
                checked += 1
                onset = base.first_persistent_run(series, eps, lag)
                if onset is None:
                    continue
                pattern, ptick, peak = base.classify_pattern(series, eps)
                first_tick = onset if ptick is None else min(onset, ptick)
                v = base.verdict(NAME, base.FAIL, mech_id=bid, first_tick=first_tick,
                                 field=field, magnitude=round(peak, 3),
                                 pattern=pattern, peer=role,
                                 note="%s vs server: %s.%s diverges > %d ticks from tick %d"
                                      % (role, bid, field, lag, onset))
                if worst is None or first_tick < worst[0]:
                    worst = (first_tick, v)
    if checked == 0:
        return base.verdict(NAME, base.SKIP, note="no common beacon ticks between peers")
    if worst is not None:
        return worst[1]
    return base.verdict(NAME, base.PASS,
                        note="beacon owner/state/progress track server (%d series)" % checked)
