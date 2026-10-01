#!/usr/bin/env python3
"""Make `hero-plate.png`, the cold open's sword in the stone, from `hero.png`.

Why this exists (FORGE_CONTEXT §17.1, the polish pass of 2026-10-01)
--------------------------------------------------------------------
`hero.png` is a rendered plate: the sword and the stone on a background of
near-black (1-12 on 255), with a light ray from the upper left and a lit floor.
The first run's room is not black where the plate sits: `FirstRunAmbience`
lights it warm from the upper left, 13-20 on 255 around the plate's top edge.
Drawn source-over, the plate's near-black *covered* that light, so the art sat
in the room as a darker rectangle; the two linear masks that faded its edges
had straight, rectangular contours, and their linear ramps drew Mach bands.
On an OLED the 1-6 of the plate's background were lit pixels next to unlit
ones, so the rectangle was there even where the room was black.

What this does
--------------
The art's black is treated as empty space, not black paint:

1. **A matte of the subject.** The luminance, blurred, keyed (5 -> 20 on 255),
   then eroded back by about the blur so the matte fills the stone and the
   sword without spilling a dark halo into the room around them.
2. **A black point for the empty space only.** Outside the matte the darkest
   levels are pulled to true zero with a soft knee (7, fading out by 21), so an
   OLED leaves those pixels off. Inside the matte nothing changes: the stone's
   own shadows keep every level they had.
3. **Premultiplied light.** Colour = the art; alpha = the larger of the matte
   and the pixel's own brightest channel. Where the matte is empty the plate
   adds its light (the ray, the dust) to the room instead of replacing the room
   with its black; where it is full, the stone is solid.
4. **Smooth edges.** What light reaches the edge of the frame — the ray, the
   floor — is faded by smoothstep ramps (left 22%, right 10%, top 8%, bottom
   30%), which have no corner in them to band.

The paywall and the Proof Card keep `hero.png` as it is.

Usage (from the repository root; needs numpy, scipy and Pillow):

    python3 docs/art/hero_plate.py
"""

import json
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "Forge/Assets.xcassets/hero.imageset/hero.png"
TARGET_SET = ROOT / "Forge/Assets.xcassets/hero-plate.imageset"
TARGET = TARGET_SET / "hero-plate.png"

# The plate is never drawn taller than 380 pt (`FirstRunView.artHeight`), which
# is 1140 px at 3x.
HEIGHT = 1152

BLACK_POINT = 7.0
KEY = (5.0, 20.0)
KEY_BLUR = 18
ERODE = 26
SOFTEN = 3
EDGES = {"left": 0.22, "right": 0.10, "top": 0.08, "bottom": 0.30}


def smoothstep(edge0, edge1, x):
    t = np.clip((x - edge0) / (edge1 - edge0), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def luminance(rgb):
    return 0.2126 * rgb[..., 0] + 0.7152 * rgb[..., 1] + 0.0722 * rgb[..., 2]


def main():
    art = np.asarray(Image.open(SOURCE).convert("RGB")).astype(np.float64)
    height, width, _ = art.shape
    v, u = np.mgrid[0:height, 0:width].astype(np.float64)
    u /= width
    v /= height

    # 1. The subject's matte.
    key = smoothstep(*KEY, ndimage.gaussian_filter(luminance(art), KEY_BLUR))
    key = ndimage.grey_erosion(key, size=(2 * ERODE + 1, 2 * ERODE + 1))
    key = np.clip(ndimage.gaussian_filter(key, SOFTEN), 0.0, 1.0)

    # 2. True black for the empty space, and only there.
    toe = np.clip(art - BLACK_POINT * (1.0 - smoothstep(BLACK_POINT, 3 * BLACK_POINT, art)), 0, 255)
    colour = art * key[..., None] + toe * (1.0 - key[..., None])

    # 4. Smooth edges.
    edges = (
        smoothstep(0, EDGES["left"], u)
        * smoothstep(0, EDGES["right"], 1 - u)
        * smoothstep(0, EDGES["top"], v)
        * smoothstep(0, EDGES["bottom"], 1 - v)
    )

    # 3. Premultiplied light over the room.
    alpha = np.maximum(key, colour.max(axis=-1) / 255.0) * edges
    premultiplied = colour * edges[..., None]

    # Resized premultiplied, so no dark fringe is resampled into the edges.
    size = (round(HEIGHT * width / height), HEIGHT)

    def resize(channel):
        return np.asarray(Image.fromarray(channel.astype(np.float32)).resize(size, Image.LANCZOS))

    alpha = np.clip(resize(alpha), 0.0, 1.0)
    premultiplied = np.clip(np.stack([resize(premultiplied[..., c]) for c in range(3)], -1), 0, 255)
    straight = np.where(alpha[..., None] > 1e-4, premultiplied / np.maximum(alpha[..., None], 1e-4), 0)

    rgba = np.dstack([np.clip(straight, 0, 255), alpha * 255.0]).round().astype(np.uint8)
    TARGET_SET.mkdir(parents=True, exist_ok=True)
    Image.fromarray(rgba, "RGBA").save(TARGET, optimize=True)
    (TARGET_SET / "Contents.json").write_text(json.dumps({
        "images": [{"filename": TARGET.name, "idiom": "universal", "scale": "1x"}],
        "info": {"author": "xcode", "version": 1},
    }, indent=2) + "\n")
    print(f"wrote {TARGET.relative_to(ROOT)} {size[0]}x{size[1]}")


if __name__ == "__main__":
    main()
