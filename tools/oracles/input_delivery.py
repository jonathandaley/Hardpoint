"""input_delivery oracle (T158): every one-shot press (reload, ability, slot N)
must be acted on exactly once by the server's copy of that mech.

Ground truth is the ReplayInputSource `input_press` event on the pressing peer
(the moment the finger goes down); the server logs `input_applied` when Mech's
handler consumes a press. Counts per (mech, action, slot) must match. Presses in
the last `press_tail_ticks` of the pressing peer's log are ignored (may still be
in flight). Only mechs with at least one logged press are checked, so bots and
idle mechs don't count.
"""
from collections import Counter

from . import base

NAME = "input_delivery"

DEFAULTS = {"press_tail_ticks": 90}


def _key(e):
    p = e.get("payload", {})
    return (e["mech_id"], p.get("action"), int(p.get("slot", -1)))


def run(ctx):
    primary = ctx["primary"]
    if "server" not in primary:
        return base.verdict(NAME, base.SKIP, note="no server stream")
    th = {**DEFAULTS, **ctx.get("thresholds", {})}
    pressed, applied = Counter(), Counter()
    for role, log in primary.items():
        # run end = last snapshot tick; events stop whenever nothing happens
        end = max(log.ticks[-1] if log.ticks else 0, max((e["tick"] for e in log.events), default=0))
        for e in log.events:
            if e.get("type") == "input_press" and e["tick"] <= end - int(th["press_tail_ticks"]):
                pressed[_key(e)] += 1
    if not pressed:
        return base.verdict(NAME, base.SKIP, note="no scripted presses in run")
    mechs = {k[0] for k in pressed}
    for e in primary["server"].events:
        if e.get("type") == "input_applied" and e["mech_id"] in mechs:
            applied[_key(e)] += 1
    bad = sorted(k for k in set(pressed) | set(applied) if pressed[k] != applied[k])
    if bad:
        detail = ", ".join("%s %s%s pressed %d applied %d" % (m, a, "" if s < 0 else str(s), pressed[(m, a, s)],
                                                               applied[(m, a, s)]) for m, a, s in bad)
        lost = sum(max(0, pressed[k] - applied[k]) for k in bad)
        return base.verdict(NAME, base.FAIL, mech_id=bad[0][0], field=bad[0][1], magnitude=lost,
                            note="server applied %d of %d presses: %s" % (sum(pressed.values()) - lost,
                                                                         sum(pressed.values()), detail))
    return base.verdict(NAME, base.PASS, note="all %d presses applied exactly once on server" % sum(pressed.values()))
