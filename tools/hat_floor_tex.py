#!/usr/bin/env python3
"""Rasterize hat_01.svg cluster polygons to a PNG texture for the bowl floor.

Output: scenes/arena/hat_floor.png
UV mapping (for GDScript):
  u = (world_x / 0.03 + 8970) / 17940
  v = (world_z / 0.03 + 6357) / 12714
"""

import re, struct, zlib

SVG      = "hat_01.svg"
OUT      = "scenes/arena/hat_floor.png"
SVG_W    = 17940.0
SVG_H    = 12714.0
IMG_W    = 4096
IMG_H    = int(SVG_H / SVG_W * IMG_W)   # 2903

BG       = (68,  70,  82)    # background / uncovered
COLORS   = [
    (148, 143, 168),          # bucket 0: warm/purple-grey
    (118, 138, 142),          # bucket 1: cool/green-grey
    (122, 135, 172),          # bucket 2: blue-grey
]


def color_bucket(style):
    m = re.search(r'fill:rgb\(([\d.]+)%,([\d.]+)%,([\d.]+)%\)', style)
    if not m:
        return -1
    r, g, b = float(m[1]), float(m[2]), float(m[3])
    if min(r, g, b) > 85.0:
        return -1
    if r >= g and r >= b:
        return 0
    if g >= r and g >= b:
        return 1
    return 2


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


def main():
    src = open(SVG).read()
    entries = re.findall(r'<path\s+style="([^"]+)"[^>]+d="([^"]+)"', src)

    buf = bytearray(bytes(BG) * IMG_W * IMG_H)

    drawn = 0
    for style, d in entries:
        bucket = color_bucket(style)
        if bucket < 0:
            continue

        pts_svg = re.findall(r'[ML]\s+([\d.]+)\s+([\d.]+)', d)
        if len(pts_svg) < 5:
            continue

        coords = [(float(x), float(y)) for x, y in pts_svg]
        # drop closing duplicate
        if len(coords) > 1 and abs(coords[-1][0] - coords[0][0]) < 0.1 \
                            and abs(coords[-1][1] - coords[0][1]) < 0.1:
            coords = coords[:-1]

        pts_img = [to_img(sx, sy) for sx, sy in coords]
        fill_polygon(buf, pts_img, COLORS[bucket])
        drawn += 1

    print(f"Rasterized {drawn} clusters → {OUT} ({IMG_W}×{IMG_H})")
    write_png(OUT, buf, IMG_W, IMG_H)


if __name__ == "__main__":
    main()
