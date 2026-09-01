#!/usr/bin/env python3
"""Draws the app icon: the focus brackets and centre dot the guidance uses.

Kept as a script rather than a checked-in binary alone, so the icon can be
re-rendered when the accent colour changes, and so what it is made of is
readable. Writes a 1024x1024 opaque RGB PNG — the App Store rejects icons
with an alpha channel.

Run from the repository root:

    python3 scripts/make-app-icon.py
"""
import math, struct, zlib

S = 1024
# App palette: the same accent green the Ready state uses.
ACCENT = (156, 240, 140)
TOP = (0x18, 0x1B, 0x20)
BOTTOM = (0x07, 0x08, 0x0A)

def seg_dist(px, py, ax, ay, bx, by):
    vx, vy = bx - ax, by - ay
    wx, wy = px - ax, py - ay
    L2 = vx * vx + vy * vy
    t = 0.0 if L2 == 0 else max(0.0, min(1.0, (wx * vx + wy * vy) / L2))
    dx, dy = wx - t * vx, wy - t * vy
    return math.sqrt(dx * dx + dy * dy)

INSET = 236.0
ARM = 214.0
HALF = 19.0          # half stroke width
DOT = 92.0

segments = []
for sx in (0, 1):
    for sy in (0, 1):
        cx = INSET if sx == 0 else S - INSET
        cy = INSET if sy == 0 else S - INSET
        hx = (ARM if sx == 0 else -ARM)
        vy = (ARM if sy == 0 else -ARM)
        segments.append((cx, cy, cx + hx, cy))
        segments.append((cx, cy, cx, cy + vy))

# Bounding boxes let most pixels skip the distance maths entirely.
boxes = [(min(a, c) - HALF - 2, min(b, d) - HALF - 2,
          max(a, c) + HALF + 2, max(b, d) + HALF + 2)
         for (a, b, c, d) in segments]

cxm = cym = S / 2.0
rows = []
for y in range(S):
    py = y + 0.5
    t = y / (S - 1)
    br = TOP[0] + (BOTTOM[0] - TOP[0]) * t
    bg = TOP[1] + (BOTTOM[1] - TOP[1]) * t
    bb = TOP[2] + (BOTTOM[2] - TOP[2]) * t
    row = bytearray()
    row.append(0)  # PNG filter type: none
    for x in range(S):
        px = x + 0.5
        cover = 0.0

        d = math.hypot(px - cxm, py - cym) - DOT
        if d < 1.0:
            cover = min(1.0, max(0.0, 0.5 - d))

        if cover < 1.0:
            for (a, b, c, dd), (x0, y0, x1, y1) in zip(segments, boxes):
                if px < x0 or px > x1 or py < y0 or py > y1:
                    continue
                sd = seg_dist(px, py, a, b, c, dd) - HALF
                if sd < 1.0:
                    cover = max(cover, min(1.0, max(0.0, 0.5 - sd)))
                    if cover >= 1.0:
                        break

        if cover <= 0.0:
            row += bytes((int(br + 0.5), int(bg + 0.5), int(bb + 0.5)))
        else:
            row += bytes((
                int(br + (ACCENT[0] - br) * cover + 0.5),
                int(bg + (ACCENT[1] - bg) * cover + 0.5),
                int(bb + (ACCENT[2] - bb) * cover + 0.5),
            ))
    rows.append(bytes(row))

raw = b"".join(rows)

def chunk(tag, data):
    return (struct.pack(">I", len(data)) + tag + data
            + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF))

png = b"\x89PNG\r\n\x1a\n"
png += chunk(b"IHDR", struct.pack(">IIBBBBB", S, S, 8, 2, 0, 0, 0))  # 8-bit RGB
png += chunk(b"IDAT", zlib.compress(raw, 9))
png += chunk(b"IEND", b"")

out = "CameraApp/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
open(out, "wb").write(png)
print("wrote", out, len(png), "bytes")
