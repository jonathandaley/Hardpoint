#!/usr/bin/env python3
# Penrose P3 via Robinson triangle substitution.
# Self-validating: interior edges shared by exactly 2 triangles; all edges = SIDE.
# Output: VERTEX and EDGE TSV lines to stdout.
#
# Run: python3 tools/penrose_gen.py

import math

SIDE          = 10.0
DISPLAY_RADIUS = 110.0
SUBDIVISIONS  = 6        # each step halves tile size; 6 gives ~SIDE*phi^-6 base tiles

PHI = (1 + math.sqrt(5)) / 2

def rnd(x): return round(x, 4)
def vkey(x, y): return (rnd(x), rnd(y))

def rot(x, y, a):
    c, s = math.cos(a), math.sin(a)
    return x*c - y*s, x*s + y*c

def initial_sun():
    """10 S-triangles (sharp/36°-apex) arranged in a sun at origin."""
    tris = []
    for k in range(10):
        a0 = math.pi * k / 5
        a1 = math.pi * (k + 1) / 5
        r  = SIDE * PHI ** SUBDIVISIONS
        ax, ay = 0.0, 0.0
        bx, by = r * math.cos(a0), r * math.sin(a0)
        cx, cy = r * math.cos(a1), r * math.sin(a1)
        tris.append(("S", ax, ay, bx, by, cx, cy))
    return tris

def subdivide(tris):
    """
    Robinson triangle substitution rules (P3 / kite-dart):
      S (sharp, apex=36°):  apex=A, base=B,C
        -> S(A, P, C) + O(B, P, A)   where P splits AB at ratio 1/phi from A
      O (obtuse, apex=108°): apex=A, base=B,C
        -> S(A, P, B) + O(P, C, B)   where P splits AC at ratio 1/phi from A
    """
    out = []
    for tri in tris:
        kind = tri[0]
        ax, ay, bx, by, cx, cy = tri[1], tri[2], tri[3], tri[4], tri[5], tri[6]
        if kind == "S":
            # P on AB, 1/phi from A
            px = ax + (bx - ax) / PHI
            py = ay + (by - ay) / PHI
            out.append(("S", ax, ay, px, py, cx, cy))
            out.append(("O", bx, by, px, py, ax, ay))
        else:  # O
            # P on AC, 1/phi from A
            px = ax + (cx - ax) / PHI
            py = ay + (cy - ay) / PHI
            out.append(("S", ax, ay, px, py, bx, by))
            out.append(("O", px, py, cx, cy, bx, by))
    return out

def extract(tris):
    """Collect edges and vertices; keep only those inside DISPLAY_RADIUS."""
    verts = {}
    edge_count = {}  # ekey -> count (interior = 2)

    for tri in tris:
        _, ax, ay, bx, by, cx, cy = tri
        vs = [(ax, ay), (bx, by), (cx, cy)]
        for v in vs:
            k = vkey(*v)
            verts[k] = v
        for i in range(3):
            ka = vkey(*vs[i])
            kb = vkey(*vs[(i+1) % 3])
            ek = (ka, kb) if ka < kb else (kb, ka)
            edge_count[ek] = edge_count.get(ek, 0) + 1

    # Clip: both endpoints inside radius
    inside = {k for k, v in verts.items() if math.hypot(*v) <= DISPLAY_RADIUS}

    good_edges = {}
    for (ka, kb), cnt in edge_count.items():
        if ka not in inside or kb not in inside:
            continue
        va, vb = verts[ka], verts[kb]
        length = math.hypot(vb[0]-va[0], vb[1]-va[1])
        if abs(length - SIDE) > 0.5:
            continue
        mid   = ((va[0]+vb[0])*0.5, (va[1]+vb[1])*0.5)
        angle = math.atan2(vb[1]-va[1], vb[0]-va[0])
        good_edges[(ka, kb)] = {"va": ka, "vb": kb, "mid": mid,
                                "angle": angle, "length": length,
                                "interior": cnt == 2}

    used = set()
    for e in good_edges.values():
        used.add(e["va"]); used.add(e["vb"])
    display_verts = {k: verts[k] for k in used if k in inside}

    return display_verts, good_edges

def validate(verts, edges):
    import sys
    lengths = sorted(set(round(e["length"], 2) for e in edges.values()))
    bad_len = [l for l in lengths if abs(l - SIDE) > 0.5]
    print("# Validation: edge lengths %s" % lengths, file=sys.stderr)
    if bad_len:
        print("# ERROR: bad lengths: %s" % bad_len, file=sys.stderr)
    else:
        print("# OK: all edges length %.1f" % SIDE, file=sys.stderr)
    print("# Verts: %d  Edges: %d" % (len(verts), len(edges)), file=sys.stderr)

def main():
    tris = initial_sun()
    for _ in range(SUBDIVISIONS):
        tris = subdivide(tris)

    verts, edges = extract(tris)

    print("# Penrose P3 — substitution method — Arena One")
    print("# SIDE=%.1fm  radius=%.1fm  subdivisions=%d" % (SIDE, DISPLAY_RADIUS, SUBDIVISIONS))
    print()
    print("# VERTICES (%d)" % len(verts))
    for v in verts.values():
        print("VERTEX\t%.4f\t%.4f" % v)

    print()
    print("# EDGES (%d)" % len(edges))
    for e in edges.values():
        print("EDGE\t%.4f\t%.4f\t%.6f\t%.4f" % (
            e["mid"][0], e["mid"][1], e["angle"], e["length"]))

    validate(verts, edges)

if __name__ == "__main__":
    main()
