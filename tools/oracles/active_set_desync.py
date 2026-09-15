"""active_set_desync oracle: every peer must agree on every mech's weapon
active-set (the right-click fire subset, toggled by number keys).

Toggles run only at the server chokepoint (V38), so agreement requires the
B34 `_sync_active_set` broadcast. Brief mismatch during RPC flight is
tolerated via `active_set_persist_ticks`; a sustained mismatch is a desync
(the class where the client's WeaponHUD icon dim never updates). To avoid a
vacuous pass the oracle SKIPs unless the server stream shows at least one
active_set change, proving the scenario exercised a toggle.
"""
from . import base

NAME = "active_set_desync"

DEFAULTS = {"active_set_persist_ticks": 10}


def _gap(ss, cs):
    sa, ca = ss.get("active_set") or [], cs.get("active_set") or []
    if len(sa) != len(ca):
        return float(max(len(sa), len(ca)))
    return float(sum(1 for a, b in zip(sa, ca) if a != b))


def run(ctx):
    primary = ctx["primary"]
    if "server" not in primary:
        return base.verdict(NAME, base.SKIP, note="no server stream")
    clients = base.client_roles(primary)
    if not clients:
        return base.verdict(NAME, base.SKIP, note="no client peers")
    th = {**DEFAULTS, **ctx.get("thresholds", {})}
    persist = int(th["active_set_persist_ticks"])
    server = primary["server"]

    last = {}
    toggled = False
    for s in server.snaps:
        cur = tuple(s.get("active_set") or [])
        if last.get(s["mech_id"], cur) != cur:
            toggled = True
            break
        last[s["mech_id"]] = cur
    if not toggled:
        return base.verdict(NAME, base.SKIP,
                            note="no active_set change on server; scenario exercised no toggles")

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
                                field="active_set", magnitude=round(peak, 1),
                                pattern=pattern, peer=role,
                                note="active_set mismatch for %s on %s persists >=%d ticks"
                                     % (mid, role, persist))
    if checked == 0:
        return base.verdict(NAME, base.SKIP, note="no comparable mech series")
    return base.verdict(NAME, base.PASS,
                        note="active_set agrees across peers (%d mech series, toggles exercised)" % checked)
