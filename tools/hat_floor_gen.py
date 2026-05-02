#!/usr/bin/env python3
"""Parse hat_01.svg cluster polygons for hat tile floor painting.

Outputs _HAT_CLUSTERS: [[bucket, x0,z0, x1,z1, ...], ...]
  bucket 0 = R-dominant (pink/peach), 1 = G-dominant (green/teal),
  2 = B-dominant (blue/purple)
  x,z in game metres, centred at world origin.
Filtered to R_MAX from origin. Fan-triangulate at runtime from centroid.
"""

import re, math

SVG      = "hat_01.svg"
SVG_CX   = 8970.0
SVG_CY   = 6357.0
SCALE    = 0.03    # SVG units → game metres
R_MAX    = 97.0    # keep clusters within arena wall radius


def color_bucket(style: str) -> int:
    m = re.search(r'fill:rgb\(([\d.]+)%,([\d.]+)%,([\d.]+)%\)', style)
    if not m:
        return -1
    r, g, b = float(m[1]), float(m[2]), float(m[3])
    # exclude background (near-white or near-equal channels)
    if min(r, g, b) > 85.0:
        return -1
    if r >= g and r >= b:
        return 0
    if g >= r and g >= b:
        return 1
    return 2


def main():
    with open(SVG) as f:
        src = f.read()

    # Each <path ...> element
    entries = re.findall(r'<path\s+style="([^"]+)"[^>]+d="([^"]+)"', src)

    clusters = []
    for style, d in entries:
        bucket = color_bucket(style)
        if bucket < 0:
            continue  # background

        pts = re.findall(r'[ML]\s+([\d.]+)\s+([\d.]+)', d)
        if len(pts) < 5:
            continue
        # drop closing duplicate (last point = first point)
        coords = [(float(x), float(y)) for x, y in pts]
        if len(coords) > 1 and abs(coords[-1][0]-coords[0][0]) < 0.1 \
                           and abs(coords[-1][1]-coords[0][1]) < 0.1:
            coords = coords[:-1]

        # convert to game coords
        game = [((sx - SVG_CX) * SCALE, (sy - SVG_CY) * SCALE)
                for sx, sy in coords]

        cx = sum(p[0] for p in game) / len(game)
        cz = sum(p[1] for p in game) / len(game)
        if math.sqrt(cx*cx + cz*cz) > R_MAX:
            continue

        row = [bucket]
        for gx, gz in game:
            row += [round(gx, 3), round(gz, 3)]
        clusters.append(row)

    print(f"# {len(clusters)} hat clusters filtered to R={R_MAX}m")
    print()
    print("const _HAT_CLUSTERS: Array = [")
    for c in clusters:
        vals = ", ".join(str(v) for v in c)
        print(f"\t[{vals}],")
    print("]")


if __name__ == "__main__":
    main()
