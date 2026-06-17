"""team_assignment oracle: team identity must be stable and consistent (B27).

Team is assigned at spawn and never changes. This oracle checks the structural
half of the friendly-fire invariant -- that no cross-team-state leak occurs:
  1. Stability: a mech's team is constant across every server tick.
  2. Cross-peer agreement: every client's team for a mech matches the server's,
     at every shared tick (no persist window -- team is static, so any mismatch
     is a bug, not sync lag).

The damage-skip half of B27 (same-team hits deal no damage) needs the hit event
stream and is covered by the event_sidefx / friendly-fire event oracle (M1.3).
"""
from . import base

NAME = "team_assignment"


def run(ctx):
    primary = ctx["primary"]
    if "server" not in primary:
        return base.verdict(NAME, base.SKIP, note="no server stream")
    server = primary["server"]

    # 1. Team stability on the authoritative stream.
    seen = {}
    for s in server.snaps:
        mid = s["mech_id"]
        team = s.get("team")
        if mid in seen and seen[mid][0] != team:
            return base.verdict(NAME, base.FAIL, mech_id=mid, first_tick=s["tick"],
                                field="team", pattern="sudden_jump",
                                note="%s team changed %r -> %r at tick %d (cross-team-state leak)"
                                     % (mid, seen[mid][0], team, s["tick"]))
        if mid not in seen:
            seen[mid] = (team, s["tick"])

    # 2. Cross-peer team agreement.
    checked = 0
    for role in base.client_roles(primary):
        client = primary[role]
        st = set(server.ticks)
        for mid in client.mech_ids:
            for t in client.ticks:
                if t not in st:
                    continue
                cs = client.at(t, mid)
                ss = server.at(t, mid)
                if cs is None or ss is None:
                    continue
                checked += 1
                if cs.get("team") != ss.get("team"):
                    return base.verdict(NAME, base.FAIL, mech_id=mid, first_tick=t,
                                        field="team", pattern="constant_offset", peer=role,
                                        note="%s sees %s on team %r, server says %r (tick %d)"
                                             % (role, mid, cs.get("team"), ss.get("team"), t))
    return base.verdict(NAME, base.PASS,
                        note="teams stable and consistent across peers (%d checks)" % checked)
