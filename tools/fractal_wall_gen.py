#!/usr/bin/env python3
"""tools/fractal_wall_gen.py — EXTERIOR circular wall generator.
ARCHIVED for interior walls (those use _PENROSE_SVG_EDGES directly).

Outputs two GDScript arrays for Arena.gd:
  _WALL_SEGS   — [world_x, world_z, rot_y]  one entry per segment
  _WALL_PARTS  — [lx, ly, lz, sx, sy, sz]   relief template in segment local space

Local-space convention (per segment):
  +X = CW tangential (along wall face)
  +Y = up
  +Z = outward radial (away from arena centre)
  Protrusions into arena = -Z.  Back slab = +Z.
"""

import math

# ── Bowl / arena constants ────────────────────────────────────────────────────
BOWL_CX   = 5.1    # bowl centre X (world)
BOWL_CZ   = 11.2   # bowl centre Z (world)
R_WALL    = 107.0  # distance from bowl centre to wall inner face

# ── Segment count ─────────────────────────────────────────────────────────────
N_SEGS    = 20     # number of circular segments (20 = decagonal symmetry × 2)

# ── Wall geometry ─────────────────────────────────────────────────────────────
WALL_H    = 22.0   # total visual height
OVERLAP   = 1.2    # extra width each side to close inter-segment gap

SLAB_D    = 1.2    # back slab depth  (+Z)
PLINTH_H  = 2.8    # base plinth height
PLINTH_D  = 1.1    # plinth protrusion (-Z)
CORNICE_H = 1.6    # top cornice height
CORNICE_D = 0.9    # cornice protrusion (-Z)
COURSE_H  = 0.5    # mid string-course height
COURSE_D  = 0.45   # string-course protrusion (-Z)
COURSE_Y  = 11.0   # Y of string-course centre (≈ bowl rim)

PIER_STEP = 11.0   # main pilaster spacing along chord
PIER_W    = 2.2    # main pilaster width
PIER_D    = 0.75   # main pilaster protrusion (-Z)
SUB_W     = 0.85   # sub-pilaster width (bay midpoint)
SUB_D     = 0.38
MINI_W    = 0.38   # mini-pilaster width (bay quarter-points)
MINI_D    = 0.20
# ──────────────────────────────────────────────────────────────────────────────


def generate() -> None:
    chord  = 2.0 * R_WALL * math.sin(math.pi / N_SEGS)
    seg_w  = chord + 2.0 * OVERLAP

    # ── Segment positions & rotations ─────────────────────────────────────────
    segs = []
    for i in range(N_SEGS):
        a     = 2.0 * math.pi * i / N_SEGS
        wx    = BOWL_CX + R_WALL * math.cos(a)
        wz    = BOWL_CZ + R_WALL * math.sin(a)
        rot_y = math.pi / 2.0 - a          # makes local +Z = outward radial
        segs.append((wx, wz, rot_y))

    # ── Relief template (local space) ─────────────────────────────────────────
    parts = []

    def p(lx, ly, lz, sx, sy, sz):
        parts.append((lx, ly, lz, sx, sy, sz))

    p(0.0, WALL_H * 0.5,      SLAB_D * 0.5,     seg_w, WALL_H,    SLAB_D)     # back slab
    p(0.0, PLINTH_H * 0.5,   -PLINTH_D * 0.5,   seg_w, PLINTH_H,  PLINTH_D)   # plinth
    p(0.0, WALL_H-CORNICE_H*0.5, -CORNICE_D*0.5, seg_w, CORNICE_H, CORNICE_D)  # cornice
    p(0.0, COURSE_Y,          -COURSE_D * 0.5,   seg_w, COURSE_H,  COURSE_D)   # string course

    n  = max(1, int(chord / PIER_STEP))
    xs = [-chord * 0.5 + i * (chord / n) for i in range(n + 1)]
    for x in xs:
        p(x, WALL_H * 0.5, -PIER_D * 0.5, PIER_W, WALL_H, PIER_D)

    for i in range(n):
        xL, xR = xs[i], xs[i + 1]
        xM = (xL + xR) * 0.5
        p(xM, WALL_H * 0.5, -SUB_D * 0.5, SUB_W, WALL_H, SUB_D)
        for xQ in [(xL * 3 + xR) * 0.25, (xL + xR * 3) * 0.25]:
            p(xQ, WALL_H * 0.5, -MINI_D * 0.5, MINI_W, WALL_H, MINI_D)

    # ── Output ────────────────────────────────────────────────────────────────
    print("const _WALL_SEGS: Array = [")
    for s in segs:
        print(f"\t[{s[0]:.3f}, {s[1]:.3f}, {s[2]:.5f}],")
    print("]")
    print()
    print("const _WALL_PARTS: Array = [")
    for q in parts:
        vals = ", ".join(f"{v:.3f}" for v in q)
        print(f"\t[{vals}],")
    print("]")
    print()
    print(f"# {N_SEGS} segs × {len(parts)} parts = {N_SEGS * len(parts)} boxes")
    print(f"# chord={chord:.2f}m  seg_w={seg_w:.2f}m")


if __name__ == "__main__":
    generate()
