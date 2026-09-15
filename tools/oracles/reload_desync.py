"""reload_desync oracle: every peer must agree on every mech's per-slot
reloading flag (drives the HUD reload bar).

Reload starts only at the server chokepoint (`_start_reload`, V38); clients
tick a cosmetic timer seeded by the B35 `_sync_reload_started` broadcast, so
the flag flips true ~RTT late and flips false at each peer's own timer expiry.
`reload_persist_ticks` absorbs both skews; a sustained mismatch means the
broadcast is missing or the cosmetic timer diverged. To avoid a vacuous pass
the oracle SKIPs unless the server stream shows at least one reload.
"""
from . import base

NAME = "reload_desync"

DEFAULTS = {"reload_persist_ticks": 20}


def _gap(ss, cs):
    sr, cr = ss.get("reloading") or {}, cs.get("reloading") or {}
    slots = set(sr) | set(cr)
    return float(sum(1 for k in slots if bool(sr.get(k)) != bool(cr.get(k))))


def run(ctx):
    primary = ctx["primary"]
    if "server" not in primary:
        return base.verdict(NAME, base.SKIP, note="no server stream")
    clients = base.client_roles(primary)
    if not clients:
        return base.verdict(NAME, base.SKIP, note="no client peers")
    th = {**DEFAULTS, **ctx.get("thresholds", {})}
    persist = int(th["reload_persist_ticks"])
    server = primary["server"]

    if not any(v for s in server.snaps for v in (s.get("reloading") or {}).values()):
        return base.verdict(NAME, base.SKIP,
                            note="no reload on server; scenario exercised no reloads")

    checked = 0
    for role in clients:
        client = primary[role]
        for mid in client.mech_ids:
            series = list(base.cross_series(server, client, mid, _gap))
            if not series:
                continue
            checked += 1
            onset = base.first_persistent_run(series, 0.0, persist)
            if onset is None:
                continue
            pattern, ptick, peak = base.classify_pattern(series, 0.0)
            return base.verdict(NAME, base.FAIL, mech_id=mid,
                                first_tick=onset if ptick is None else min(onset, ptick),
                                field="reloading", magnitude=round(peak, 1),
                                pattern=pattern, peer=role,
                                note="reloading flag mismatch for %s on %s persists >=%d ticks"
                                     % (mid, role, persist))
    if checked == 0:
        return base.verdict(NAME, base.SKIP, note="no comparable mech series")
    return base.verdict(NAME, base.PASS,
                        note="reloading flags agree across peers (%d mech series, reloads exercised)" % checked)
