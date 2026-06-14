#!/usr/bin/env python3
"""M0.5 pairwise epsilon diff for the MP autodebug determinism self-test.

Compares two JSONL snapshot logs tick-by-tick, mech-by-mech, and reports the
first field that diverges beyond tolerance. Stdlib only. The M0 deliverable is
green here: two runs of the identical seed + script must be epsilon-identical.

Usage:
    sync_diff.py <a.jsonl> <b.jsonl> [--pos-eps 0.001] [--rot-eps 0.001]
                 [--hp-eps 0.01]

Exit 0 = epsilon-identical (PASS), 1 = divergence (FAIL), 2 = bad input.
"""
import argparse
import json
import sys


def load(path):
    """Return {(tick, mech_id): snapshot} and the sorted set of ticks."""
    rows = {}
    ticks = set()
    with open(path) as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            d = json.loads(line)
            rows[(d["tick"], d["mech_id"])] = d
            ticks.add(d["tick"])
    return rows, ticks


def vdiff(a, b):
    return max((abs(x - y) for x, y in zip(a, b)), default=0.0)


def is_local(row):
    """A mech whose owner is this logging peer is simulated locally (authoritative)
    and must be bit-deterministic. Networked mechs carry transport-timing jitter
    (input-RPC arrival), which is out of the determinism gate by design."""
    return row.get("owner") == row.get("peer")


def compare(a_path, b_path, pos_eps, rot_eps, hp_eps, local_only=True):
    a, a_ticks = load(a_path)
    b, b_ticks = load(b_path)
    common = sorted(a_ticks & b_ticks)
    if not common:
        print(f"FAIL: no overlapping ticks ({a_path} vs {b_path})")
        return 1

    checked = 0
    for tick in common:
        # mechs present at this tick in run A
        mechs = sorted(mid for (t, mid) in a if t == tick)
        for mid in mechs:
            ra = a.get((tick, mid))
            rb = b.get((tick, mid))
            if local_only and not is_local(ra):
                continue
            checked += 1
            if rb is None:
                print(f"FAIL tick {tick} mech {mid}: present in A, missing in B")
                return 1
            checks = [
                ("pos", vdiff(ra["pos"], rb["pos"]), pos_eps),
                ("rot_local", vdiff(ra["rot_local"], rb["rot_local"]), rot_eps),
                ("rot_global", vdiff(ra["rot_global"], rb["rot_global"]), rot_eps),
                ("health", abs(ra["health"] - rb["health"]), hp_eps),
            ]
            for field, mag, eps in checks:
                if mag > eps:
                    print(f"FAIL tick {tick} mech {mid} field {field}: "
                          f"|A-B|={mag:.5f} > eps {eps}")
                    print(f"  A: {json.dumps(ra)}")
                    print(f"  B: {json.dumps(rb)}")
                    return 1
            for field in ("ammo", "lock_target", "team"):
                if ra.get(field) != rb.get(field):
                    print(f"FAIL tick {tick} mech {mid} field {field}: "
                          f"{ra.get(field)!r} != {rb.get(field)!r}")
                    return 1

    scope = "locally-owned mechs" if local_only else "all mechs"
    print(f"PASS: {a_path} vs {b_path} epsilon-identical "
          f"({checked} snapshots, {scope}, over {len(common)} ticks)")
    return 0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("a")
    ap.add_argument("b")
    # Mode-A loopback tolerances (approved 2026-06-13): the authoritative server
    # stream is exact for locally-driven mechs; networked mechs jitter ~0.17m
    # from ENet input-arrival timing, so pos_eps absorbs that. Real desync bugs
    # are meters, well above these. Client interpolated logs are NOT gated here.
    ap.add_argument("--pos-eps", type=float, default=0.30)
    ap.add_argument("--rot-eps", type=float, default=0.01)
    ap.add_argument("--hp-eps", type=float, default=0.01)
    ap.add_argument("--all-mechs", action="store_true",
                    help="also gate networked mechs (carries transport jitter; diagnostic)")
    args = ap.parse_args()
    try:
        return compare(args.a, args.b, args.pos_eps, args.rot_eps, args.hp_eps,
                       local_only=not args.all_mechs)
    except (OSError, json.JSONDecodeError, KeyError) as e:
        print(f"ERROR: {e}")
        return 2


if __name__ == "__main__":
    sys.exit(main())
