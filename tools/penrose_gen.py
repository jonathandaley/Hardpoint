#!/usr/bin/env python3
# Penrose P3 tiling via de Bruijn pentagrid dual method.
# No dependencies. Outputs VERTEX and EDGE TSV lines to stdout.
#
# Run: python3 tools/penrose_gen.py
#
# Pentagon V0 points +Z (north) = +Y in 2D tool space.
# All edges should be length SIDE (10.0m). Fat tiles at angle pairs ±1 mod 5.

import math

SIDE = 10.0
ARENA_RADIUS = 72.0
GAMMA = 0.0        # 0 = canonical sun tiling; degeneracy at origin handled below
GRID_RANGE = 12    # how many lines per family to consider

# Family direction angles: start at 90° (north), step by 72°
# e_k points perpendicular to family k's lines
def ek(k):
    a = math.pi / 2 + 2 * math.pi * k / 5
    return (math.cos(a), math.sin(a))

DIRS = [ek(k) for k in range(5)]

def dot(a, b):
    return a[0]*b[0] + a[1]*b[1]

def vec_key(x, y):
    return "%.3f,%.3f" % (round(x, 3), round(y, 3))

def tiling_vertex(coords):
    # Sum of coords[k] * DIRS[k] * SIDE
    x = sum(coords[k] * DIRS[k][0] for k in range(5)) * SIDE
    y = sum(coords[k] * DIRS[k][1] for k in range(5)) * SIDE
    return (x, y)

def main():
    vertices = {}  # key -> (x, y)
    edges = {}     # key -> {mid, angle, length, tile_type}

    for j in range(5):
        for k in range(j+1, 5):
            diff = (k - j) % 5
            tile_type = "fat" if diff in (1, 4) else "thin"

            ej = DIRS[j]
            ek_ = DIRS[k]
            # Lines of family j: x·ej = (n + GAMMA)*SIDE  for integer n
            # Lines of family k: x·ek = (m + GAMMA)*SIDE  for integer m
            # Solve for intersection point, then find the 4 rhombus vertices

            # 2x2 system: ej·p = (n+G)*SIDE,  ek·p = (m+G)*SIDE
            det = ej[0]*ek_[1] - ej[1]*ek_[0]
            if abs(det) < 1e-9:
                continue

            for n in range(-GRID_RANGE, GRID_RANGE+1):
                for m in range(-GRID_RANGE, GRID_RANGE+1):
                    # For GAMMA=0 at origin all 5 family lines coincide, making
                    # ceil() ambiguous.  Use a tiny positive offset so the thin
                    # tiles at n=m=0 land in the correct cells (second-ring tiles,
                    # not spurious tiles with a vertex at the origin).
                    g = 1e-6 if (GAMMA == 0.0 and n == 0 and m == 0) else GAMMA
                    rj = (n + g) * SIDE
                    rk = (m + g) * SIDE
                    # Intersection point of line n,j and line m,k
                    px = (rj * ek_[1] - rk * ej[1]) / det
                    py = (rk * ej[0] - rj * ek_[0]) / det

                    # Skip if center of rhombus is far outside arena
                    if math.hypot(px, py) > ARENA_RADIUS + SIDE * 2:
                        continue

                    # For each of the 4 rhombus vertices, compute the
                    # grid coordinates for all 5 families at that corner.
                    # Corner (dn, dm) offsets: (0,0),(1,0),(1,1),(0,1)
                    quad = []
                    for dn, dm in ((0,0),(1,0),(1,1),(0,1)):
                        coords = []
                        for i in range(5):
                            if i == j:
                                coords.append(n + dn)
                            elif i == k:
                                coords.append(m + dm)
                            else:
                                # ceil(intersection · e_i / SIDE - g)
                                coords.append(math.ceil(dot((px, py), DIRS[i]) / SIDE - g))
                        quad.append(tiling_vertex(coords))

                    # Register vertices and edges
                    for v in quad:
                        if math.hypot(*v) <= ARENA_RADIUS + 1.0:
                            vertices[vec_key(*v)] = v

                    for i in range(4):
                        a = quad[i]
                        b = quad[(i+1) % 4]
                        ka = vec_key(*a)
                        kb = vec_key(*b)
                        ekey = (ka+"|"+kb) if ka < kb else (kb+"|"+ka)
                        if ekey not in edges:
                            length = math.hypot(b[0]-a[0], b[1]-a[1])
                            mid = ((a[0]+b[0])*0.5, (a[1]+b[1])*0.5)
                            angle = math.atan2(b[1]-a[1], b[0]-a[0])
                            edges[ekey] = {"mid": mid, "angle": angle,
                                           "length": length, "type": tile_type}
                        elif tile_type == "thin":
                            edges[ekey]["type"] = "thin"

    # Filter edges to arena radius and check lengths
    good_edges = {k: e for k, e in edges.items()
                  if math.hypot(*e["mid"]) <= ARENA_RADIUS + 1.0
                  and abs(e["length"] - SIDE) < 0.01}

    print("# Penrose P3 — de Bruijn method — Arena One")
    print("# SIDE=%.1fm  arena_radius=%.1fm" % (SIDE, ARENA_RADIUS))
    print("# Pentagon V0 pointing +Z (north); team boundary at X=0")
    print()
    print("# VERTICES (%d)  VERTEX\tx\ty" % len(vertices))
    for v in vertices.values():
        print("VERTEX\t%.4f\t%.4f" % v)

    print()
    print("# EDGES (%d)  EDGE\tmid_x\tmid_y\tangle_rad\tlength\ttype" % len(good_edges))
    for e in good_edges.values():
        print("EDGE\t%.4f\t%.4f\t%.6f\t%.4f\t%s" % (
            e["mid"][0], e["mid"][1], e["angle"], e["length"], e["type"]))

    # Sanity check
    lengths = sorted(set(round(e["length"], 2) for e in edges.values()))
    import sys
    print("\n# Edge length distribution: %s" % lengths, file=sys.stderr)
    print("# Total edges before filter: %d, after: %d" % (len(edges), len(good_edges)), file=sys.stderr)

if __name__ == "__main__":
    main()
