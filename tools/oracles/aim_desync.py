"""aim_desync oracle (T140): each client's OWN mech aim (torso yaw + camera pitch)
must match the server's copy of it once the client stops turning.

B-a: the client's shots looked right on its own screen while the server's result
drifted a few degrees. The client never overwrites its own torso from snapshots
(Mech.gd `_apply_snapshot_interp`), so any difference in how the server
integrates the client's look input persists for the rest of the life.

During a turn the server trails by input latency, so only settled ticks are
compared: the client's own aim unchanged for `aim_settle_ticks`. By then every
look input has reached the server, and the two must agree within `aim_eps`.
transform_desync cannot see this class: its rot tolerance is 0.5 rad and
quaternion snapping in the log adds ~0.04 rad of noise; `aim` is logged as floats.
"""
import math

from . import base

NAME = "aim_desync"

DEFAULTS = {"aim_eps": 0.005, "aim_settle_ticks": 30, "persist_ticks": 5}


def _wrap(a):
    return math.atan2(math.sin(a), math.cos(a))


def settled_diffs(client, server, settle):
    """{mech_id: [(tick, yaw_diff, pitch_diff)]} for the client's own mechs at
    ticks where the client's aim has been unchanged for >= settle ticks."""
    series = {}
    for s in client.snaps:
        if s.get("owner") == s.get("peer") and "aim" in s:
            series.setdefault(s["mech_id"], []).append(s)
    out = {}
    for mid, snaps in series.items():
        snaps.sort(key=lambda s: s["tick"])
        rows, last, still = [], None, 0
        for s in snaps:
            a = s["aim"]
            still = still + 1 if a == last else 0
            last = a
            if still < settle:
                continue
            ss = server.at(s["tick"], mid)
            if ss is None or "aim" not in ss:
                continue
            rows.append((s["tick"], abs(_wrap(a[0] - ss["aim"][0])), abs(a[1] - ss["aim"][1])))
        out[mid] = rows
    return out


def run(ctx):
    primary = ctx["primary"]
    if "server" not in primary:
        return base.verdict(NAME, base.SKIP, note="no server stream to compare against")
    th = {**DEFAULTS, **ctx.get("thresholds", {})}
    eps, persist = float(th["aim_eps"]), int(th["persist_ticks"])
    server = primary["server"]
    worst, checked = None, 0
    for role in base.client_roles(primary):
        for mid, rows in settled_diffs(primary[role], server, int(th["aim_settle_ticks"])).items():
            if not rows:
                continue
            checked += 1
            mags = [(t, max(dy, dp)) for t, dy, dp in rows]
            onset = base.first_persistent_run(mags, eps, persist)
            if onset is None:
                continue
            pattern, _, peak = base.classify_pattern(mags, eps)
            _, dy, dp = max(rows, key=lambda r: max(r[1], r[2]))
            field = "yaw" if dy >= dp else "pitch"
            v = base.verdict(NAME, base.FAIL, mech_id=mid, peer=role, first_tick=onset,
                             field=field, magnitude=round(peak, 5), pattern=pattern,
                             note="%s own aim vs server at settled ticks: %s off by up to %.4f rad "
                                  "(%.2f deg) from tick %d (yaw %.4f, pitch %.4f at worst)"
                                  % (role, field, peak, math.degrees(peak), onset, dy, dp))
            if worst is None or onset < worst["first_tick"]:
                worst = v
    if worst is not None:
        return worst
    if checked == 0:
        return base.verdict(NAME, base.SKIP, note="no settled own-aim samples (log lacks 'aim' or client never settled)")
    return base.verdict(NAME, base.PASS,
                        note="client own aim matches server at settled ticks (%d series, eps %.4f rad)" % (checked, eps))
