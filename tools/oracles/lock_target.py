"""lock_target oracle: lock-on integrity (covers B21/B23).

Two checks:
  1. No live lock on a dead/absent target. On the authoritative server stream,
     any mech whose lock_target is set must point at a mech that exists at that
     tick and has health > 0. A lock onto a corpse or a despawned body is the
     B21/B23 class -- flagged immediately (no persist window; it's a state bug,
     not sync lag).
  2. Cross-peer lock agreement. A client's lock_target for a mech must match the
     server's. Brief disagreement during lock acquisition is tolerated via
     `lock_persist_ticks`; a sustained mismatch is a desync.
"""
from . import base

NAME = "lock_target"

DEFAULTS = {"lock_persist_ticks": 8}


def run(ctx):
    primary = ctx["primary"]
    if "server" not in primary:
        return base.verdict(NAME, base.SKIP, note="no server stream")
    th = {**DEFAULTS, **ctx.get("thresholds", {})}
    persist = int(th["lock_persist_ticks"])
    server = primary["server"]

    # Check 1: dead/absent lock on the authoritative stream. Use a tick index to
    # avoid the O(ticks*snaps) rescan inside _dead_lock_scan's inner loop.
    bt = base.by_tick(server)
    for tick in server.ticks:
        snaps = bt[tick]
        for mid, s in snaps.items():
            tgt = s.get("lock_target")
            if tgt is None:
                continue
            tsnap = snaps.get(tgt)
            if tsnap is None:
                return base.verdict(NAME, base.FAIL, mech_id=mid, first_tick=tick,
                                    field="lock_target", pattern="sudden_jump",
                                    note="%s locks %r which is absent at tick %d" % (mid, tgt, tick))
            if tsnap.get("health", 0) <= 0:
                return base.verdict(NAME, base.FAIL, mech_id=mid, first_tick=tick,
                                    field="lock_target", pattern="sudden_jump",
                                    note="%s locks dead %r (hp %.1f) at tick %d (B21/B23)"
                                         % (mid, tgt, tsnap.get("health", 0), tick))

    # Check 2: cross-peer lock agreement.
    worst = None
    for role in base.client_roles(primary):
        client = primary[role]
        for mid in client.mech_ids:
            series = base.cross_series(server, client, mid,
                                       lambda ss, cs: 1.0 if ss.get("lock_target") != cs.get("lock_target") else 0.0)
            onset = base.first_persistent_run(series, 0.5, persist)
            if onset is None:
                continue
            ss = server.at(onset, mid)
            cs = client.at(onset, mid)
            v = base.verdict(NAME, base.FAIL, mech_id=mid, first_tick=onset,
                             field="lock_target", pattern="constant_offset", peer=role,
                             note="%s vs server: lock %r != %r for >=%d ticks from tick %d"
                                  % (role, cs.get("lock_target"), ss.get("lock_target"), persist, onset))
            if worst is None or onset < worst[0]:
                worst = (onset, v)
    if worst is not None:
        return worst[1]
    return base.verdict(NAME, base.PASS, note="no dead-locks; client locks agree with server")
