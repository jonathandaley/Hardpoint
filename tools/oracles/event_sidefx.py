"""event_sidefx oracle: every authoritative transform jump has a cause.

On the server stream (authoritative; this is also where hit/died/captured
events are emitted), a mech's position should change smoothly tick-to-tick.
A sudden jump -- a respawn teleport, a knockback -- is legitimate only if a
replicated event for that mech occurs nearby. An unexplained jump (position
discontinuity with no event within +/- `event_window` ticks) is the bug class:
state mutated without a corresponding replicated event, so clients never see it.

Server-only by design: client transforms are interpolated and the client does
not log hit/died (damage is server-authoritative), so a client-side correction
jump has no local event and would false-positive. The server is the oracle.
"""
import math

from . import base

NAME = "event_sidefx"

# A per-tick position delta above this (metres in one physics tick) is a jump.
# Normal mech travel is well under 1 m/tick at 60 Hz; a respawn teleport is tens.
DEFAULTS = {"jump_threshold": 8.0, "event_window": 3}


def _dist(a, b):
    return math.sqrt(sum((x - y) ** 2 for x, y in zip(a, b)))


def run(ctx):
    primary = ctx["primary"]
    if "server" not in primary:
        return base.verdict(NAME, base.SKIP, note="no server stream")
    th = {**DEFAULTS, **ctx.get("thresholds", {})}
    jump_th = float(th["jump_threshold"])
    window = int(th["event_window"])
    server = primary["server"]

    # Event ticks per mech, for nearby-cause lookup.
    ev_ticks = {}
    for ev in server.events:
        ev_ticks.setdefault(ev.get("mech_id"), []).append(ev.get("tick"))

    def explained(mech_id, tick):
        for et in ev_ticks.get(mech_id, ()):
            if et is not None and abs(et - tick) <= window:
                return True
        return False

    jumps_checked = 0
    for mid in server.mech_ids:
        snaps = sorted((s for s in server.snaps if s["mech_id"] == mid), key=lambda s: s["tick"])
        for prev, cur in zip(snaps, snaps[1:]):
            if cur["tick"] - prev["tick"] != 1:
                continue  # gap in logging; not a real one-tick discontinuity
            d = _dist(prev["pos"], cur["pos"])
            if d <= jump_th:
                continue
            jumps_checked += 1
            if not explained(mid, cur["tick"]):
                return base.verdict(NAME, base.FAIL, mech_id=mid, first_tick=cur["tick"],
                                    field="pos", magnitude=round(d, 3), pattern="sudden_jump",
                                    note="%s jumped %.2fm at tick %d with no event within +/-%d ticks"
                                         % (mid, d, cur["tick"], window))
    return base.verdict(NAME, base.PASS,
                        note="every transform jump has a nearby event (%d jumps checked)" % jumps_checked)
