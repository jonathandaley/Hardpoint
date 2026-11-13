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
# rot: sustained interp lag during a fast scripted turn (1.7 rad/s about-face in
# kill_confirm) measured 0.22 rad peak with the angular metric -- 0.5 gives >2x
# headroom while real rotation desyncs (wrong/frozen rotation) persist at
# ~radians. Slow-turn scenarios may tighten via thresholds.rot_epsilon.
# scale_eps (T142): body_scale is constant per mech; any gap is a replication bug.
DEFAULTS = {"pos_eps": 1.5, "rot_epsilon": 0.5, "scale_eps": 0.01, "persist_ticks": 5}

FIELDS = ("pos", "rot_local", "rot_global", "scale")


def _field_eps(field, th):
    return {"pos": th["pos_eps"], "scale": th["scale_eps"]}.get(field, th["rot_epsilon"])


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
    # T419 (dedicated_server@bad 2 in 5): once the server's match is over it stops moving mechs, but a
    # client hears of it a lossy link's worth later and keeps predicting its own mech forward -- that
    # isn't a desync. Ticks from the server's match_end on are not judged.
    end = next((int(e["tick"]) for e in (server.events or []) if e.get("type") == "match_end"), None)

    worst = None  # (first_tick, verdict-dict) -- earliest persistent divergence wins
    total_checked = 0
    skew = int(th.get("cross_peer_skew_ticks", base.CROSS_PEER_SKEW_TICKS))
    for role in sorted(clients):
        client = primary[role]
        for mid in client.mech_ids:
            for field in FIELDS:
                eps = _field_eps(field, th)
                if field == "scale":
                    def mag(ss, cs, f=field):  # absent in pre-T142 logs -> no evidence
                        return abs(cs[f] - ss[f]) if f in cs and f in ss else 0.0
                elif field == "pos":
                    def mag(ss, cs, f=field):
                        return base.vmax_diff(cs[f], ss[f])
                else:
                    # True rotation angle; componentwise diff false-fires on
                    # the quaternion double cover when yaw wraps past pi.
                    def mag(ss, cs, f=field):
                        return base.quat_angle(cs[f], ss[f])
                series = base.cross_series(server, client, mid, mag, skew)
                if end is not None:
                    series = [(t, m) for t, m in series if t < end]
                if not series:
                    continue
                total_checked += 1
                onset = base.first_persistent_run(series, eps, persist)
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
