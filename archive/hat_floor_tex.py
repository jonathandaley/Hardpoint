#!/usr/bin/env python3
"""Rasterize hat_01.svg cluster polygons to a PNG texture for the bowl floor.

Output: scenes/arena/hat_floor.png
UV mapping (for GDScript):
  u = (world_x / 0.03 + 8970) / 17940
  v = (world_z / 0.03 + 6357) / 12714
"""

import re, struct, zlib

SVG   = "tools/hat_01.svg"
OUT   = "scenes/arena/hat_floor.png"
SVG_W = 17940.0
SVG_H = 12714.0
IMG_W = 1024
IMG_H = int(SVG_H / SVG_W * IMG_W)

BG     = (68,  70,  82)
COLORS = [
    (148, 143, 168),   # warm/purple-grey
    (118, 138, 142),   # cool/green-grey
    (122, 135, 172),   # blue-grey
    (138, 152, 146),   # sage-grey
    (108, 125, 148),   # steel-grey
]

SNAP = 0.5   # SVG units; shared edges snap within this tolerance


def color_bucket(style):
    m = re.search(r'fill:rgb\(([\d.]+)%,([\d.]+)%,([\d.]+)%\)', style)
    if not m:
        return -1
    r, g, b = float(m[1]), float(m[2]), float(m[3])
    if min(r, g, b) > 85.0:
        return -1
    return -1 if False else 0   # placeholder; overridden by graph coloring


def is_bg(style):
    m = re.search(r'fill:rgb\(([\d.]+)%,([\d.]+)%,([\d.]+)%\)', style)
    if not m:
        return True
    r, g, b = float(m[1]), float(m[2]), float(m[3])
    return min(r, g, b) > 85.0


def to_img(sx, sy):
    return sx * IMG_W / SVG_W, sy * IMG_H / SVG_H


def fill_polygon(buf, pts, color):
    r, g, b = color
    fill = bytes([r, g, b])
    y_min = max(0, int(min(p[1] for p in pts)))
    y_max = min(IMG_H - 1, int(max(p[1] for p in pts)) + 1)
    n = len(pts)
    for y in range(y_min, y_max + 1):
        yf = y + 0.5
        xs = []
        for i in range(n):
            x0, y0 = pts[i]
            x1, y1 = pts[(i + 1) % n]
            if (y0 <= yf < y1) or (y1 <= yf < y0):
                t = (yf - y0) / (y1 - y0)
                xs.append(x0 + t * (x1 - x0))
        xs.sort()
        row = y * IMG_W * 3
        for i in range(0, len(xs) - 1, 2):
            x0 = max(0, int(xs[i]))
            x1 = min(IMG_W - 1, int(xs[i + 1]) + 1)
            if x0 >= x1:
                continue
            buf[row + x0 * 3 : row + x1 * 3] = fill * (x1 - x0)


def write_png(path, buf, w, h):
    def chunk(tag, data):
        crc = zlib.crc32(tag + data) & 0xffffffff
        return struct.pack('>I', len(data)) + tag + data + struct.pack('>I', crc)
    raw = bytearray()
    for y in range(h):
        raw.append(0)
        raw += buf[y * w * 3 : (y + 1) * w * 3]
    compressed = zlib.compress(bytes(raw), 6)
    with open(path, 'wb') as f:
        f.write(b'\x89PNG\r\n\x1a\n')
        f.write(chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 2, 0, 0, 0)))
        f.write(chunk(b'IDAT', compressed))
        f.write(chunk(b'IEND', b''))


def snap_key(x, y):
    return (round(x / SNAP), round(y / SNAP))


def build_adjacency(polys):
    # Map snapped edge → list of polygon indices
    edge_map = {}
    for idx, coords in enumerate(polys):
        n = len(coords)
        for i in range(n):
            a = snap_key(*coords[i])
            b = snap_key(*coords[(i + 1) % n])
            key = (min(a, b), max(a, b))
            edge_map.setdefault(key, []).append(idx)

    adj = [set() for _ in range(len(polys))]
    for clusters in edge_map.values():
        if len(clusters) == 2:
            a, b = clusters[0], clusters[1]
            adj[a].add(b)
            adj[b].add(a)
    return adj


def greedy_color(adj, n_polys):
    colors = [-1] * n_polys
    # Order by descending degree for better coloring
    order = sorted(range(n_polys), key=lambda i: len(adj[i]), reverse=True)
    max_color = 0
    for i in order:
        used = {colors[j] for j in adj[i] if colors[j] >= 0}
        c = 0
        while c in used:
            c += 1
        colors[i] = c
        max_color = max(max_color, c)
    return colors, max_color


def main():
    src = open(SVG).read()
    entries = re.findall(r'<path\s+style="([^"]+)"[^>]+d="([^"]+)"', src)

    polys = []
    for style, d in entries:
        if is_bg(style):
            continue
        pts = re.findall(r'[ML]\s+([\d.]+)\s+([\d.]+)', d)
        if len(pts) < 5:
            continue
        coords = [(float(x), float(y)) for x, y in pts]
        if len(coords) > 1 and abs(coords[-1][0] - coords[0][0]) < 0.1 \
                            and abs(coords[-1][1] - coords[0][1]) < 0.1:
            coords = coords[:-1]
        polys.append(coords)

    adj = build_adjacency(polys)
    graph_colors, max_color = greedy_color(adj, len(polys))
    n_colors_used = max_color + 1
    print(f"Graph coloring: {len(polys)} clusters, {n_colors_used} colors used")
    if n_colors_used > len(COLORS):
        print(f"WARNING: need {n_colors_used} colors but only {len(COLORS)} defined")

    buf = bytearray(bytes(BG) * IMG_W * IMG_H)
    for idx, coords in enumerate(polys):
        c = graph_colors[idx] % len(COLORS)
        pts_img = [to_img(sx, sy) for sx, sy in coords]
        fill_polygon(buf, pts_img, COLORS[c])

    print(f"Rasterized {len(polys)} clusters → {OUT} ({IMG_W}×{IMG_H})")
    write_png(OUT, buf, IMG_W, IMG_H)


if __name__ == "__main__":
    main()
