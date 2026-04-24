#!/usr/bin/env python3
# Penrose P3 tiling via de Bruijn pentagrid dual method.
# No dependencies. Outputs VERTEX and EDGE TSV lines to stdout.
#
# Run: python3 tools/penrose_gen.py
#
# Pentagon V0 points +Z (north) = +Y in 2D tool space.
# All edges should be length SIDE (10.0m). Fat tiles at angle pairs ±1 mod 5.
#
# Clipping policy: generate ALL rhombuses in GRID_RANGE with no early exit.
# Clip only at the very end. Edge included iff BOTH endpoints are inside
# DISPLAY_RADIUS — guarantees no half-edges at the boundary.

import math

SIDE          = 10.0
DISPLAY_RADIUS = 110.0   # edges with both verts inside this radius are shown
GAMMA         = 0.0      # 0 = canonical sun tiling; degeneracy at origin handled below
GRID_RANGE    = 20       # lines per family — must be large enough to cover DISPLAY_RADIUS

# Family direction angles: start at 90° (north), step by 72°
def ek(k):
    a = math.pi / 2 + 2 * math.pi * k / 5
    return (math.cos(a), math.sin(a))

DIRS = [ek(k) for k in range(5)]

def dot(a, b):
    return a[0]*b[0] + a[1]*b[1]

def vec_key(x, y):
    return "%.3f,%.3f" % (round(x, 3), round(y, 3))

def tiling_vertex(coords):
    x = sum(coords[k] * DIRS[k][0] for k in range(5)) * SIDE
    y = sum(coords[k] * DIRS[k][1] for k in range(5)) * SIDE
    return (x, y)

def main():
    vertices = {}  # key -> (x, y)
    edges    = {}  # key -> {va, vb, mid, angle, length, type}

    for j in range(5):
        for k in range(j+1, 5):
            diff = (k - j) % 5
            tile_type = "fat" if diff in (1, 4) else "thin"

            ej  = DIRS[j]
            ek_ = DIRS[k]
            det = ej[0]*ek_[1] - ej[1]*ek_[0]
            if abs(det) < 1e-9:
                continue

            for n in range(-GRID_RANGE, GRID_RANGE+1):
                for m in range(-GRID_RANGE, GRID_RANGE+1):
                    g  = 1e-6 if (GAMMA == 0.0 and n == 0 and m == 0) else GAMMA
                    rj = (n + g) * SIDE
                    rk = (m + g) * SIDE
                    px = (rj * ek_[1] - rk * ej[1]) / det
                    py = (rk * ej[0] - rj * ek_[0]) / det

                    # No early-exit clipping — generate every rhombus in range
                    quad = []
                    for dn, dm in ((0,0),(1,0),(1,1),(0,1)):
                        coords = []
                        for i in range(5):
                            if i == j:
                                coords.append(n + dn)
                            elif i == k:
                                coords.append(m + dm)
                            else:
                                coords.append(math.ceil(dot((px, py), DIRS[i]) / SIDE - g))
                        quad.append(tiling_vertex(coords))

                    for v in quad:
                        vertices[vec_key(*v)] = v

                    for i in range(4):
                        a = quad[i]
                        b = quad[(i+1) % 4]
                        ka = vec_key(*a)
                        kb = vec_key(*b)
                        ekey = (ka+"|"+kb) if ka < kb else (kb+"|"+ka)
                        if ekey not in edges:
                            length = math.hypot(b[0]-a[0], b[1]-a[1])
                            mid    = ((a[0]+b[0])*0.5, (a[1]+b[1])*0.5)
                            angle  = math.atan2(b[1]-a[1], b[0]-a[0])
                            edges[ekey] = {"va": ka, "vb": kb, "mid": mid,
                                           "angle": angle, "length": length,
                                           "type": tile_type}
                        elif tile_type == "thin":
                            edges[ekey]["type"] = "thin"

    # Clip last: keep only vertices inside DISPLAY_RADIUS
    display_verts = {k: v for k, v in vertices.items()
                     if math.hypot(*v) <= DISPLAY_RADIUS}

    # Keep only edges where BOTH endpoints are display vertices
    # and length is correct (guards against floating-point drift at degenerate corners)
    good_edges = {k: e for k, e in edges.items()
                  if e["va"] in display_verts
                  and e["vb"] in display_verts
                  and abs(e["length"] - SIDE) < 0.01}

    # Trim vertex set to only those actually used by good edges
    used_keys = set()
    for e in good_edges.values():
        used_keys.add(e["va"])
        used_keys.add(e["vb"])
    display_verts = {k: display_verts[k] for k in used_keys if k in display_verts}

    print("# Penrose P3 — de Bruijn method — Arena One")
    print("# SIDE=%.1fm  display_radius=%.1fm  grid_range=%d" % (SIDE, DISPLAY_RADIUS, GRID_RANGE))
    print("# Pentagon V0 pointing +Z (north); team boundary at X=0")
    print("# Clip policy: both endpoints inside radius — no half-edges")
    print()
    print("# VERTICES (%d)" % len(display_verts))
    for v in display_verts.values():
        print("VERTEX\t%.4f\t%.4f" % v)

    print()
    print("# EDGES (%d)" % len(good_edges))
    for e in good_edges.values():
        print("EDGE\t%.4f\t%.4f\t%.6f\t%.4f\t%s" % (
            e["mid"][0], e["mid"][1], e["angle"], e["length"], e["type"]))

    import sys
    lengths = sorted(set(round(e["length"], 2) for e in edges.values()))
    print("\n# Edge length distribution: %s" % lengths, file=sys.stderr)
    print("# Total rhombus edges: %d  |  after clip: %d  |  vertices used: %d" % (
        len(edges), len(good_edges), len(display_verts)), file=sys.stderr)

if __name__ == "__main__":
    main()
