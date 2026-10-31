"""world_invariants oracle (T149): single-state sanity on every peer's stream,
auto-added to every scenario by sync_compare. Game-bug taxonomy 'invalid value
change' / 'invalid position' (Politowski et al. 2023, MP_AUTODEBUG_PLAN §9):
  - no NaN/inf in pos, aim, health
  - 0 <= health <= max_hp
  - 0 <= ammo <= ammo_max per finite magazine (ammo_max -1 = infinite)
  - pos.y above the kill floor (fell out of the world)
  - beacons: 0 <= progress <= 1, owner/capturing team in {-1, 0, 1}
Fields added in T149 (max_hp, ammo_max) are skipped when absent (older logs).
Skipped on purpose: stuck detection (needs input->mech mapping that V43 makes
unreliable per log file; T152 soak covers it with bots) and fire cadence (the
determinism gate already catches cadence regressions, B29).
"""
import math

from . import base

NAME = "world_invariants"

DEFAULTS = {"kill_floor_y": -50.0}


def _bad_num(v):
    return isinstance(v, float) and (math.isnan(v) or math.isinf(v))


def check_snap(s, floor):
    for field in ("pos", "aim"):
        if any(_bad_num(x) for x in s.get(field) or []):
            return field, "non-finite %s %s" % (field, s.get(field))
    hp = s.get("health")
    if hp is not None:
        if _bad_num(hp):
            return "health", "non-finite health"
        top = s.get("max_hp")
        if hp < -0.01 or (top is not None and hp > top + 0.01):
            return "health", "health %.2f outside [0, %s]" % (hp, top)
    for slot, a in (s.get("ammo") or {}).items():
        top = (s.get("ammo_max") or {}).get(slot)
        if a is None or top is None or top < 0:
            continue
        if a < 0 or a > top:
            return "ammo", "slot %s ammo %s outside [0, %s]" % (slot, a, top)
    pos = s.get("pos")
    if pos and pos[1] < floor:
        return "pos", "y=%.1f below kill floor %.0f (fell out of the world)" % (pos[1], floor)
    return None


def check_beacon(b):
    p = b.get("progress")
    if p is not None and (p < -0.001 or p > 1.001):
        return "progress %.3f outside [0, 1]" % p
    for k in ("owner_team", "capturing_team"):
        if b.get(k) not in (None, -1, 0, 1):
            return "%s=%r invalid" % (k, b.get(k))
    return None


def run(ctx):
    th = {**DEFAULTS, **ctx.get("thresholds", {})}
    floor = float(th["kill_floor_y"])
    n = 0
    for role, log in sorted(ctx["primary"].items()):
        for s in log.snaps:
            n += 1
            bad = check_snap(s, floor)
            if bad:
                return base.verdict(NAME, base.FAIL, peer=role, mech_id=s.get("mech_id"), first_tick=s["tick"],
                                    field=bad[0], pattern="sudden_jump",
                                    note="%s %s tick %d: %s" % (role, s.get("mech_id"), s["tick"], bad[1]))
        for b in log.beacons:
            bad = check_beacon(b)
            if bad:
                return base.verdict(NAME, base.FAIL, peer=role, mech_id=b.get("beacon_id"), first_tick=b["tick"],
                                    field="beacon", note="%s %s tick %d: %s" % (role, b.get("beacon_id"), b["tick"], bad))
    if n == 0:
        return base.verdict(NAME, base.SKIP, note="no snapshots")
    return base.verdict(NAME, base.PASS, note="%d snapshots + beacons within world invariants" % n)
