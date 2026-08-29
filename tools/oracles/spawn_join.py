"""spawn_join oracle: at the first tick a client and the server both log a
mech, the join-critical fields must already agree.

Catches wrong-at-birth bugs (roster/team mixups, spawn transform mismatch,
wrong starting HP) that the persist-window oracles can absorb as "early sync
noise". Both peers spawn mechs locally from the same broadcast roster, so
these fields must match from the very first common tick -- no latency grace.

True late-join (a peer connecting mid-match) is deferred with T132; when that
lands, this oracle already checks the right thing at whatever tick the
late-joiner's stream starts.
"""
from . import base

NAME = "spawn_join"

DEFAULTS = {"spawn_pos_eps": 1.5}


def run(ctx):
    primary = ctx["primary"]
    if "server" not in primary:
        return base.verdict(NAME, base.SKIP, note="no server stream")
    clients = base.client_roles(primary)
    if not clients:
        return base.verdict(NAME, base.SKIP, note="no client peers")
    th = {**DEFAULTS, **ctx.get("thresholds", {})}
    pos_eps = float(th["spawn_pos_eps"])
    server = primary["server"]
    st = set(server.ticks)

    checked = 0
    for role in clients:
        client = primary[role]
        for mid in client.mech_ids:
            first = next((t for t in client.ticks if t in st
                          and client.at(t, mid) and server.at(t, mid)), None)
            if first is None:
                continue
            ss, cs = server.at(first, mid), client.at(first, mid)
            checked += 1
            bad = None
            if base.vmax_diff(ss["pos"], cs["pos"]) > pos_eps:
                bad = ("pos", round(base.vmax_diff(ss["pos"], cs["pos"]), 3))
            elif ss.get("team") != cs.get("team"):
                bad = ("team", "%s vs %s" % (ss.get("team"), cs.get("team")))
            elif ss.get("owner") != cs.get("owner"):
                bad = ("owner", "%s vs %s" % (ss.get("owner"), cs.get("owner")))
            elif abs(ss.get("health", 0) - cs.get("health", 0)) > 0.01:
                bad = ("health", "%s vs %s" % (ss.get("health"), cs.get("health")))
            if bad:
                return base.verdict(NAME, base.FAIL, mech_id=mid, first_tick=first,
                                    field=bad[0], pattern="constant_offset", peer=role,
                                    note="%s vs server at first common tick %d: %s mismatch (%s)"
                                         % (role, first, bad[0], bad[1]))
    if checked == 0:
        return base.verdict(NAME, base.SKIP, note="no common (tick, mech) between peers")
    return base.verdict(NAME, base.PASS,
                        note="spawn state agrees at first common tick (%d mech series)" % checked)
