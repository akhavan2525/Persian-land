"""Turns the Persian UI paintings (made with ChatGPT) into game-ready textures.

    python make_ui.py <source dir> <assets dir>

Sources: topbar.png, panel.png, button.png, icons.png (5 round icons in a row), menu_bg.png.
Writes assets/ui/*.png, assets/ui/icons/*.png, assets/images/menu_bg.jpg and prints the
slot positions of the top bar for hud.gd.
"""
import json
import os
import sys

import numpy as np
from PIL import Image
from scipy import ndimage as nd

SRC, OUT = sys.argv[1], sys.argv[2]
os.makedirs(os.path.join(OUT, "ui", "icons"), exist_ok=True)


def load(name):
    return np.array(Image.open(os.path.join(SRC, name)).convert("RGBA")).astype(np.float32)


def clean_alpha(a):
    """Hard edge at half alpha, softened by a pixel: removes the coloured fringe the
    generator leaves around cut-outs."""
    m = a[:, :, 3] > 128
    m = nd.binary_opening(m, iterations=1)
    a = a.copy()
    a[:, :, 3] = np.clip(nd.gaussian_filter(m.astype(np.float32), 0.8) * 255, 0, 255)
    return a


def cut_background(a, thresh=60.0):
    """For art painted on a smooth glow: everything smooth that touches the border is background."""
    g = np.zeros(a.shape[:2])
    for c in range(3):
        s = nd.gaussian_filter(a[:, :, c], 1.0)
        g += np.hypot(nd.sobel(s, 1), nd.sobel(s, 0))
    smooth = (g < thresh) | (a[:, :, 3] < 10)
    lab, _ = nd.label(smooth)
    edge = set(np.unique(np.concatenate([lab[0], lab[-1], lab[:, 0], lab[:, -1]]))) - {0}
    bg = np.isin(lab, list(edge)) | (a[:, :, 3] < 10)
    bg = nd.binary_closing(bg, iterations=2, border_value=1)
    fg = nd.binary_opening(nd.binary_fill_holes(~bg), iterations=2)
    a = a.copy()
    a[:, :, 3] = np.minimum(nd.gaussian_filter(fg.astype(np.float32), 1.0) * 255, a[:, :, 3])
    return a


def crop(a):
    ys, xs = np.where(a[:, :, 3] > 8)
    return a[ys.min():ys.max() + 1, xs.min():xs.max() + 1]


def save(a, path, size=None):
    im = Image.fromarray(np.clip(a, 0, 255).astype(np.uint8), "RGBA")
    if size:
        im = im.resize(size, Image.LANCZOS)
    im.save(path, optimize=True)
    return im


def stretch_cols(a, x0, x1, k):
    """Widens columns x0..x1 by k (the plain middle of a slot)."""
    mid = Image.fromarray(a[:, x0:x1].astype(np.uint8), "RGBA")
    mid = mid.resize((int((x1 - x0) * k), a.shape[0]), Image.BICUBIC)
    return np.concatenate([a[:, :x0], np.array(mid).astype(np.float32), a[:, x1:]], axis=1)


# ---------------- top bar: widen the four number slots ----------------
top = clean_alpha(load("topbar.png"))
lum = top[340, :, :3].mean(1)
dark = (lum < 55) & (top[340, :, 3] > 200)
slots, s = [], None
for x, d in enumerate(dark):
    if d and s is None:
        s = x
    if not d and s is not None:
        if x - s > 40:
            slots.append([s, x])
        s = None
assert len(slots) == 4, slots
K = 2.0
for i in reversed(range(4)):
    x0, x1 = slots[i][0] + 40, slots[i][1] - 40
    top = stretch_cols(top, x0, x1, K)
    grow = int((x1 - x0) * K) - (x1 - x0)
    slots[i][1] += grow
    for j in range(i + 1, 4):
        slots[j][0] += grow
        slots[j][1] += grow
ys, xs = np.where(top[:, :, 3] > 8)
y0, y1, xa, xb = ys.min(), ys.max() + 1, xs.min(), xs.max() + 1
top = top[y0:y1, xa:xb]
H, W = top.shape[:2]
out_h = 150
out_w = int(W * out_h / H)
save(top, os.path.join(OUT, "ui", "topbar.png"), (out_w, out_h))
layout = {"size": [out_w, out_h], "slots": [[(a - xa) / W, (b - xa) / W] for a, b in slots],
          "slot_y": [(271 - y0) / H, (435 - y0) / H], "center": 0.5}
print(json.dumps(layout))

# ---------------- panel frame ----------------
panel = crop(clean_alpha(load("panel.png")))
save(panel, os.path.join(OUT, "ui", "panel.png"), (240, 240))

# ---------------- button ----------------
btn = crop(cut_background(load("button.png")))
save(btn, os.path.join(OUT, "ui", "button.png"), (420, int(420 * btn.shape[0] / btn.shape[1])))

# ---------------- resource icons ----------------
ic = clean_alpha(load("icons.png"))
cols = (ic[:, :, 3] > 128).any(0)
runs, s = [], None
for x, c in enumerate(cols):
    if c and s is None:
        s = x
    if not c and s is not None:
        runs.append((s, x))
        s = None
if s is not None:
    runs.append((s, len(cols)))
names = ["wood", "stone", "food", "gold", "pop"]
assert len(runs) == 5, runs
for n, (a, b) in zip(names, runs):
    one = crop(ic[:, a:b])
    h, w = one.shape[:2]
    side = max(h, w)
    sq = np.zeros((side, side, 4), np.float32)
    sq[(side - h) // 2:(side - h) // 2 + h, (side - w) // 2:(side - w) // 2 + w] = one
    save(sq, os.path.join(OUT, "ui", "icons", n + ".png"), (96, 96))

# ---------------- menu background ----------------
bg = Image.open(os.path.join(SRC, "menu_bg.png")).convert("RGB")
bg.save(os.path.join(OUT, "images", "menu_bg.jpg"), quality=86)
print("done")
