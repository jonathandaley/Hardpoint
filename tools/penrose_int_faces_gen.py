#!/usr/bin/env python3
"""Parse pynrose_18.svg rhombus faces for interior wall painting.

Interior walls: 10m long × 3.2m tall.
Outputs _INT_PENROSE_FACES: [[u0,v0, u1,v1, u2,v2, u3,v3, bucket], ...]
  u = along wall (local z), v = up (local y), centred at (0, 1.6).
"""

import re, math

SVG        = "tools/pynrose_18.svg"
SVG_CX     = 50.0
SVG_CY     = 50.0
WALL_SCALE = 0.6     # smaller tiling for shorter walls
WALL_CY    = 2.65    # centre of max wall height (3.2 + 2.1) / 2

HALF_W  = 5.0        # exact L/2
V_MIN   = 0.0        # wall bottom
V_MAX   = 5.3        # max wall height (H=3.2 + BOWL_STEP_H=2.1)
BUFFER  = 0.5


def to_wall(sx, sy):
    return (sx - SVG_CX) * WALL_SCALE, -(sy - SVG_CY) * WALL_SCALE + WALL_CY


def main():
    src = open(SVG).read()
    paths = re.findall(
        r'<path class="(thin|thick)Rhombus"[^>]*'
        r'd="M\s*([\d.\-]+),([\d.\-]+)\s+'
        r'([\d.\-]+),([\d.\-]+)\s+'
        r'([\d.\-]+),([\d.\-]+)\s+'
        r'([\d.\-]+),([\d.\-]+)\s+z"',
        src)

    faces = []
    for cls, x0, y0, x1, y1, x2, y2, x3, y3 in paths:
        sv = [(float(x0), float(y0)), (float(x1), float(y1)),
              (float(x2), float(y2)), (float(x3), float(y3))]
        cx_svg = sum(p[0] for p in sv) / 4
        cy_svg = sum(p[1] for p in sv) / 4
        cu, cv = to_wall(cx_svg, cy_svg)

        if abs(cu) > HALF_W + BUFFER or cv < V_MIN - BUFFER or cv > V_MAX + BUFFER:
            continue

        wv = [to_wall(sx, sy) for sx, sy in sv]

        if any(v > V_MAX or v < V_MIN or abs(u) > HALF_W for u, v in wv):
            continue

        b = 1 if cls == "thick" else 0

        row = []
        for u, v in wv:
            row += [round(u, 4), round(v, 4)]
        row.append(b)
        faces.append(row)

    print(f"# {len(faces)} interior rhombus faces (10m x 3.2m walls)")
    print()
    print("const _INT_PENROSE_FACES: Array = [")
    for f in faces:
        vals = ", ".join(str(x) for x in f)
        print(f"\t[{vals}],")
    print("]")


if __name__ == "__main__":
    main()
