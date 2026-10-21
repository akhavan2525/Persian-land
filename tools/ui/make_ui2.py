"""Cuts the second set of painted UI pieces into game textures.

    python make_ui2.py <ui-src/v2 dir> <rendered icons dir> <assets/ui dir>

- round building icons from the sheet (barracks, woodcutter, quarry, house, farm)
- the same gold frame around rendered models for the tower, wall and gate
- the bottom bar, the arched build tile, the side button and the minimap frame
"""
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

SRC, REN, OUT = sys.argv[1], sys.argv[2], sys.argv[3]
os.makedirs(os.path.join(OUT, "icons"), exist_ok=True)


def trim(im, pad=4):
    a = np.array(im)[:, :, 3] > 24
    ys, xs = np.nonzero(a)
    return im.crop((max(0, xs.min() - pad), max(0, ys.min() - pad), min(im.width, xs.max() + pad), min(im.height, ys.max() + pad)))


def disc_mask(size, r, feather=1.5):
    m = Image.new("L", (size, size), 0)
    c = size / 2
    ImageDraw.Draw(m).ellipse((c - r, c - r, c + r, c + r), fill=255)
    return m.filter(ImageFilter.GaussianBlur(feather))


# ---------------- round building icons ----------------
sheet = Image.open(os.path.join(SRC, "ui_sheet.png")).convert("RGBA")
CENTERS = {"granary": 135, "barracks": 347, "woodcutter": 558, "quarry": 768, "house": 980, "pasture": 1190, "farm": 1400}
CY, R_OUT, R_IN = 146, 99, 91
S = 2 * R_OUT + 4
icons = {}
for name, cx in CENTERS.items():
    crop = sheet.crop((cx - S // 2, CY - S // 2, cx + S // 2, CY + S // 2))
    crop.putalpha(disc_mask(S, R_OUT))
    icons[name] = crop
    if name in ("barracks", "woodcutter", "quarry", "house", "farm"):
        crop.resize((128, 128), Image.LANCZOS).save(os.path.join(OUT, "icons", "b_%s.png" % name))

# rendered models inside the same frame: take the quarry's ring, fill the middle with lapis
ring = icons["quarry"].copy()
yy, xx = np.mgrid[0:S, 0:S]
d = np.hypot(xx - S / 2, yy - S / 2)
for name in ("tower", "wall", "gate", "keep"):
    path = os.path.join(REN, name + ".png")
    if not os.path.exists(path):
        continue
    t = np.clip(d / R_IN, 0, 1)[..., None]
    col = np.array([52, 92, 168]) * (1 - t) + np.array([18, 34, 84]) * t
    inner = np.dstack([col, np.full((S, S), 255)]).astype(np.uint8)
    pic = Image.fromarray(inner, "RGBA")
    model = trim(Image.open(path).convert("RGBA"))
    k = (R_IN * 1.55) / max(model.size)
    model = model.resize((max(1, int(model.width * k)), max(1, int(model.height * k))), Image.LANCZOS)
    shadow = Image.new("RGBA", pic.size, (0, 0, 0, 0))
    ox, oy = (S - model.width) // 2, (S - model.height) // 2 + 6
    sh = Image.new("RGBA", model.size, (0, 0, 0, 140))
    sh.putalpha(model.split()[3].point(lambda v: v * 0.55))
    shadow.alpha_composite(sh, (ox + 4, oy + 5))
    pic.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(4)))
    pic.alpha_composite(model, (ox, oy))
    out = ring.copy()
    inner_mask = disc_mask(S, R_IN - 1, 1.0)
    out.paste(pic, (0, 0), inner_mask)
    out.putalpha(disc_mask(S, R_OUT))
    out.resize((128, 128), Image.LANCZOS).save(os.path.join(OUT, "icons", "b_%s.png" % name))

# ---------------- frames ----------------
bar = trim(Image.open(os.path.join(SRC, "bottom_bar.png")).convert("RGBA"))
bar = bar.resize((int(bar.width * 136 / bar.height), 136), Image.LANCZOS)   # drawn at this height
bar.save(os.path.join(OUT, "bottom_bar.png"))
tile = trim(Image.open(os.path.join(SRC, "build_tile.png")).convert("RGBA"))
tile = tile.resize((96, int(tile.height * 96 / tile.width)), Image.LANCZOS)
tile.save(os.path.join(OUT, "build_tile.png"))
side = trim(Image.open(os.path.join(SRC, "side_button.png")).convert("RGBA"))
side = side.resize((210, int(side.height * 210 / side.width)), Image.LANCZOS)
side.save(os.path.join(OUT, "side_button.png"))
mm = trim(Image.open(os.path.join(SRC, "minimap_frame.png")).convert("RGBA"))
mm = mm.resize((512, int(mm.height * 512 / mm.width)), Image.LANCZOS)
mm.save(os.path.join(OUT, "minimap_frame.png"))
for n, im in (("bottom_bar", bar), ("build_tile", tile), ("side_button", side), ("minimap_frame", mm)):
    print(n, im.size)
