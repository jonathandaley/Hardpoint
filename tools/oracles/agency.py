"""agency oracle (T555): what a client's pilot asks for, the server does.

Ground truth is the owning client's `intent` events (Mech._maybe_forward_input, for EVERY input
source -- players, replay scripts and bots alike): fire held on / off edges and ability / reload /
slot presses. Judged per mech life (one mech node = one life: every squad slot spawns its own),
only on ticks where both the client's and the server's copy are alive and the world is live, and
not in the last `tail_ticks` of the life (still in flight):
  - fire held >= `fire_hold_min_ticks` -> the server's copy tried to fire (`fired`) at least once
    (T519: a staged first mech moved and looked on its client but never shot);
  - an ability / reload / slot press -> the server consumed one of that kind (`input_applied`);
  - >= `ability_ready_presses` ability presses while the client's own cooldowns all read 0 -> the
    ability came on (`ability_on`) at least once.
Per life, not per press: the server merges presses closer than one input packet (bots press on
consecutive ticks), so exact counts are input_delivery's job for scripted presses.
"""
from collections import defaultdict

from . import base

NAME = "agency"

DEFAULTS = {"fire_hold_min_ticks": 120, "tail_ticks": 120, "ability_ready_presses": 2}


def _alive(log, tick, mech_id):
    s = log.at(tick, mech_id)
    return s is not None and float(s.get("health", 0)) > 0.0


def _live_tick(server):
    """First server tick where anything moved or fired: before it the match held every mech."""
    first = [e["tick"] for e in server.events if e.get("type") == "fired"]
    for s in server.snaps:
        v = s.get("vel") or [0, 0, 0]
        if abs(v[0]) + abs(v[2]) > 0.01:
            first.append(s["tick"])
            break
    return min(first) if first else None


def run(ctx):
    primary = ctx["primary"]
    server = primary.get("server")
    if server is None:
        return base.verdict(NAME, base.SKIP, note="no server stream")
    th = {**DEFAULTS, **ctx.get("thresholds", {})}
    live = _live_tick(server)
    if live is None:
        return base.verdict(NAME, base.SKIP, note="the match never went live")
    srv = defaultdict(lambda: defaultdict(list))  # mech -> kind -> ticks
    died = {}
    for e in server.events:
        t, m, typ = e["tick"], e.get("mech_id", ""), e.get("type")
        if typ == "fired":
            srv[m]["fired"].append(t)
        elif typ == "input_applied":
            srv[m][e.get("payload", {}).get("action")].append(t)
        elif typ == "ability_on":
            srv[m]["ability_on"].append(t)
        elif typ == "died":
            died.setdefault(m, t)
    srv_last = defaultdict(int)
    for s in server.snaps:
        srv_last[s["mech_id"]] = max(srv_last[s["mech_id"]], s["tick"])
    checked, problems = 0, []
    for role in base.client_roles(primary):
        cl = primary[role]
        cl_end = cl.ticks[-1] if cl.ticks else 0
        intents = defaultdict(list)
        for e in cl.events:
            if e.get("type") == "intent":
                intents[e["mech_id"]].append(e)
        for m, evs in sorted(intents.items()):
            end = min(died.get(m, srv_last[m]), srv_last[m], cl_end) - int(th["tail_ticks"])

            def counts(t):
                return live <= t <= end and _alive(server, t, m) and _alive(cl, t, m)

            hold, hold_from, on_at = 0, None, None
            presses = defaultdict(list)
            for e in sorted(evs, key=lambda e: e["tick"]):
                p, t = e.get("payload", {}), e["tick"]
                if p.get("action") == "fire":
                    if p.get("on") and on_at is None:
                        on_at = t
                    elif not p.get("on") and on_at is not None:
                        n = sum(1 for x in range(on_at, t) if counts(x))
                        if n and hold_from is None:
                            hold_from = on_at
                        hold, on_at = hold + n, None
                elif counts(t):
                    presses[p.get("action")].append(t)
            if on_at is not None:  # still held at the end of the log
                n = sum(1 for x in range(on_at, end + 1) if counts(x))
                if n and hold_from is None:
                    hold_from = on_at
                hold += n
            life = (live, max(end + int(th["tail_ticks"]), live))
            if hold or presses:
                checked += 1
            if hold >= int(th["fire_hold_min_ticks"]) and not any(life[0] <= t <= life[1] for t in srv[m]["fired"]):
                problems.append((hold_from, m, "fire", "%s held fire %d ticks from tick %d; the server's copy never "
                                 "tried to fire" % (role, hold, hold_from)))
            for action, ticks in sorted(presses.items()):
                if not any(life[0] <= t <= life[1] for t in srv[m][action]):
                    problems.append((ticks[0], m, action, "%s pressed %s %d time(s) from tick %d; the server consumed "
                                     "none" % (role, action, len(ticks), ticks[0])))
            ready = []
            for t in presses.get("ability", []):
                s = cl.at(t, m)
                cds = (s or {}).get("abilities") or {}
                if cds and all(float(v) <= 0.0 for v in cds.values()):
                    ready.append(t)
            if len(ready) >= int(th["ability_ready_presses"]) and \
                    not any(life[0] <= t <= life[1] for t in srv[m]["ability_on"]):
                problems.append((ready[0], m, "ability_on", "%s pressed its ability %d time(s) off cooldown from "
                                 "tick %d; it never came on" % (role, len(ready), ready[0])))
    if not checked:
        return base.verdict(NAME, base.SKIP, note="no client asked for anything while alive and live")
    if problems:
        problems.sort(key=lambda p: (p[0] is None, p[0] or 0))
        t, m, field, note = problems[0]
        more = "" if len(problems) == 1 else " (+%d more: %s)" % (len(problems) - 1,
                                                                 "; ".join(p[3] for p in problems[1:4]))
        return base.verdict(NAME, base.FAIL, mech_id=m, field=field, first_tick=t, note=note + more)
    return base.verdict(NAME, base.PASS, note="%d client mech life(s): every fire hold / press reached the server" % checked)
