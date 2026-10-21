"""Synthesises the game's battle sounds (no samples needed).

    python make_sfx.py <out dir>

Writes 22 kHz mono WAV files: sword clashes, arrows, hits, deaths, building, upgrades,
the war horn and the four war powers.
"""
import os
import sys

import numpy as np
from scipy import signal
from scipy.io import wavfile

SR = 22050
OUT = sys.argv[1]
os.makedirs(OUT, exist_ok=True)
rng = np.random.default_rng(7)


def t(sec):
    return np.arange(int(SR * sec)) / SR


def env(n, attack=0.005, decay=0.2, curve=1.0):
    x = np.arange(n) / SR
    a = np.clip(x / max(attack, 1e-4), 0, 1)
    d = np.exp(-x / max(decay, 1e-4)) ** curve
    return a * d


def noise(sec):
    return rng.standard_normal(int(SR * sec))


def bandpass(x, lo, hi, order=2):
    b, a = signal.butter(order, [lo / (SR / 2), hi / (SR / 2)], "band")
    return signal.lfilter(b, a, x)


def lowpass(x, f, order=2):
    b, a = signal.butter(order, f / (SR / 2), "low")
    return signal.lfilter(b, a, x)


def highpass(x, f, order=2):
    b, a = signal.butter(order, f / (SR / 2), "high")
    return signal.lfilter(b, a, x)


def mix(*parts):
    n = max(len(p) for p in parts)
    out = np.zeros(n)
    for p in parts:
        out[:len(p)] += p
    return out


def at(x, sec, total):
    out = np.zeros(int(SR * total))
    i = int(SR * sec)
    seg = x[:max(0, len(out) - i)]
    out[i:i + len(seg)] += seg
    return out


def reverb(x, amount=0.25, length=0.6):
    ir = noise(length) * env(int(SR * length), 0.001, length / 4)
    ir = lowpass(ir, 4000)
    wet = signal.fftconvolve(x, ir)[:len(x) + int(SR * length)]
    wet /= np.max(np.abs(wet)) + 1e-9
    dry = np.concatenate([x, np.zeros(len(wet) - len(x))])
    return dry + wet * amount * np.max(np.abs(x))


def save(name, x, gain=0.9):
    x = x / (np.max(np.abs(x)) + 1e-9) * gain
    fade = min(len(x), int(SR * 0.01))
    x[-fade:] *= np.linspace(1, 0, fade)
    wavfile.write(os.path.join(OUT, name + ".wav"), SR, (x * 32767).astype(np.int16))


def clang(seed_f, sec=0.6):
    """Metal on metal: a hard click plus a few inharmonic ringing partials."""
    n = int(SR * sec)
    x = t(sec)
    ring = sum(np.sin(2 * np.pi * seed_f * r * x + rng.random() * 6) * w
               for r, w in ((1.0, 1.0), (2.76, 0.6), (5.4, 0.35), (8.9, 0.2)))
    ring *= env(n, 0.001, 0.12)
    click = highpass(noise(0.03), 2500) * env(int(SR * 0.03), 0.0005, 0.008)
    return reverb(mix(ring * 0.6, click), 0.2, 0.4)


def thud(f=90, sec=0.35):
    n = int(SR * sec)
    x = t(sec)
    sweep = np.sin(2 * np.pi * (f + 60 * np.exp(-x * 30)) * x) * env(n, 0.002, 0.08)
    body = lowpass(noise(sec), 600) * env(n, 0.001, 0.05)
    return mix(sweep, body * 0.8)


def whoosh(sec=0.45, lo=600, hi=3000, rise=True):
    n = int(SR * sec)
    x = noise(sec)
    k = np.linspace(0, 1, n)
    shape = np.sin(np.pi * k) ** 2
    # sweep the band by filtering in chunks
    out = np.zeros(n)
    chunks = 12
    for i in range(chunks):
        s, e = i * n // chunks, (i + 1) * n // chunks
        f = lo + (hi - lo) * ((i / chunks) if rise else 1 - i / chunks)
        out[s:e] = bandpass(x, f * 0.7, min(f * 1.4, SR / 2 - 100))[s:e]
    return out * shape


# ---------------- melee ----------------
for i, f in enumerate((520, 610, 700)):
    save("sword_%d" % i, mix(clang(f), at(thud(120, 0.2) * 0.5, 0.0, 0.6)))
for i in range(3):
    save("hit_%d" % i, mix(thud(70 + i * 15, 0.3), highpass(noise(0.08), 1500) * env(int(SR * 0.08), 0.001, 0.02) * 0.4))

# ---------------- arrows ----------------
for i in range(2):
    twang = np.sin(2 * np.pi * (180 + i * 30) * t(0.25)) * env(int(SR * 0.25), 0.001, 0.05)
    save("bow_%d" % i, mix(twang * 0.7, at(whoosh(0.35, 1200, 4000) * 0.6, 0.02, 0.4)))
save("arrow_hit", mix(thud(140, 0.15), highpass(noise(0.05), 2000) * env(int(SR * 0.05), 0.0005, 0.01) * 0.5))

