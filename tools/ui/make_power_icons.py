"""Draws the four war-power icons inside the painted round frame of the resource icons.

    python make_power_icons.py <source icons.png> <out dir>
"""
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

SRC, OUT = sys.argv[1], sys.argv[2]
os.makedirs(OUT, exist_ok=True)
S = 256

# the first painted icon gives the frame; its middle is replaced by our own picture
src = Image.open(SRC).convert("RGBA")
a = np.array(src)[:, :, 3] > 128
cols = a.any(0)
x0 = int(np.argmax(cols))
x1 = x0 + int(np.argmax(~cols[x0:]))
rows = a[:, x0:x1].any(1)
y0 = int(np.argmax(rows))
y1 = len(rows) - int(np.argmax(rows[::-1]))
frame = src.crop((x0, y0, x1, y1))
side = max(frame.size)
sq = Image.new("RGBA", (side, side))
sq.paste(frame, ((side - frame.size[0]) // 2, (side - frame.size[1]) // 2))
frame = sq.resize((S, S), Image.LANCZOS)
INNER = 0.345 * S


def base(c1, c2):
    """Frame with a fresh radial-gradient disc in the middle."""
    img = frame.copy()
    yy, xx = np.mgrid[0:S, 0:S]
    d = np.hypot(xx - S / 2, yy - S / 2)
    t = np.clip(d / INNER, 0, 1)[..., None]
    col = (np.array(c1) * (1 - t) + np.array(c2) * t)
    disc = np.dstack([col, np.where(d < INNER, 255, 0)]).astype(np.uint8)
    disc_im = Image.fromarray(disc, "RGBA").filter(ImageFilter.GaussianBlur(0.6))
    img.alpha_composite(disc_im)
    return img


def outline_poly(draw, pts, fill, line=(40, 20, 5, 255), w=5):
    draw.polygon(pts, fill=fill)
    draw.line(pts + [pts[0]], fill=line, width=w, joint="curve")


def P(x, y):
    return (S / 2 + x * INNER, S / 2 + y * INNER)


def arrows():
    img = base((70, 40, 20), (25, 15, 10))
    d = ImageDraw.Draw(img)
    for k, (ox, oy) in enumerate(((-0.45, -0.1), (0.0, -0.25), (0.42, -0.05))):
        ang = math.radians(115)
        dx, dy = math.cos(ang), math.sin(ang)
        tip = P(ox + dx * 0.55, oy + dy * 0.55 + 0.25)
        tail = P(ox - dx * 0.55, oy - dy * 0.55 + 0.25)
        d.line([tail, tip], fill=(40, 20, 5, 255), width=11)
        d.line([tail, tip], fill=(222, 190, 120, 255), width=6)
        nx, ny = -dy, dx
        h = INNER * 0.17
        tx, ty = tip
        outline_poly(d, [(tx + dx * h, ty + dy * h), (tx + nx * h * 0.55, ty + ny * h * 0.55), (tx - nx * h * 0.55, ty - ny * h * 0.55)],
                     (205, 210, 220, 255), w=3)
        bx, by = tail
        for s in (-1, 1):
            d.line([(bx, by), (bx - dx * h * 0.9 + nx * s * h * 0.5, by - dy * h * 0.9 + ny * s * h * 0.5)], fill=(180, 40, 30, 255), width=6)
    return img


def fire():
    img = base((120, 45, 10), (40, 12, 5))
    d = ImageDraw.Draw(img)

    def flame(scale, col, dy=0.0):
        pts = []
        for i in range(60):
            t = i / 59 * 2 * math.pi
            r = 0.5 + 0.12 * math.sin(5 * t)
            x = math.sin(t) * r * 0.75 * scale
            y = -math.cos(t) * r * scale
            if y < 0:
                y *= 1.0 + 0.9 * (1 - abs(math.sin(t)))   # pointed top
            pts.append(P(x, y + 0.2 + dy))
        outline_poly(d, pts, col, w=4)
    flame(1.25, (230, 80, 20, 255))
    flame(0.85, (250, 160, 30, 255), 0.08)
    flame(0.45, (255, 235, 140, 255), 0.18)
    return img


def lightning():
    img = base((40, 60, 120), (10, 15, 40))
    d = ImageDraw.Draw(img)
    pts = [P(0.15, -0.85), P(-0.38, 0.08), P(-0.02, 0.08), P(-0.22, 0.85), P(0.42, -0.18), P(0.06, -0.18), P(0.3, -0.85)]
    glow = Image.new("RGBA", (S, S))
    ImageDraw.Draw(glow).polygon(pts, fill=(160, 210, 255, 255))
    img.alpha_composite(glow.filter(ImageFilter.GaussianBlur(9)))
    d = ImageDraw.Draw(img)
    outline_poly(d, pts, (245, 250, 255, 255), line=(30, 50, 110, 255), w=5)
    return img


def simorgh():
    img = base((30, 110, 115), (10, 40, 50))
    d = ImageDraw.Draw(img)
    gold = (240, 190, 70, 255)
    for s in (-1, 1):
        wing = [P(0.0, -0.05), P(0.3 * s, -0.45), P(0.62 * s, -0.62), P(0.9 * s, -0.5), P(0.72 * s, -0.36),
                P(0.86 * s, -0.22), P(0.62 * s, -0.14), P(0.7 * s, 0.0), P(0.4 * s, 0.02), P(0.12 * s, 0.12)]
        outline_poly(d, wing, gold, w=4)
    tail = [P(-0.1, 0.1), P(-0.42, 0.78), P(-0.12, 0.62), P(0.0, 0.88), P(0.12, 0.62), P(0.42, 0.78), P(0.1, 0.1)]
    outline_poly(d, tail, (225, 120, 40, 255), w=4)
    body = [P(-0.12, -0.1), P(0.0, -0.38), P(0.12, -0.1), P(0.08, 0.25), P(-0.08, 0.25)]
    outline_poly(d, body, (250, 215, 110, 255), w=4)
    head = [P(-0.07, -0.36), P(0.0, -0.55), P(0.07, -0.36)]
    outline_poly(d, head, (250, 215, 110, 255), w=3)
    d.polygon([P(0.0, -0.62), P(-0.05, -0.52), P(0.05, -0.52)], fill=(200, 60, 40, 255))
    return img


for name, fn in (("arrows", arrows), ("fire", fire), ("lightning", lightning), ("simorgh", simorgh)):
    fn().resize((128, 128), Image.LANCZOS).save(os.path.join(OUT, "power_%s.png" % name))
print("power icons written")
