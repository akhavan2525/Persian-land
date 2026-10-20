"""Makes the tileable ground textures (grass, dirt, rock, sand) with numpy.

    python make_ground.py <output_dir>

Every texture wraps seamlessly: noise is filtered in frequency space and scattered
features wrap around the edges. Each material gets an albedo PNG (height in alpha,
used for height-blending in the terrain shader) and a normal-map PNG.
"""
import os
import sys

import numpy as np
from PIL import Image

OUT = sys.argv[1] if len(sys.argv) > 1 else "out"
S = 1024
rng = np.random.default_rng(11)


def noise(scale_px, beta=2.0, seed=None):
    """Tileable fractal noise; features around scale_px pixels and smaller."""
    r = np.random.default_rng(seed) if seed is not None else rng
    w = r.standard_normal((S, S))
    f = np.fft.fftfreq(S)
    fx, fy = np.meshgrid(f, f)
    k = np.sqrt(fx * fx + fy * fy)
    k0 = 1.0 / scale_px
    filt = 1.0 / np.power(np.maximum(k, k0), beta / 2.0 + 0.5)
    filt[0, 0] = 0
    n = np.real(np.fft.ifft2(np.fft.fft2(w) * filt))
    n -= n.min()
    n /= n.max()
    return n


def band(scale_px, width=0.5, seed=None):
    """Tileable noise limited to one feature size (no large blobs)."""
    r = np.random.default_rng(seed) if seed is not None else rng
    w = r.standard_normal((S, S))
    f = np.fft.fftfreq(S)
    fx, fy = np.meshgrid(f, f)
    k = np.sqrt(fx * fx + fy * fy)
    k0 = 1.0 / scale_px
    filt = np.exp(-((np.log(np.maximum(k, 1e-6)) - np.log(k0)) ** 2) / (2 * width * width))
    n = np.real(np.fft.ifft2(np.fft.fft2(w) * filt))
    n -= n.min()
    n /= n.max()
    return n


def stamp_discs(count, rmin, rmax, seed):
    """Wrapped round pebbles: returns height field and an id field for colour variation."""
    r = np.random.default_rng(seed)
    h = np.zeros((S, S))
    tint = np.zeros((S, S))
    for _ in range(count):
        cx, cy = r.uniform(0, S, 2)
        rad = r.uniform(rmin, rmax)
        ex = r.uniform(0.7, 1.3)
        t = r.uniform(-1, 1)
        x0, x1 = int(cx - rad * 1.4) - 1, int(cx + rad * 1.4) + 2
        y0, y1 = int(cy - rad * 1.4) - 1, int(cy + rad * 1.4) + 2
        ys = np.arange(y0, y1)
        xs = np.arange(x0, x1)
        X, Y = np.meshgrid(xs, ys)
        d = np.sqrt(((X - cx) / ex) ** 2 + ((Y - cy) * ex) ** 2) / rad
        bump = np.clip(1 - d * d, 0, None) ** 0.6
        yi, xi = np.ix_(ys % S, xs % S)
        cur = h[yi, xi]
        m = bump > cur
        h[yi, xi] = np.where(m, bump, cur)
        tt = tint[yi, xi]
        tint[yi, xi] = np.where(m & (bump > 0), t, tt)
    return h, tint


def cells(n_points, seed):
    """Wrapped Voronoi: distance to the nearest edge (for rock cracks)."""
    r = np.random.default_rng(seed)
    pts = r.uniform(0, S, (n_points, 2))
    ys, xs = np.mgrid[0:S, 0:S].astype(np.float32)
    d1 = np.full((S, S), 1e9, np.float32)
    d2 = np.full((S, S), 1e9, np.float32)
    for px, py in pts:
        dx = np.abs(xs - px)
        dx = np.minimum(dx, S - dx)
        dy = np.abs(ys - py)
        dy = np.minimum(dy, S - dy)
        d = np.sqrt(dx * dx + dy * dy)
        closer = d < d1
        d2 = np.where(closer, d1, np.minimum(d2, d))
        d1 = np.where(closer, d, d1)
    return d2 - d1


def ramp(t, stops):
    """t in 0..1 -> colour from [(pos, (r,g,b)), ...] (sRGB 0..255)."""
    t = np.clip(t, 0, 1)
    pos = np.array([p for p, _ in stops])
    cols = np.array([c for _, c in stops], dtype=np.float64)
    out = np.zeros(t.shape + (3,))
    for ch in range(3):
        out[..., ch] = np.interp(t, pos, cols[:, ch])
    return out


def normal_map(h, strength):
    dx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) * strength
    dy = (np.roll(h, -1, 0) - np.roll(h, 1, 0)) * strength
    n = np.dstack([-dx, dy, np.ones_like(h)])
    n /= np.linalg.norm(n, axis=2, keepdims=True)
    return ((n * 0.5 + 0.5) * 255).astype(np.uint8)


