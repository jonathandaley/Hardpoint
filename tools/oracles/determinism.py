"""determinism oracle: two identical runs (same seed + script) must match.

This is the meta-oracle / green baseline gate. It compares the authoritative
SERVER stream of the primary run against that of a baseline run, for locally
owned mechs only (those are bit-deterministic; networked mechs carry transport
jitter and are out of the determinism gate by design -- see sync_diff.py).

Needs a baseline run (sync_compare.py --baseline-run); SKIPs without one.
"""
from . import base

NAME = "determinism"

# Mode-A loopback tolerances, mirrored from sync_diff.py (approved 2026-06-13).
DEFAULTS = {"det_pos_eps": 0.30, "det_rot_eps": 0.01, "det_hp_eps": 0.01}


def run(ctx):
    baseline = ctx.get("baseline")
    if not baseline or "server" not in baseline:
        return base.verdict(NAME, base.SKIP, note="no baseline run; pass --baseline-run")
    primary = ctx["primary"]
    if "server" not in primary:
        return base.verdict(NAME, base.SKIP, note="no server stream in primary run")
    th = {**DEFAULTS, **ctx.get("thresholds", {})}
    a = primary["server"]
    b = baseline["server"]
    common = [t for t in a.ticks if t in set(b.ticks)]
    if not common:
        return base.verdict(NAME, base.FAIL, note="no overlapping ticks between runs")

    checked = 0
    for tick in common:
        for mid in a.mech_ids:
            ra = a.at(tick, mid)
            if ra is None or not base.is_local(ra):
                continue
            rb = b.at(tick, mid)
            if rb is None:
                return base.verdict(NAME, base.FAIL, mech_id=mid, first_tick=tick,
                                    field="presence", pattern="sudden_jump",
                                    note="mech present in run1, missing in run2 at this tick")
            checked += 1
            vec_checks = [
                ("pos", base.vmax_diff(ra["pos"], rb["pos"]), th["det_pos_eps"]),
                ("rot_local", base.vmax_diff(ra["rot_local"], rb["rot_local"]), th["det_rot_eps"]),
                ("rot_global", base.vmax_diff(ra["rot_global"], rb["rot_global"]), th["det_rot_eps"]),
                ("health", abs(ra["health"] - rb["health"]), th["det_hp_eps"]),
            ]
            for field, mag, eps in vec_checks:
                if mag > eps:
                    return base.verdict(NAME, base.FAIL, mech_id=mid, first_tick=tick,
                                        field=field, magnitude=round(mag, 5),
                                        pattern="sudden_jump",
                                        note="run1 vs run2 |diff|=%.5f > eps %.4g" % (mag, eps))
            for field in ("lock_target", "team"):
                if ra.get(field) != rb.get(field):
                    return base.verdict(NAME, base.FAIL, mech_id=mid, first_tick=tick,
                                        field=field, pattern="sudden_jump",
                                        note="run1 %r != run2 %r" % (ra.get(field), rb.get(field)))

    return base.verdict(NAME, base.PASS,
                        note="epsilon-identical: %d local snapshots over %d ticks" % (checked, len(common)))
