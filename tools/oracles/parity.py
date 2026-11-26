"""parity oracle (T555): what the server says happened, every client saw.

  - every ability activation the server broadcast (`ability_on` with slot >= 0, Mech._activate_ability
    -> _rpc_ability_activated) -> `ability_seen` for that mech and slot on each client (charge is a
    lunge, checked by transform_desync);
  - every death (`died`) -> `died_seen` (Mech._sync_death) on each client.
Only server events a client could see: it logged that mech within `window_ticks` before the event (a
late joiner or a player back in the menus could not), and the event is more than `tail_ticks` before
that client's log ends (a reliable RPC still in flight). Counts per (mech, kind, slot): seen >= sent.
"""
from collections import Counter

from . import base

NAME = "parity"

DEFAULTS = {"tail_ticks": 180, "window_ticks": 30}


def run(ctx):
    primary = ctx["primary"]
    server = primary.get("server")
    if server is None:
        return base.verdict(NAME, base.SKIP, note="no server stream")
    th = {**DEFAULTS, **ctx.get("thresholds", {})}
    sent = []
    for e in server.events:
        typ, p = e.get("type"), e.get("payload", {})
        if typ == "ability_on" and int(p.get("slot", -1)) >= 0:
            sent.append((e["tick"], e["mech_id"], "ability", int(p["slot"])))
        elif typ == "died":
            sent.append((e["tick"], e["mech_id"], "died", -1))
    if not sent:
        return base.verdict(NAME, base.SKIP, note="no ability activation or death on the server")
    total, missing = 0, []
    for role in base.client_roles(primary):
        cl = primary[role]
        if not cl.ticks:
            continue
        seen = Counter()
        for e in cl.events:
            if e.get("type") == "ability_seen":
                seen[(e["mech_id"], "ability", int(e.get("payload", {}).get("slot", -1)))] += 1
            elif e.get("type") == "died_seen":
                seen[(e["mech_id"], "died", -1)] += 1
        want = Counter()
        first = {}
        for t, m, kind, slot in sent:
            if t > cl.ticks[-1] - int(th["tail_ticks"]):
                continue
            if not any(cl.at(x, m) is not None for x in range(t - int(th["window_ticks"]), t + 1)):
                continue
            want[(m, kind, slot)] += 1
            first.setdefault((m, kind, slot), t)
        total += sum(want.values())
        for k in sorted(want):
            if seen[k] < want[k]:
                missing.append((first[k], role, k, want[k], seen[k]))
    if not total:
        return base.verdict(NAME, base.SKIP, note="no server event fell where a client could see it")
    if missing:
        missing.sort()
        t, role, (m, kind, slot), w, s = missing[0]
        what = "ability slot %d" % slot if kind == "ability" else "death"
        more = "" if len(missing) == 1 else " (+%d more)" % (len(missing) - 1)
        return base.verdict(NAME, base.FAIL, mech_id=m, field=kind, first_tick=t, peer=role,
                            note="%s saw %d of %d %s event(s) of %s (first at tick %d)%s" % (role, s, w, what, m, t, more))
    return base.verdict(NAME, base.PASS, note="every client saw all %d server ability / death event(s)" % total)
