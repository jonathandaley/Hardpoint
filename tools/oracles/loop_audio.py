"""loop_audio oracle (T155, V26): loop audio (arc/laser beam) must not outlive
its cause. Snapshot field `loops` = weapon slots whose loop player is audible.
FAIL when, on any peer, a mech's loop stays audible for more than
`loop_grace_ticks` while (a) the mech is dead, (b) the match has ended
(`match_end` event on that peer), or (c, clients) the server's same mech had no
audible loop anywhere in [t - grace, t + skew] -- a late beam packet restarted
it after the stop (unreliable start vs reliable stop ride different channels).
"""
from . import base

NAME = "loop_audio"
DEFAULTS = {"loop_grace_ticks": 45}


def _runs(ticks, bad, grace):
    """First (start, end) run of > grace consecutive bad ticks, else None."""
    start = prev = None
    for t in ticks:
        if bad(t):
            if start is None or t != prev + 1:
                start = t
            if t - start >= grace:
                return start, t
            prev = t
        else:
            start = None
    return None


def run(ctx):
    primary = ctx["primary"]
    if "server" not in primary:
        return base.verdict(NAME, base.SKIP, note="no server stream")
    th = {**DEFAULTS, **ctx.get("thresholds", {})}
    g, skew = int(th["loop_grace_ticks"]), base.CROSS_PEER_SKEW_TICKS
    server = primary["server"]
    heard = 0
    for role, log in primary.items():
        ends = [e["tick"] for e in log.events if e.get("type") == "match_end"]
        end = min(ends) if ends else None
        for mid in log.mech_ids:
            ticks = [t for t in log.ticks if log.at(t, mid) is not None]
            on = {t for t in ticks if log.at(t, mid).get("loops")}
            heard += bool(on)
            checks = [("dead", lambda t: t in on and log.at(t, mid)["health"] <= 0),
                      ("match over", lambda t: t in on and end is not None and t >= end)]
            if role != "server":
                srv_on = {t for t in server.ticks if (server.at(t, mid) or {}).get("loops")}
                checks.append(("no beam on the server",
                               lambda t: t in on and not any(u in srv_on for u in range(t - g, t + skew + 1))))
            for why, bad in checks:
                hit = _runs(ticks, bad, g)
                if hit:
                    return base.verdict(NAME, base.FAIL, peer=role, mech_id=mid, first_tick=hit[0], field="loops",
                                        note="%s: %s loop audio still playing %d+ ticks with %s (from tick %d)"
                                             % (role, mid, g, why, hit[0]))
    if not heard:
        return base.verdict(NAME, base.SKIP, note="no loop audio played")
    return base.verdict(NAME, base.PASS, note="loop audio stops with its beam on every peer")
