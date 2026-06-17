"""transform_desync oracle: each client's view of a mech must track the server.

For every networked peer (roles other than "server") and every mech both the
client and the server logged, compare pos / rot_local / rot_global tick-by-tick
on the ticks they share. Client logs are interpolated (V38), so brief lag is
expected -- a FAIL requires divergence to persist for `persist_ticks`
consecutive common ticks. The first mech/field that persistently diverges is
reported with a pattern classification.

Tick alignment caveat: both peers reset tick=0 at match start, so common ticks
line up to within the match-start handshake. The persist window absorbs a small
constant offset; a true desync is meters and many ticks, well clear of it.
"""
from . import base

NAME = "transform_desync"

# Cross-peer tolerances. Looser than the determinism gate: a client interpolates
# remote mechs, so sub-meter / small-angle lag is normal. Real desync is meters.
DEFAULTS = {"pos_eps": 1.5, "rot_epsilon": 0.05, "persist_ticks": 5}

FIELDS = ("pos", "rot_local", "rot_global")


def _field_eps(field, th):
    return th["pos_eps"] if field == "pos" else th["rot_epsilon"]


def _first_persistent_run(ticks_mags, eps, persist):
    """Return the start tick of the first run of >= persist consecutive entries
    with magnitude > eps, or None. ticks_mags is ordered by tick."""
    run_start = None
    run_len = 0
    for t, m in ticks_mags:
        if m > eps:
            if run_start is None:
                run_start = t
            run_len += 1
            if run_len >= persist:
                return run_start
        else:
            run_start = None
            run_len = 0
    return None


def run(ctx):
    primary = ctx["primary"]
    if "server" not in primary:
        return base.verdict(NAME, base.SKIP, note="no server stream to compare against")
    clients = [r for r in primary if r != "server"]
    if not clients:
        return base.verdict(NAME, base.SKIP, note="no client peers in run")
    th = {**DEFAULTS, **ctx.get("thresholds", {})}
    persist = int(th["persist_ticks"])
    server = primary["server"]
    server_ticks = set(server.ticks)

    worst = None  # (first_tick, verdict-dict) -- earliest persistent divergence wins
    total_checked = 0
    for role in sorted(clients):
        client = primary[role]
        common = [t for t in client.ticks if t in server_ticks]
        for mid in client.mech_ids:
            for field in FIELDS:
                eps = _field_eps(field, th)
                series = []
                for t in common:
                    cs = client.at(t, mid)
                    ss = server.at(t, mid)
                    if cs is None or ss is None:
                        continue
                    series.append((t, base.vmax_diff(cs[field], ss[field])))
                if not series:
                    continue
                total_checked += 1
                onset = _first_persistent_run(series, eps, persist)
                if onset is None:
                    continue
                pattern, ptick, peak = base.classify_pattern(series, eps)
                first_tick = onset if ptick is None else min(onset, ptick)
                note = ("%s vs server: %s diverges > %.4g for >=%d ticks from tick %d (peak %.4f)"
                        % (role, field, eps, persist, onset, peak))
                v = base.verdict(NAME, base.FAIL, mech_id=mid, first_tick=first_tick,
                                 field=field, magnitude=round(peak, 5),
                                 pattern=pattern, peer=role, note=note)
                if worst is None or first_tick < worst[0]:
                    worst = (first_tick, v)
    if worst is not None:
        return worst[1]
    return base.verdict(NAME, base.PASS,
                        note="all client transforms track server within tolerance (%d mech/field series)" % total_checked)