def save(name, col, h, strength):
    os.makedirs(OUT, exist_ok=True)
    a = (np.clip(h, 0, 1) * 255).astype(np.uint8)
    rgba = np.dstack([np.clip(col, 0, 255).astype(np.uint8), a])
    Image.fromarray(rgba, "RGBA").save(os.path.join(OUT, name + "_albedo.png"))
    Image.fromarray(normal_map(h, strength), "RGB").save(os.path.join(OUT, name + "_normal.png"))
    print("saved", name)


def grass():
    big = noise(300, seed=1)
    mid = noise(60, seed=2)
    tuft = band(6, 0.45, seed=3)
    fine = band(2.2, 0.4, seed=4)
    # height: little tufts of blades
    h = tuft * 0.6 + fine * 0.4
    h = np.clip((h - 0.25) * 1.6, 0, 1)
    t = mid * 0.55 + big * 0.25 + h * 0.35
    col = ramp(t, [(0.0, (58, 78, 30)), (0.35, (84, 108, 40)), (0.6, (110, 132, 52)), (0.85, (148, 152, 70)), (1.0, (170, 160, 88))])
    # dry yellow patches and small dark gaps between blades
    dry = np.clip((noise(120, seed=5) - 0.58) * 4, 0, 1)
    col = col * (1 - dry[..., None] * 0.5) + np.array([168, 150, 84]) * dry[..., None] * 0.5
    col *= (0.62 + 0.38 * h)[..., None]
    # a few soil specks
    soil = np.clip((band(4, 0.5, seed=6) - 0.8) * 8, 0, 1) * np.clip((mid - 0.5) * 3, 0, 1)
    col = col * (1 - soil[..., None]) + np.array([96, 74, 48]) * soil[..., None]
    save("grass", col, h * 0.8 + mid * 0.2, 2.5)


def dirt():
    base = noise(200, seed=11)
    mid = noise(40, seed=12)
    fine = band(2.5, 0.5, seed=13)
    peb, tint = stamp_discs(900, 3, 9, 21)
    small, stint = stamp_discs(4000, 1.2, 3, 22)
    t = base * 0.4 + mid * 0.4 + fine * 0.2
    col = ramp(t, [(0.0, (92, 70, 48)), (0.5, (128, 100, 70)), (1.0, (156, 128, 92))])
    col *= (0.85 + fine * 0.25)[..., None]
    pc = ramp(tint * 0.5 + 0.5, [(0.0, (98, 90, 80)), (0.5, (124, 112, 96)), (1.0, (140, 122, 98))])
    m = np.clip(peb * 3, 0, 1)[..., None]
    col = col * (1 - m) + pc * (0.75 + 0.3 * peb[..., None]) * m
    ms = np.clip(small * 3, 0, 1)[..., None] * 0.7
    col = col * (1 - ms) + pc * 0.9 * ms
    # tracks: soft darker ruts
    h = np.maximum(peb, small * 0.6) * 0.7 + mid * 0.2 + fine * 0.1
    save("dirt", col, h, 4.0)


def rock():
    cr = cells(110, 31)
    wx = (noise(90, seed=36) - 0.5) * 40
    wy = (noise(90, seed=37) - 0.5) * 40
    ys, xs = np.mgrid[0:S, 0:S]
    cr = cr[(ys + wy.astype(int)) % S, (xs + wx.astype(int)) % S]
    big = noise(250, seed=32)
    mid = noise(50, seed=33)
    fine = band(3, 0.6, seed=34)
    crack = np.clip(cr / 6.0, 0, 1)
    t = big * 0.35 + mid * 0.45 + fine * 0.2
    col = ramp(t, [(0.0, (88, 84, 78)), (0.45, (122, 116, 106)), (0.8, (152, 146, 134)), (1.0, (176, 170, 158))])
    col *= (0.45 + 0.55 * crack ** 0.5)[..., None]
    # lichen
    lich = np.clip((noise(80, seed=35) - 0.62) * 5, 0, 1) * (fine > 0.55)
    col = col * (1 - lich[..., None] * 0.6) + np.array([128, 132, 80]) * lich[..., None] * 0.6
    h = crack ** 0.5 * 0.55 + mid * 0.3 + fine * 0.15
    save("rock", col, h, 5.0)


def sand():
    big = noise(260, seed=41)
    fine = band(1.8, 0.5, seed=42)
    yy = np.mgrid[0:S, 0:S][0] / S
    xx = np.mgrid[0:S, 0:S][1] / S
    warp = noise(150, seed=43)
    ripple = 0.5 + 0.5 * np.sin((yy * 24 + xx * 6 + warp * 3.0) * 2 * np.pi)
    t = big * 0.5 + ripple * 0.25 + fine * 0.25
    col = ramp(t, [(0.0, (172, 152, 112)), (0.5, (200, 180, 136)), (1.0, (222, 204, 160))])
    h = ripple * 0.5 + fine * 0.3 + big * 0.2
    save("sand", col, h, 2.0)


if __name__ == "__main__":
    grass()
    dirt()
    rock()
    sand()
