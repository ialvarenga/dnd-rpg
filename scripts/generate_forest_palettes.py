#!/usr/bin/env python3
"""Paint recoloured palette columns into the KayKit forest atlas.

The pack ships a 1024x1024 atlas divided into eight vertical columns. Only the
first one carries colour; KayKit leaves the other seven blank and labels them
"space reserved for future nature pack additions, and extra tier colors -- or
you can add your own colors if you'd like". This script takes them up on that.

Column 0 is four stacked vertical gradients, one per material band:

    v 0.00-0.25  foliage (green)
    v 0.25-0.50  wood    (orange)
    v 0.50-0.75  stone   (blue-grey)
    v 0.75-1.00  neutral (white to black)

Every model's UVs stay inside column 0, so `forest_palette_N.tres` selects a
palette purely with `uv1_offset.x = 0.125 * (N - 1)`. Column 0 is the source of
truth and is never written, which keeps this script idempotent.
"""

from __future__ import annotations

import argparse
import colorsys
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
TEXTURE_PATH = ROOT / "godot/assets/kaykit_forest/forest_texture.png"
COLUMNS = 8
# (v_start, v_end) of each band, as a fraction of texture height.
BANDS = ("foliage", "wood", "stone", "neutral")


class Recolour:
    """Blend a band's hue toward `hue`, then scale saturation and value.

    Blending rather than rotating keeps each band's own light-to-dark ramp
    while pulling the whole band toward one target colour, so `strength` reads
    as "how far from the original hue" instead of "how many degrees".
    """

    def __init__(self, hue: float, strength: float, saturation: float, value: float) -> None:
        self.hue = hue / 360.0
        self.strength = strength
        self.saturation = saturation
        self.value = value

    def apply(self, rgb: tuple[int, int, int]) -> tuple[int, int, int]:
        h, s, v = colorsys.rgb_to_hsv(*(channel / 255.0 for channel in rgb))
        # Interpolate the short way around the hue circle.
        delta = (self.hue - h + 0.5) % 1.0 - 0.5
        h = (h + delta * self.strength) % 1.0
        s = min(1.0, s * self.saturation)
        v = min(1.0, v * self.value)
        return tuple(round(channel * 255.0) for channel in colorsys.hsv_to_rgb(h, s, v))


# Palette 1 is the pack's own colouring and is not generated. Each entry maps a
# band to its recolour; "neutral" is always copied verbatim so the greyscale
# ramp stays usable as a shared highlight/shadow strip.
PALETTES: dict[int, tuple[str, dict[str, Recolour]]] = {
    2: ("pine", {
        "foliage": Recolour(150, 0.45, 1.10, 0.78),
        "wood": Recolour(25, 0.30, 0.95, 0.85),
        "stone": Recolour(205, 0.30, 1.00, 0.92),
    }),
    3: ("spring", {
        "foliage": Recolour(95, 0.55, 0.90, 1.14),
        "wood": Recolour(30, 0.30, 0.90, 1.05),
        "stone": Recolour(200, 0.20, 0.92, 1.05),
    }),
    4: ("olive", {
        "foliage": Recolour(68, 0.60, 0.68, 0.98),
        "wood": Recolour(33, 0.40, 0.80, 0.96),
        "stone": Recolour(60, 0.25, 0.75, 1.00),
    }),
    5: ("shadow", {
        "foliage": Recolour(140, 0.35, 0.95, 0.60),
        "wood": Recolour(15, 0.20, 0.90, 0.64),
        "stone": Recolour(210, 0.30, 1.00, 0.68),
    }),
    6: ("gold", {
        "foliage": Recolour(42, 0.85, 1.00, 1.08),
        "wood": Recolour(28, 0.40, 0.95, 1.00),
        "stone": Recolour(45, 0.30, 0.85, 1.00),
    }),
    7: ("rust", {
        "foliage": Recolour(18, 0.85, 1.05, 0.92),
        "wood": Recolour(12, 0.40, 1.00, 0.90),
        "stone": Recolour(25, 0.30, 0.80, 0.94),
    }),
    8: ("dry", {
        "foliage": Recolour(48, 0.80, 0.50, 1.06),
        "wood": Recolour(38, 0.40, 0.65, 1.02),
        "stone": Recolour(48, 0.30, 0.60, 1.02),
    }),
}


def band_for(y: int, height: int) -> str:
    return BANDS[min(len(BANDS) - 1, y * len(BANDS) // height)]


def build(source: Image.Image) -> Image.Image:
    width, height = source.size
    column_width = width // COLUMNS
    result = source.copy()
    # Column 0 is a pure vertical gradient, so one sample per row describes it.
    base_rows = [source.getpixel((0, y)) for y in range(height)]
    for index, (_name, bands) in PALETTES.items():
        left = (index - 1) * column_width
        for y, pixel in enumerate(base_rows):
            band = band_for(y, height)
            recolour = bands.get(band)
            rgb = pixel[:3] if recolour is None else recolour.apply(pixel[:3])
            result.paste(rgb + pixel[3:], (left, y, left + column_width, y + 1))
    return result


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="fail if the atlas is out of date")
    args = parser.parse_args()

    source = Image.open(TEXTURE_PATH).convert("RGBA")
    if source.size[0] % COLUMNS:
        raise SystemExit("Atlas width %d is not divisible by %d columns" % (source.size[0], COLUMNS))
    generated = build(source)
    if generated.tobytes() == source.tobytes():
        return
    if args.check:
        raise SystemExit("Out of date: %s (run scripts/generate_forest_palettes.py)" % TEXTURE_PATH.relative_to(ROOT))
    generated.save(TEXTURE_PATH)
    print("Wrote %d palette columns into %s" % (len(PALETTES), TEXTURE_PATH.relative_to(ROOT)))


if __name__ == "__main__":
    main()
