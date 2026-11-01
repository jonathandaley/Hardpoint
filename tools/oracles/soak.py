"""soak oracle (T152): long bot-driven runs (scenario "soak": true). From the
harness perf lines, server log and snapshots:
  - softlock: the match must end (Harness 'match ended at sync tick N')
  - leaks: per peer, orphan nodes may grow <= soak_max_orphan_growth, object
    count and static memory <= soak_max_growth (fraction) from the second
    sample (after load) to the last
  - perf: server physics median per frame <= soak_max_phys_ms (T3500 budget 16 ms); p90/max reported
  - bandwidth: bytes/s through the proxy per client <= soak_max_bytes_s
  - stuck: no live server mech trying to move (|vel| > 1 m/s) while displacing
    < 0.5 m over 180 ticks -- pushing into a wall, not a defender holding a beacon
"""
import glob
import json
import math
import os
import re

from . import base

NAME = "soak"

DEFAULTS = {"soak_max_orphan_growth": 50, "soak_max_growth": 0.25, "soak_max_phys_ms": 16.0,
            "soak_max_bytes_s": 65536, "soak_stuck_ticks": 180}

_PERF = re.compile(r"\[Harness\] perf tick=(\d+) phys_ms=([\d.]+) objects=(\d+) nodes=(\d+) orphans=(\d+) mem=(\d+)")


def _perf(path):
    return [tuple(float(x) for x in m.groups()) for m in _PERF.finditer(open(path, errors="replace").read())]


def check_stuck(server, window, end_tick=None):
    by_mech = {}
    for s in server.snaps:
        by_mech.setdefault(s["mech_id"], []).append(s)
    for mid, snaps in by_mech.items():
        snaps.sort(key=lambda s: s["tick"])
        for a, b in zip(snaps, snaps[window:]):
            if a["health"] <= 0 or b["health"] <= 0 or "vel" not in a:
                continue
            if end_tick is not None and b["tick"] >= end_tick:
                break  # match over: mechs are frozen with their last velocity
            seg = [s for s in snaps if a["tick"] <= s["tick"] <= b["tick"]]
            trying = all(math.hypot(s["vel"][0], s["vel"][2]) > 1.0 for s in seg)
            if trying and math.dist(a["pos"], b["pos"]) < 0.5:
                return mid, a["tick"], b["tick"]
    return None


def run(ctx):
    run_dir = ctx.get("run_dir") or ""
    th = {**DEFAULTS, **ctx.get("thresholds", {})}
    slog = os.path.join(run_dir, "server.log")
    if not os.path.exists(slog) or "[Harness] perf" not in open(slog, errors="replace").read():
        return base.verdict(NAME, base.SKIP, note="not a soak run (no perf samples)")
    m_end = re.search(r"\[Harness\] match ended at sync tick (\d+)", open(slog, errors="replace").read())
    if m_end is None:
        return base.verdict(NAME, base.FAIL, field="softlock", note="match never ended within the run (softlock?)")
    end_tick = int(m_end.group(1))
    notes = []
    for path in sorted(glob.glob(os.path.join(run_dir, "*.log"))):
        role = os.path.basename(path)[:-4]
        p = _perf(path)
        if len(p) < 3:
            continue
        first, last = p[1], p[-1]  # p[0] is during load
        if last[4] - first[4] > th["soak_max_orphan_growth"]:
            return base.verdict(NAME, base.FAIL, peer=role, field="orphans",
                                note="%s orphan nodes grew %d -> %d (leak)" % (role, first[4], last[4]))
        for i, label in ((2, "objects"), (5, "static mem")):
            if first[i] > 0 and (last[i] - first[i]) / first[i] > th["soak_max_growth"]:
                return base.verdict(NAME, base.FAIL, peer=role, field=label,
                                    note="%s %s grew %.0f -> %.0f (+%.0f%%)" % (role, label, first[i], last[i],
                                                                              100 * (last[i] - first[i]) / first[i]))
        if role == "server":
            # Single-frame samples on a shared dev box are noisy: gate the median (gross
            # regressions), report p90/max. Combat spikes are tracked by T165 profiling.
            ms = sorted(x[1] for x in p[1:])
            p50, p90 = ms[len(ms) // 2], ms[min(len(ms) - 1, int(len(ms) * 0.9))]
            notes.append("server phys p50 %.1f / p90 %.1f / max %.1f ms" % (p50, p90, ms[-1]))
            if p50 > th["soak_max_phys_ms"]:
                return base.verdict(NAME, base.FAIL, peer=role, field="phys_ms", magnitude=p50,
                                    note="server physics median %.2f ms/frame > %.1f ms budget" % (p50, th["soak_max_phys_ms"]))
    meta = json.load(open(os.path.join(run_dir, "meta.json"))) if os.path.exists(os.path.join(run_dir, "meta.json")) else {}
    stats = (meta.get("net") or {}).get("stats") or {}
    ticks = ctx["primary"]["server"].ticks
    secs = max(1.0, (ticks[-1] - ticks[0]) / 60.0) if ticks else 1.0
    clients = max(1, stats.get("clients", 1))
    if stats.get("s2c_bytes"):
        bps = (stats["s2c_bytes"] + stats.get("c2s_bytes", 0)) / secs / clients
        notes.append("%.1f KB/s per client" % (bps / 1024))
        if bps > th["soak_max_bytes_s"]:
            return base.verdict(NAME, base.FAIL, field="bandwidth", magnitude=bps,
                                note="%.1f KB/s per client > budget %.1f" % (bps / 1024, th["soak_max_bytes_s"] / 1024))
    stuck = check_stuck(ctx["primary"]["server"], int(th["soak_stuck_ticks"]), end_tick)
    if stuck:
        return base.verdict(NAME, base.FAIL, mech_id=stuck[0], first_tick=stuck[1], field="stuck",
                            note="%s pushing (>1 m/s) but stuck (<0.5 m) from tick %d to %d" % stuck)
    return base.verdict(NAME, base.PASS, note="match ended; no leaks/stuck; " + ", ".join(notes))
