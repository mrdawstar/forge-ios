#!/usr/bin/env python3
"""The nine blades: packaged for the app, and lit the way the shipped blades were.

Forge 1.1, session S4. Run from the repository root:

    python3 docs/art/sword_lit.py "/Users/dawidbubnow/Desktop/Forge/new swords/final"

# What it reads

- `<final>/01-rough.png` ... `<final>/09-enduring.png`: the owner's chosen art, at
  whatever size each was rendered (1024x1536, 724x2172, ...). Never modified.
- The seven shipped pairs `sword1..7.png` / `sword1..7-lit.png`, read out of git
  at `TRAINING_REV` (the last commit before they were replaced), because that
  pair is the only definition of "lit" there is.

# What it writes

1. `<final>/NN-name-lit.png`: the lit variant **at the base file's own size**.
   Same pixel grid, same alpha (byte for byte), same geometry; only RGB moves.
2. `Forge/Assets.xcassets/swordN.imageset/swordN.png` and
   `swordN-lit.imageset/swordN-lit.png`: both packaged by one transform into
   the app's 483x1771 sprite, so the base and the lit share their alpha exactly.

# How a blade is packaged (asset packaging only, nothing is redrawn)

The same rule as the owner's `prepare.swift` for scale: crop to the alpha bounds
plus two pixels, scale to fit inside 463x1537, resample once (Lanczos, in
premultiplied alpha so no edge picks up the matte's colour). Placement is where
it differs, and on purpose: every shipped sprite has its **blade starting at
~490px** (the guard's lower edge; 487-494 on six of the seven) and its blade on
the canvas centre. That is what puts the same length of steel above the stone's
mouth (520px when seated) whatever the blade, and what keeps the socket's
centred occlusion on the blade (FORGE_CONTEXT §2i: "occlusion is centred"). So
each blade is placed with its blade start at 490 and its blade axis at x=241.5,
both rounded to whole pixels so the art is resampled once.

`02-struck.png` is byte-identical to the shipped `sword1.png`, so it is copied
verbatim, and its lit variant is the shipped hand-made `sword1-lit.png`, also
verbatim: the reference treatment of that exact image.

# How "lit" was measured

The shipped lit sprites differ from their bases only in RGB, and the difference
is a function of **canvas position**, the same on all seven:

- per row, a gain and an offset per channel: the hilt lifted and a touch cooler
  (the key light is upper left), falling to about half brightness at the tip;
- a highlight along the **left** edge of the silhouette, ~9 levels at the edge
  and gone by ~23px (the bevel catching the key);
- a localised additive field: a restrained highlight on the left guard arm
  beside the grip, slightly deeper shade on the right of the guard.

Fitted from the seven pairs (rows in 8px bands, smoothed; the field as the
smoothed pooled residual, faded to nothing away from where the shipped blades
had pixels), it reproduces each shipped lit sprite **held out of the fit** to
2.0-3.0 levels RMS out of 255 (5.5 for the black sword), against 12-49 for no
treatment at all. The brief also asks for a subtle rim on the right edge; the
shipped pair has none (the right edge measures -1.3), so it is added at four
levels on the outermost pixel, two on the next, cool, fading out down the blade:
edge separation, not a second light.

Nothing here writes a pixel outside the base's alpha, and alpha is never
modified, so the scene's rule that lighting is baked into the sprite and never
extends past it (`SwordSceneView`, doctrine 2) holds by construction.
"""

import os
import shutil
import subprocess
import sys
import tempfile

import numpy as np
from PIL import Image
from scipy import ndimage

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
ASSETS = os.path.join(REPO, "Forge", "Assets.xcassets")
# The last commit whose sword1..7 are the 1.0 sprites the treatment is read from.
TRAINING_REV = "98932b2"

CANVAS_W, CANVAS_H = 483, 1771
FIT_W, FIT_H = 463, 1537
BLADE_START = 490
AXIS = 241.5
RIM_LEVELS = 4.0

