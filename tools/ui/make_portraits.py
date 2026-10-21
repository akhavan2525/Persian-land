"""Trims the painted unit portraits to their round frame and saves 256px copies.

    python make_portraits.py <source dir> <out dir>
"""
import glob
import os
import sys

import numpy as np
from PIL import Image

SRC, OUT = sys.argv[1], sys.argv[2]
os.makedirs(OUT, exist_ok=True)
for f in sorted(glob.glob(os.path.join(SRC, "*.png"))):
    im = Image.open(f).convert("RGBA")
    a = np.array(im)[:, :, 3] > 40
    ys, xs = np.nonzero(a)
    x0, x1, y0, y1 = xs.min(), xs.max(), ys.min(), ys.max()
    side = max(x1 - x0, y1 - y0) + 8
    cx, cy = (x0 + x1) // 2, (y0 + y1) // 2
    sq = Image.new("RGBA", (side, side))
    sq.paste(im.crop((cx - side // 2, cy - side // 2, cx + side // 2, cy + side // 2)), (0, 0))
    sq.resize((256, 256), Image.LANCZOS).save(os.path.join(OUT, os.path.basename(f)))
    print(os.path.basename(f), "frame", x1 - x0, y1 - y0, "opaque share %.2f" % a.mean())
