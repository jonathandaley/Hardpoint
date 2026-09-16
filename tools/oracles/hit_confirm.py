"""hit_confirm oracle: every server-side hit whose shooter is owned by a
client peer must produce a `hit_confirm` event on that peer within a delay
window (B32: server forwards confirms via Mech._sync_hit_confirmed so the
owning peer's HUD flashes the hit-X).

Hits land only at the server damage chokepoint (V38), so `hit` events exist
only in the server stream; `hit_confirm` events exist only on the peer that
received the forward. Server-owned shooters (host player, bots) confirm
locally with no RPC and are out of scope. Confirms are consumed one-to-one
(greedy, in tick order) so two hits cannot share one confirm. To avoid a
vacuous pass the oracle SKIPs when the scenario produced no client-owned hits.

Peer tick clocks are NOT aligned (V45): each peer counts its own physics
frames from the moment it received match-start, so a client can stamp the
confirm one tick BEFORE the server's hit tick. The window therefore opens
`clock_skew` ticks early (T136: a zero negative bound flaked ~1/6 runs).
"""
from . import base

NAME = "hit_confirm"

DEFAULTS = {"hit_confirm_max_delay_ticks": 30, "hit_confirm_clock_skew_ticks": 2}


def run(ctx):
    primary = ctx["primary"]
    if "server" not in primary:
        return base.verdict(NAME, base.SKIP, note="no server stream")
    clients = base.client_roles(primary)
    if not clients:
        return base.verdict(NAME, base.SKIP, note="no client peers")
    th = {**DEFAULTS, **ctx.get("thresholds", {})}
    delay = int(th["hit_confirm_max_delay_ticks"])
    skew = int(th["hit_confirm_clock_skew_ticks"])
    server = primary["server"]

    role_by_peer = {}
    for role in clients:
        snaps = primary[role].snaps
        if snaps:
            role_by_peer[snaps[0]["peer"]] = role

    owner_by_mech = {}
    for s in server.snaps:
        owner_by_mech.setdefault(s["mech_id"], s.get("owner"))

    # unconsumed confirm ticks per client role, ascending
    confirms = {
        role: sorted(e["tick"] for e in primary[role].events
                     if e.get("type") == "hit_confirm")
        for role in clients
    }

    checked = 0
    for e in sorted((e for e in server.events if e.get("type") == "hit"),
                    key=lambda e: e["tick"]):
        src = (e.get("payload") or {}).get("src")
        role = role_by_peer.get(owner_by_mech.get(src))
        if role is None:
            continue  # server-owned or unattributed shooter; no RPC involved
        checked += 1
        t = e["tick"]
        pool = confirms[role]
        match = next((i for i, ct in enumerate(pool) if t - skew <= ct <= t + delay), None)
        if match is None:
            return base.verdict(NAME, base.FAIL, mech_id=src, first_tick=t,
                                field="hit_confirm", pattern="sudden_jump",
                                peer=role,
                                note="hit by %s at tick %d never confirmed on owning peer %s within [-%d, +%d] ticks"
                                     % (src, t, role, skew, delay))
        pool.pop(match)
    if checked == 0:
        return base.verdict(NAME, base.SKIP,
                            note="no client-owned attributed hits; scenario did not exercise confirm RPC")
    return base.verdict(NAME, base.PASS,
                        note="%d client-owned hits each confirmed on owning peer" % checked)