NAMES = ["01-rough", "02-struck", "03-shaped", "04-folded", "05-quenched",
         "06-edged", "07-proven", "08-honed", "09-enduring"]


# MARK: - Reading the shipped pairs

def shipped(name):
    """A shipped sprite as float RGBA, read from git rather than the working tree."""
    path = f"Forge/Assets.xcassets/{name}.imageset/{name}.png"
    data = subprocess.run(["git", "-C", REPO, "show", f"{TRAINING_REV}:{path}"],
                          check=True, capture_output=True).stdout
    with tempfile.NamedTemporaryFile(suffix=".png") as tmp:
        tmp.write(data)
        tmp.flush()
        return np.array(Image.open(tmp.name).convert("RGBA")).astype(np.float64)


def run_lengths(alpha):
    """Horizontal distance, in pixels, from each solid pixel to the silhouette's
    left and right edges on its row (1 at the edge itself, 0 outside)."""
    solid = alpha > 128
    h, w = solid.shape
    dl = np.zeros((h, w))
    dr = np.zeros((h, w))
    for x in range(w):
        dl[:, x] = np.where(solid[:, x], (dl[:, x - 1] + 1) if x > 0 else 1, 0)
    for x in range(w - 1, -1, -1):
        dr[:, x] = np.where(solid[:, x], (dr[:, x + 1] + 1) if x < w - 1 else 1, 0)
    return dl, dr


# MARK: - The model

def fit_rows(pairs, band=8, sigma=2.5):
    nb = (CANVAS_H + band - 1) // band
    g = np.full((nb, 3), np.nan)
    o = np.full((nb, 3), np.nan)
    for k in range(nb):
        rows = slice(k * band, (k + 1) * band)
        for c in range(3):
            xs, ys = [], []
            for base, lit in pairs:
                m = base[rows, :, 3] > 250
                xs.append(base[rows, :, c][m])
                ys.append(lit[rows, :, c][m])
            x = np.concatenate(xs)
            y = np.concatenate(ys)
            if len(x) < 60:
                continue
            coef, *_ = np.linalg.lstsq(np.vstack([x, np.ones_like(x)]).T, y, rcond=None)
            g[k, c], o[k, c] = coef
    valid = np.where(~np.isnan(g[:, 0]))[0]
    for k in range(nb):
        if np.isnan(g[k, 0]):
            j = valid[np.argmin(np.abs(valid - k))]
            g[k], o[k] = g[j], o[j]
    g = ndimage.gaussian_filter1d(g, sigma=sigma, axis=0, mode="nearest")
    o = ndimage.gaussian_filter1d(o, sigma=sigma, axis=0, mode="nearest")
    centres = np.arange(nb) * band + band / 2
    rows = np.arange(CANVAS_H)
    gy = np.stack([np.interp(rows, centres, g[:, c]) for c in range(3)], 1)
    oy = np.stack([np.interp(rows, centres, o[:, c]) for c in range(3)], 1)
    return gy, oy


def fit_left(pairs, gy, oy, maxd=24):
    left = np.zeros((maxd + 1, 3))
    count = np.zeros(maxd + 1)
    for base, lit in pairs:
        residual = lit[..., :3] - (base[..., :3] * gy[:, None] + oy[:, None])
        solid = base[..., 3] > 250
        dl, dr = run_lengths(base[..., 3])
        for d in range(1, maxd + 1):
            s = solid & (dl == d) & (dr > maxd)
            left[d] += residual[s].sum(0)
            count[d] += s.sum()
    left /= np.maximum(count, 1)[:, None]
    left[0] = left[1]
    return left


def left_term(alpha, left, pixel=1.0):
    """The left-edge highlight. `pixel` is how many canvas pixels one pixel of
    this image is, so the profile keeps its width at any source resolution."""
    dl, dr = run_lengths(alpha)
    maxd = len(left) - 1
    d = dl * pixel
    term = np.stack([np.interp(d, np.arange(maxd + 1), left[:, c]) for c in range(3)], -1)
    term[(dl == 0) | (d > maxd)] = 0
    # A run too narrow to have a left and a right bevel gets less of it.
    run = (dl + dr - 1) * pixel
    return term * np.clip((run - 4) / 20.0, 0, 1)[..., None]


