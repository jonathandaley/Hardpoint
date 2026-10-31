"""hud_layout oracle (T147, B-d class): HUD geometry from the harness HUD dumps
(<role>.hud.jsonl, scenario "hud_dump_ticks"). Headless Godot still computes
Control layout, so no rendering is needed. FAILs on:
  - a visible HUD control with area that sits outside the viewport,
  - weapon icons (WeaponHUD/Icon<N>) overlapping each other or shrunk below
    90% of the 36x22 slot,
  - the client's weapon icon rects differing from the server's at the same dump
    (every harness peer flies the same loadout).
B-d (client icons 'squashed together at the bottom') never reproduced in the
harness (headless, rendered under Xvfb, 4 loadouts); this guards the class.
"""
import glob
import json
import os

from . import base

NAME = "hud_layout"

SLOT = (36.0, 22.0)
TOL = 1.0


def _overlap(a, b):
    return (a[0] < b[0] + b[2] - TOL and b[0] < a[0] + a[2] - TOL and
            a[1] < b[1] + b[3] - TOL and b[1] < a[1] + a[3] - TOL)


def _icons(dump):
    return sorted((c["path"], c["rect"]) for c in dump["controls"] if c["path"].startswith("WeaponHUD/Icon"))


def check_dump(role, dump):
    vw, vh = dump["viewport"]
    for c in dump["controls"]:
        x, y, w, h = c["rect"]
        if w * h > 0 and (x < -TOL or y < -TOL or x + w > vw + TOL or y + h > vh + TOL):
            return "%s tick %d: %s off-screen at %s" % (role, dump["tick"], c["path"], [round(v) for v in c["rect"]])
    icons = _icons(dump)
    for p, r in icons:
        if r[2] < SLOT[0] * 0.9 or r[3] < SLOT[1] * 0.9:
            return "%s tick %d: %s shrunk to %.0fx%.0f" % (role, dump["tick"], p, r[2], r[3])
    for i in range(len(icons)):
        for j in range(i + 1, len(icons)):
            if _overlap(icons[i][1], icons[j][1]):
                return "%s tick %d: %s overlaps %s" % (role, dump["tick"], icons[i][0], icons[j][0])
    return None


def run(ctx):
    run_dir = ctx.get("run_dir") or ""
    dumps = {}
    for path in sorted(glob.glob(os.path.join(run_dir, "*.hud.jsonl"))):
        role = os.path.basename(path)[: -len(".hud.jsonl")]
        dumps[role] = [json.loads(l) for l in open(path) if l.strip()]
    if not dumps:
        return base.verdict(NAME, base.SKIP, note="no HUD dumps (scenario has no hud_dump_ticks)")
    n = 0
    for role, ds in dumps.items():
        for d in ds:
            n += 1
            bad = check_dump(role, d)
            if bad:
                return base.verdict(NAME, base.FAIL, peer=role, first_tick=d["tick"], note=bad)
    server = {d["tick"]: d for d in dumps.get("server", [])}
    for role, ds in dumps.items():
        if role == "server":
            continue
        for d in ds:
            s = server.get(d["tick"])
            if s is not None and [r for _, r in _icons(s)] != [r for _, r in _icons(d)]:
                return base.verdict(NAME, base.FAIL, peer=role, first_tick=d["tick"],
                                    note="%s tick %d: weapon icons %s != server %s" % (
                                        role, d["tick"], [[round(v) for v in r] for _, r in _icons(d)],
                                        [[round(v) for v in r] for _, r in _icons(s)]))
    return base.verdict(NAME, base.PASS, note="%d HUD dumps on-screen, icons separate and matching server" % n)
