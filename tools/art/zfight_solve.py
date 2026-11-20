"""T533: pick a small per-hardpoint offset that keeps every weapon that fits the slot clear of the
mech body's faces (no same-facing face pairs closer than CLEAR along any axis).

  godot --headless --path . res://tools/gd_probes/weapon_zfight.tscn -- --dump=build/scratch/zf_dump.json
  python3 tools/art/zfight_solve.py build/scratch/zf_dump.json [--apply]

Per mech slot and per axis, the offset d (mm, |d| <= MAX_MM, 0.5 mm steps, smallest |d| wins) must keep
|delta - d| >= CLEAR for every dumped pair (moving the weapon by d moves its face plane by d). --apply
adds it to the slot's `position` in resources/mechs/<Mech>.tres. Then rerun the probe: it is the judge.
"""
import json
import re
import sys
from collections import defaultdict

CLEAR = float(next((a[8:] for a in sys.argv if a.startswith("--clear=")), "0.004"))  # m
MAX_MM = 12


def solve(pairs):
    by = defaultdict(list)
    for p in pairs:
        by[(p["mech"], p["slot"], p["axis"])].append(p["delta"])
    out = defaultdict(lambda: [0.0, 0.0, 0.0])
    stuck = []
    for (mech, slot, ax), deltas in sorted(by.items()):
        if all(abs(x) >= CLEAR for x in deltas):
            continue
        cands = sorted((i * 0.0005 for i in range(-2 * MAX_MM, 2 * MAX_MM + 1)), key=abs)
        d = next((c for c in cands if all(abs(x - c) >= CLEAR for x in deltas)), None)
        if d is None:
            stuck.append((mech, slot, "xyz"[ax]))
            continue
        out[(mech, slot)][ax] = d
    return out, stuck


def apply(offsets):
    for (mech, slot), d in sorted(offsets.items()):
        path = "resources/mechs/" + mech
        s = open(path).read()
        # slot i = the i-th entry of weapon_slots = [SubResource("a"), ...]
        ids = re.findall(r'SubResource\("([^"]+)"\)', re.search(r"weapon_slots = \[([^\]]*)\]", s).group(1))
        sid = ids[slot]
        block = re.search(r'\[sub_resource [^\]]*id="%s"\][^\[]*' % re.escape(sid), s)
        m = re.search(r"position = Vector3\(([^)]*)\)", block.group(0))
        v = [float(x) for x in m.group(1).split(",")]
        nv = [round(v[i] + d[i], 4) for i in range(3)]
        nb = block.group(0).replace(m.group(0), "position = Vector3(%s)" % ", ".join("%g" % x for x in nv))
        s = s[:block.start()] + nb + s[block.end():]
        open(path, "w").write(s)
        print("%s slot %d: %s -> %s" % (mech, slot, v, nv))


if __name__ == "__main__":
    offsets, stuck = solve(json.load(open(sys.argv[1])))
    for k, d in sorted(offsets.items()):
        print(k, ["%+.1f mm" % (x * 1000) for x in d])
    if stuck:
        print("NO OFFSET within %d mm:" % MAX_MM, stuck)
    if "--apply" in sys.argv:
        apply(offsets)