def fit_field(pairs, gy, oy, left, sigma=6.0):
    num = np.zeros((CANVAS_H, CANVAS_W, 3))
    den = np.zeros((CANVAS_H, CANVAS_W))
    for base, lit in pairs:
        solid = base[..., 3] > 250
        residual = lit[..., :3] - (base[..., :3] * gy[:, None] + oy[:, None]) - left_term(base[..., 3], left)
        num += residual * solid[..., None]
        den += solid
    smooth_num = np.stack([ndimage.gaussian_filter(num[..., c], sigma) for c in range(3)], -1)
    smooth_den = ndimage.gaussian_filter(den, sigma)
    field = smooth_num / np.maximum(smooth_den, 1e-6)[..., None]
    support = ndimage.gaussian_filter((den > 0).astype(float), sigma)
    return field * np.clip(support * 3, 0, 1)[..., None]


def rim_term(alpha, canvas_y, pixel=1.0):
    dl, dr = run_lengths(alpha)
    d = dr * pixel
    profile = np.clip(1.5 - 0.5 * d, 0, 1) * (dr > 0)          # 1 at the edge, 0.5 next, then 0
    fade = np.clip((1250 - canvas_y) / 700.0, 0, 1)             # gone by the lower blade
    cool = np.array([0.92, 0.97, 1.0])
    return (RIM_LEVELS * profile * fade)[..., None] * cool


def sample(field, xs, ys):
    """Bilinear lookup of a canvas field at fractional canvas coordinates."""
    out = np.zeros(xs.shape + (field.shape[-1],))
    xs = np.clip(xs, 0, CANVAS_W - 1)
    ys = np.clip(ys, 0, CANVAS_H - 1)
    for c in range(field.shape[-1]):
        out[..., c] = ndimage.map_coordinates(field[..., c], [ys, xs], order=1, mode="nearest")
    return out


# MARK: - Packaging

def anchors(alpha):
    ys, xs = np.where(alpha > 8)
    y0, y1 = ys.min(), ys.max()
    h = y1 - y0 + 1
    widths = (alpha > 128).sum(1)
    guard = int(np.argmax(widths))
    blade_w = np.median(widths[int(y0 + 0.55 * h): int(y0 + 0.75 * h)])
    start = guard
    while start < y1 and widths[start] > 1.35 * blade_w:
        start += 1
    rows = alpha[int(y0 + 0.55 * h): int(y0 + 0.85 * h)]
    axis = (rows * np.arange(alpha.shape[1])[None, :]).sum() / rows.sum()
    return start, axis


def packaging(alpha):
    """The one transform both the base and the lit go through."""
    ys, xs = np.where(alpha > 8)
    x0 = max(0, xs.min() - 2)
    y0 = max(0, ys.min() - 2)
    x1 = min(alpha.shape[1] - 1, xs.max() + 2)
    y1 = min(alpha.shape[0] - 1, ys.max() + 2)
    cw, ch = x1 - x0 + 1, y1 - y0 + 1
    scale = min(FIT_H / ch, FIT_W / cw)
    rw, rh = round(cw * scale), round(ch * scale)
    start, axis = anchors(alpha)
    sx, sy = rw / cw, rh / ch
    px = round(AXIS - (axis - x0 + 0.5) * sx + 0.5)
    py = round(BLADE_START - (start - y0 + 0.5) * sy + 0.5)
    assert 0 <= px and px + rw <= CANVAS_W and 0 <= py and py + rh <= CANVAS_H, "blade off the canvas"
    return dict(box=(x0, y0, x1 + 1, y1 + 1), size=(rw, rh), at=(px, py), sx=sx, sy=sy)


def package(rgba_uint8, t):
    image = Image.fromarray(rgba_uint8, "RGBA").crop(t["box"])
    resized = image.convert("RGBa").resize(t["size"], Image.LANCZOS).convert("RGBA")
    canvas = Image.new("RGBA", (CANVAS_W, CANVAS_H), (0, 0, 0, 0))
    canvas.paste(resized, t["at"])
    return canvas


