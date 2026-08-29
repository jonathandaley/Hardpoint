"""Shared loaders, comparison helpers, and verdict construction for oracles.

A "run" is one execution of run_scenario.py: a directory holding one
<role>.jsonl snapshot stream per peer (server, client_1, ...) and an optional
<role>.events.jsonl event stream. Oracles consume PeerLog objects plus the
scenario spec via a ctx dict; see tools/sync_compare.py for how ctx is built.

Verdict shape (the M1 contract, per MP_AUTODEBUG_PLAN.md S4):
    {
      "oracle": "transform_desync",
      "verdict": "PASS" | "FAIL" | "SKIP",
      "pattern": "constant_offset|accumulating_drift|sudden_jump|none",
      "mech_id": "...", "first_tick": int, "magnitude": float,
      "field": "...", "note": "..."
    }
Only "oracle" and "verdict" are mandatory; the rest are diagnosis fields an
oracle fills in when it has something to say.
"""
import glob
import json
import os

PASS = "PASS"
FAIL = "FAIL"
SKIP = "SKIP"


def load_jsonl(path):
    out = []
    with open(path) as f:
        for line in f:
            line = line.strip()
            if line:
                out.append(json.loads(line))
    return out


class PeerLog:
    """One peer's snapshot + event streams, indexed for oracle access."""

    def __init__(self, role, snaps, events, beacons=None):
        self.role = role
        self.snaps = snaps
        self.events = events
        self.beacons = beacons or []  # M2.1: per-tick beacon rows, may be absent
        self.by_key = {(s["tick"], s["mech_id"]): s for s in snaps}
        self.ticks = sorted({s["tick"] for s in snaps})
        self.mech_ids = sorted({s["mech_id"] for s in snaps})
        self.beacon_by_key = {(b["tick"], b["beacon_id"]): b for b in self.beacons}
        self.beacon_ids = sorted({b["beacon_id"] for b in self.beacons})

    def at(self, tick, mech_id):
        return self.by_key.get((tick, mech_id))

    def beacon_at(self, tick, beacon_id):
        return self.beacon_by_key.get((tick, beacon_id))


def load_run(run_dir):
    """Return {role: PeerLog} for every <role>.jsonl in run_dir."""
    peers = {}
    for p in sorted(glob.glob(os.path.join(run_dir, "*.jsonl"))):
        if p.endswith(".events.jsonl") or p.endswith(".beacons.jsonl"):
            continue
        role = os.path.basename(p)[: -len(".jsonl")]
        snaps = load_jsonl(p)
        epath = os.path.join(run_dir, role + ".events.jsonl")
        events = load_jsonl(epath) if os.path.exists(epath) else []
        bpath = os.path.join(run_dir, role + ".beacons.jsonl")
        beacons = load_jsonl(bpath) if os.path.exists(bpath) else []
        peers[role] = PeerLog(role, snaps, events, beacons)
    return peers


def vmax_diff(a, b):
    """Max abs componentwise difference of two equal-length numeric arrays."""
    return max((abs(x - y) for x, y in zip(a, b)), default=0.0)


def quat_angle(a, b):
    """Angular distance in radians between two [x,y,z,w] quaternions.

    Componentwise diff is wrong for rotations: q and -q are the same rotation
    (double cover) but differ by up to 2.0 per component, which fires false
    positives the moment a mech's yaw wraps past pi (caught by kill_confirm's
    full-circle sweep). 2*acos(|dot|) is the true rotation angle between them.
    """
    import math
    dot = abs(sum(x * y for x, y in zip(a, b)))
    return 2.0 * math.acos(min(1.0, dot))


def is_local(snap):
    """True if this snapshot's mech is simulated locally by the logging peer
    (owner == peer), hence authoritative and bit-deterministic. Networked mechs
    on a client are interpolated (V38) and carry transport-timing jitter."""
    return snap.get("owner") == snap.get("peer")


def verdict(oracle, status, **extra):
    v = {"oracle": oracle, "verdict": status}
    v.update(extra)
    return v


def client_roles(primary):
    """Networked peers (everything but the authoritative server), sorted."""
    return sorted(r for r in primary if r != "server")


def cross_series(server, client, mech_id, mag_fn):
    """Per-tick (tick, magnitude) for one mech over the ticks server+client
    share, where mag_fn(server_snap, client_snap) -> float. Ordered by tick."""
    st = set(server.ticks)
    out = []
    for t in client.ticks:
        if t not in st:
            continue
        ss = server.at(t, mech_id)
        cs = client.at(t, mech_id)
        if ss is not None and cs is not None:
            out.append((t, mag_fn(ss, cs)))
    return out


def first_persistent_run(ticks_mags, eps, persist):
    """Start tick of the first run of >= persist consecutive entries with
    magnitude > eps, or None. ticks_mags is ordered by tick."""
    run_start = None
    run_len = 0
    for t, m in ticks_mags:
        if m > eps:
            if run_start is None:
                run_start = t
            run_len += 1
            if run_len >= persist:
                return run_start
        else:
            run_start = None
            run_len = 0
    return None


def by_tick(peerlog):
    """{tick: {mech_id: snapshot}} for whole-tick lookups (e.g. is a lock
    target alive at this tick)."""
    d = {}
    for s in peerlog.snaps:
        d.setdefault(s["tick"], {})[s["mech_id"]] = s
    return d


def classify_pattern(ticks_mags, eps):
    """Classify a per-tick magnitude trajectory into one of the S4 patterns.

    ticks_mags: list of (tick, magnitude) over the common ticks for a single
    mech/field. eps: the divergence threshold for that field.

    Returns (pattern, first_tick, peak):
      none              -- never exceeds eps
      sudden_jump       -- a brief spike that then recovers below eps
      accumulating_drift-- magnitude grows materially from onset to end
      constant_offset   -- steps up and stays roughly flat
    Heuristic; the magnitude/first_tick it reports matter more than the label.
    """
    over = [(t, m) for t, m in ticks_mags if m > eps]
    if not over:
        return "none", None, 0.0
    first_tick = over[0][0]
    mags = [m for _, m in over]
    peak = max(mags)
    total = len(ticks_mags)
    # Brief relative to the whole window and clearly a spike -> sudden_jump.
    if len(over) <= max(2, int(0.1 * total)) and peak > 2 * eps:
        return "sudden_jump", first_tick, peak
    n = len(mags)
    third = max(1, n // 3)
    head = sum(mags[:third]) / third
    tail = sum(mags[-third:]) / third
    if tail > head * 1.5 + eps:
        return "accumulating_drift", first_tick, peak
    return "constant_offset", first_tick, peak