# ---------------- deaths ----------------
for i in range(3):
    n = int(SR * 0.7)
    x = t(0.7)
    f0 = 150 - i * 20
    groan = signal.sawtooth(2 * np.pi * (f0 * (1 - 0.35 * x / 0.7)) * x) * env(n, 0.02, 0.25)
    groan = bandpass(groan, 300, 1800) + bandpass(groan, 600, 900) * 0.6
    save("death_%d" % i, mix(groan * 0.6, at(thud(60, 0.4), 0.25, 0.7)))

# ---------------- building ----------------
hammer = mix(*[at(mix(clang(900 + k * 40, 0.25) * 0.5, thud(200, 0.15)), k * 0.28, 1.0) for k in range(3)])
save("build", hammer)
rumble = lowpass(noise(1.4), 300) * env(int(SR * 1.4), 0.05, 0.6)
save("collapse", mix(rumble, at(thud(50, 0.6), 0.0, 1.4), at(highpass(noise(0.8), 1500) * env(int(SR * 0.8), 0.01, 0.2) * 0.3, 0.1, 1.4)))

# ---------------- upgrade chime: a rising Persian-sounding (Shur-like) phrase ----------------
notes = [293.7, 311.1, 349.2, 392.0, 440.0, 587.3]
chime = np.zeros(int(SR * 1.8))
for k, f in enumerate(notes):
    x = t(0.9)
    tone = (np.sin(2 * np.pi * f * x) + 0.4 * np.sin(2 * np.pi * 2 * f * x) + 0.2 * np.sin(2 * np.pi * 3.01 * f * x))
    tone *= env(len(x), 0.004, 0.35)
    chime += at(tone, k * 0.13, 1.8)
save("upgrade", reverb(chime, 0.35, 1.0))

# ---------------- war horn (karnay) ----------------
x = t(2.2)
vib = 1 + 0.006 * np.sin(2 * np.pi * 5.5 * x)
f = 110 * vib * (1 + 0.04 * np.clip(x * 3, 0, 1))
horn = signal.sawtooth(2 * np.pi * np.cumsum(f) / SR) + 0.5 * signal.sawtooth(2 * np.pi * np.cumsum(f * 1.5) / SR)
horn = lowpass(horn, 900) * (np.clip(x / 0.25, 0, 1) * np.clip((2.2 - x) / 0.5, 0, 1))
save("horn", reverb(horn, 0.4, 1.2))

# ---------------- powers ----------------
volley = mix(*[at(whoosh(0.5, 900, 3500) * rng.uniform(0.3, 0.7), rng.uniform(0, 1.6), 2.6) for _ in range(40)])
volley = mix(volley, *[at(thud(150, 0.12) * 0.3, 0.5 + rng.uniform(0, 1.8), 2.6) for _ in range(30)])
save("power_arrows", volley)

x = t(3.0)
crackle = np.zeros(len(x))
for _ in range(160):
    i = rng.integers(0, len(x) - 400)
    crackle[i:i + 300] += highpass(noise(300 / SR), 2000) * env(300, 0.0002, 0.002) * rng.uniform(0.2, 1)
roar = lowpass(noise(3.0), 500) * (np.clip(x / 0.15, 0, 1) * np.exp(-x / 2.0))
save("power_fire", mix(roar, crackle * 0.6, whoosh(0.8, 300, 1500) * 0.8))

x = t(3.0)
crack = highpass(noise(0.15), 800) * env(int(SR * 0.15), 0.0005, 0.03)
boom = lowpass(noise(3.0), 160) * env(len(x), 0.02, 0.9)
boom2 = lowpass(noise(3.0), 400) * env(len(x), 0.05, 0.5) * 0.5
save("thunder", reverb(mix(crack * 1.2, boom, boom2), 0.3, 1.5))
save("power_lightning", reverb(mix(crack, boom * 0.5), 0.3, 1.0))

x = t(3.2)
shimmer = np.zeros(len(x))
for f in (587.3, 740.0, 880.0, 1174.7, 1480.0):
    shimmer += np.sin(2 * np.pi * f * x * (1 + 0.002 * np.sin(2 * np.pi * 6 * x))) * (0.5 + 0.5 * np.sin(2 * np.pi * rng.uniform(1, 3) * x))
shimmer *= np.clip(x / 0.4, 0, 1) * np.clip((3.2 - x) / 1.2, 0, 1)
wings = mix(*[at(lowpass(noise(0.35), 700) * np.sin(np.pi * np.linspace(0, 1, int(SR * 0.35))) ** 2, 0.2 + k * 0.45, 3.2) for k in range(5)])
save("power_simorgh", reverb(mix(shimmer * 0.4, wings * 0.8), 0.45, 1.2))

# ---------------- ui ----------------
x = t(0.08)
save("click", np.sin(2 * np.pi * 1400 * x) * env(len(x), 0.001, 0.015), 0.5)
print("sounds written to", OUT)
