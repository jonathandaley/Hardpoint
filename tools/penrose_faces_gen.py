#!/usr/bin/env python3
"""Parse pynrose_18.svg rhombus faces for wall painting.

Outputs _PENROSE_FACES: [[u0,v0, u1,v1, u2,v2, u3,v3, bucket], ...]
Wall-local coords in metres, centred at (0, 11) on the 32×22m face.
Filtered to the same bounds used by _paint_wall_penrose.
"""

import re, math

SVG        = "tools/pynrose_18.svg"
SVG_CX     = 50.0   # tiling centre in SVG coords
SVG_CY     = 50.0
WALL_SCALE = 1.5    # matches SCALE*SIDE (0.15 * 10m) from edge strips
WALL_CY    = 11.0   # vertical centre on 22m wall

HALF_W  = 16.5
V_MIN   = -0.75
V_MAX   = 21.5
BUFFER  = 1.0       # include faces whose centre is this far outside bounds


def to_wall(sx, sy):
    return (sx - SVG_CX) * WALL_SCALE, -(sy - SVG_CY) * WALL_SCALE + WALL_CY


def bucket(angle):
    return (int(round(angle / (math.pi / 5.0))) % 5 + 5) % 5


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

        # reject any face with a vertex above the wall top or below the floor
        if any(v > V_MAX or v < V_MIN for _, v in wv):
            continue

        b = 1 if cls == "thick" else 0  # 0=thin(pale blue), 1=fat(crimson)

        row = []
        for u, v in wv:
            row += [round(u, 4), round(v, 4)]
        row.append(b)
        faces.append(row)

    print(f"# {len(faces)} rhombus faces (filtered to wall bounds)")
    print()
    print("const _PENROSE_FACES: Array = [")
    for f in faces:
        vals = ", ".join(str(x) for x in f)
        print(f"\t[{vals}],")
    print("]")


if __name__ == "__main__":
    main()
