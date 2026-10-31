"""latency_recovery oracle (T151): after any network trouble (the
outage_recovery scenario blacks the link out for 1.5 s mid-fight), every
client must end the run agreeing with the server. Per-tick oracles tolerate
short lag; this one asks the end-state question: over the last
`recovery_tail_ticks` of the run, each client's view of every mech (pos,
health, per-slot ammo, lock + eligible target) and of every beacon (owner,
state) must match the server within the usual cross-peer skew window. A
dropped reliable-but-never-resent change, or a state that only syncs on
change and missed its change, shows up here as a permanent gap.
"""
from . import base

NAME = "latency_recovery"

DEFAULTS = {"recovery_tail_ticks": 30, "pos_eps": 1.5, "hp_eps": 1.0}


def _mech_gap(ss, cs, th):
    if base.vmax_diff(ss["pos"], cs["pos"]) > th["pos_eps"]:
        return "pos"
    if abs(ss["health"] - cs["health"]) > th["hp_eps"]:
        return "health"
    if ss.get("ammo") != cs.get("ammo"):
        return "ammo"
    for f in ("lock_target", "eligible"):
        if ss.get(f) != cs.get(f):
            return f
    return None


def run(ctx):
    primary = ctx["primary"]
    if "server" not in primary:
        return base.verdict(NAME, base.SKIP, note="no server stream")
    th = {**DEFAULTS, **ctx.get("thresholds", {})}
    tail, skew = int(th["recovery_tail_ticks"]), base.CROSS_PEER_SKEW_TICKS
    server = primary["server"]
    checked = 0
    for role in base.client_roles(primary):
        client = primary[role]
        if not client.ticks:
            continue
        last = min(client.ticks[-1], server.ticks[-1]) - skew
        for mid in client.mech_ids:
            dead = server.at(last, mid)
            if dead is not None and dead.get("health", 1) <= 0:
                continue  # a corpse's weapons keep reloading server-side with broadcasts off; irrelevant
            for t in range(last - tail, last + 1):
                cs = client.at(t, mid)
                if cs is None:
                    continue
                checked += 1
                cands = [server.at(t + d, mid) for d in range(-skew - base.INTERP_LAG_TICKS, skew + 1)]
                gaps = [_mech_gap(ss, cs, th) for ss in cands if ss is not None]
                if gaps and all(gaps):
                    return base.verdict(NAME, base.FAIL, peer=role, mech_id=mid, first_tick=t, field=gaps[0],
                                        note="%s %s still disagrees with the server on %s at tick %d (end of run)"
                                             % (role, mid, gaps[0], t))
        for bid in client.beacon_ids:
            cb = client.beacon_at(last, bid)
            if cb is None:
                continue
            sbs = [server.beacon_at(last + d, bid) for d in range(-skew, skew + 1)]
            if not any(sb and sb["owner_team"] == cb["owner_team"] and sb["state"] == cb["state"] for sb in sbs):
                return base.verdict(NAME, base.FAIL, peer=role, mech_id=bid, first_tick=last, field="beacon",
                                    note="%s %s owner/state %s/%s never matches the server at end of run"
                                         % (role, bid, cb["owner_team"], cb["state"]))
    if checked == 0:
        return base.verdict(NAME, base.SKIP, note="no client end-of-run samples")
    return base.verdict(NAME, base.PASS, note="clients agree with the server at end of run (%d samples)" % checked)
