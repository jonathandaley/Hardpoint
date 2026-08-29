"""friendly_fire oracle: no hit event may have the shooter and victim on the
same team (B27: team check gates every damage call site).

Hit events are logged at the server-authoritative damage chokepoint with M2.1
shooter attribution (src mech + src_team); the victim's team comes from the
same-tick snapshot. A same-team hit reaching the chokepoint at all means a
call-site team check was bypassed. To avoid a vacuous pass the oracle requires
at least one attributed cross-team hit, proving the scenario exercised the
damage path.
"""
from . import base

NAME = "friendly_fire"


def run(ctx):
    primary = ctx["primary"]
    if "server" not in primary:
        return base.verdict(NAME, base.SKIP, note="no server stream")
    server = primary["server"]
    snap = base.by_tick(server)

    cross = 0
    unattributed = 0
    for e in server.events:
        if e.get("type") != "hit":
            continue
        src_team = e.get("payload", {}).get("src_team", -1)
        if src_team is None or src_team < 0:
            unattributed += 1
            continue
        victim = snap.get(e["tick"], {}).get(e["mech_id"])
        if victim is None:
            # nearest logged tick at or before the event
            prev = [t for t in server.ticks if t <= e["tick"] and e["mech_id"] in snap.get(t, {})]
            victim = snap[prev[-1]][e["mech_id"]] if prev else None
        if victim is None:
            unattributed += 1
            continue
        if victim.get("team") == src_team:
            return base.verdict(NAME, base.FAIL, mech_id=e["mech_id"],
                                first_tick=e["tick"], field="team",
                                pattern="sudden_jump", peer="server",
                                note="same-team hit: %s damaged %s (team %s) at tick %d -- B27 call-site check bypassed"
                                     % (e["payload"].get("src", "?"), e["mech_id"], src_team, e["tick"]))
        cross += 1
    if cross == 0:
        return base.verdict(NAME, base.SKIP,
                            note="no attributed cross-team hits (%d unattributed); scenario did not exercise damage"
                                 % unattributed)
    return base.verdict(NAME, base.PASS,
                        note="no same-team hits across %d attributed hits" % cross)