def canvas_coords(shape, t):
    """Where each source pixel lands on the canvas."""
    h, w = shape
    x0, y0 = t["box"][:2]
    px, py = t["at"]
    u = np.arange(w)[None, :].repeat(h, 0)
    v = np.arange(h)[:, None].repeat(w, 1)
    return px + (u - x0 + 0.5) * t["sx"] - 0.5, py + (v - y0 + 0.5) * t["sy"] - 0.5


def light(base, t, model):
    gy, oy, left, field = model
    alpha = base[..., 3]
    cx, cy = canvas_coords(alpha.shape, t)
    pixel = t["sx"]
    gain = sample(gy[:, None, :].repeat(CANVAS_W, 1), cx, cy)
    offset = sample(oy[:, None, :].repeat(CANVAS_W, 1), cx, cy)
    lit = base.copy()
    rgb = base[..., :3] * gain + offset + sample(field, cx, cy)
    rgb += left_term(alpha, left, pixel) + rim_term(alpha, cy, pixel)
    visible = alpha > 0
    lit[..., :3] = np.where(visible[..., None], np.clip(rgb, 0, 255), base[..., :3])
    lit[..., 3] = alpha
    return lit


def save_png(array, path):
    Image.fromarray(np.round(array).astype(np.uint8), "RGBA").save(path, optimize=True)


def write_asset(image, name):
    folder = os.path.join(ASSETS, f"{name}.imageset")
    os.makedirs(folder, exist_ok=True)
    image.save(os.path.join(folder, f"{name}.png"), optimize=True)
    with open(os.path.join(folder, "Contents.json"), "w") as f:
        f.write('{\n  "images" : [\n    {\n      "filename" : "%s.png",\n'
                '      "idiom" : "universal",\n      "scale" : "1x"\n    }\n  ],\n'
                '  "info" : {\n    "author" : "xcode",\n    "version" : 1\n  }\n}\n' % name)


def main(final):
    pairs = [(shipped(f"sword{i}"), shipped(f"sword{i}-lit")) for i in range(1, 8)]
    gy, oy = fit_rows(pairs)
    left = fit_left(pairs, gy, oy)
    model = (gy, oy, left, fit_field(pairs, gy, oy, left))

    for index, name in enumerate(NAMES, start=1):
        source = os.path.join(final, f"{name}.png")
        lit_path = os.path.join(final, f"{name}-lit.png")
        if name == "02-struck":
            # The shipped Rough blade, unchanged: its own hand-lit variant is
            # the reference, so both go in byte for byte.
            with open(lit_path, "wb") as out:
                subprocess.run(["git", "-C", REPO, "show",
                                f"{TRAINING_REV}:Forge/Assets.xcassets/sword1-lit.imageset/sword1-lit.png"],
                               check=True, stdout=out)
            shutil.copyfile(source, os.path.join(ASSETS, "sword2.imageset", "sword2.png"))
            shutil.copyfile(lit_path, os.path.join(ASSETS, "sword2-lit.imageset", "sword2-lit.png"))
            print(f"{name}: verbatim (shipped sword1 and its lit)")
            continue

        base = np.array(Image.open(source).convert("RGBA")).astype(np.float64)
        t = packaging(base[..., 3])
        lit = light(base, t, model)
        save_png(lit, lit_path)
        written = np.array(Image.open(lit_path).convert("RGBA"))
        assert np.array_equal(written[..., 3], base[..., 3].astype(np.uint8)), "alpha moved"

        write_asset(package(base.astype(np.uint8), t), f"sword{index}")
        write_asset(package(written, t), f"sword{index}-lit")
        print(f"{name}: scale {t['sx']:.3f}, placed at {t['at']}, {t['size'][0]}x{t['size'][1]}")


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else
         "/Users/dawidbubnow/Desktop/Forge/new swords/final")
