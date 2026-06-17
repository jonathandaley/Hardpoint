"""rpc_integrity oracle: per-peer event sequence is monotonic, no gaps/reorders.

Each peer stamps every logged event with a monotonic rpc_seq. This oracle
verifies that, within a peer's event stream, rpc_seq is strictly increasing by
exactly 1 with no duplicate, gap, or backwards step.

Honest scope: rpc_seq is assigned locally at emit time, so this currently
validates event-log integrity / dropped-event detection within a peer -- NOT
true on-wire RPC reordering between peers. Detecting that needs sender-assigned
sequence numbers carried in the replicated RPCs themselves (future netcode
work); when those land, this oracle gains real cross-peer teeth.
"""
from . import base

NAME = "rpc_integrity"


def run(ctx):
    primary = ctx["primary"]
    peers_with_events = [(r, p) for r, p in sorted(primary.items()) if p.events]
    if not peers_with_events:
        return base.verdict(NAME, base.SKIP, note="no events logged (event stream idle)")

    checked = 0
    for role, peer in peers_with_events:
        prev = None
        for ev in peer.events:
            seq = ev.get("rpc_seq")
            checked += 1
            if seq is None:
                return base.verdict(NAME, base.FAIL, peer=role, first_tick=ev.get("tick"),
                                    pattern="sudden_jump",
                                    note="%s event missing rpc_seq: %s" % (role, ev.get("type")))
            if prev is not None and seq != prev + 1:
                kind = "duplicate/backwards" if seq <= prev else "gap"
                return base.verdict(NAME, base.FAIL, peer=role, first_tick=ev.get("tick"),
                                    magnitude=seq - prev, pattern="sudden_jump",
                                    note="%s rpc_seq %s after %d (%s) at tick %s"
                                         % (role, seq, prev, kind, ev.get("tick")))
            prev = seq
    return base.verdict(NAME, base.PASS,
                        note="rpc_seq monotonic & gapless across %d events" % checked)
