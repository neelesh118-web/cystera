"""The launcher icon and the splash mark, generated rather than hand-exported.

Why a script and not five PNGs in a folder: the app's icon is its most-looked-at
artwork, and a raster-only icon set is one that nobody can adjust later — you get
a tile that is 3% off, a rose that does not match the app's tokens, and a rebuild
that cannot fix either. Every file this writes is derived from the design below,
so changing the mark or the ramp is a two-line edit and a re-run.

Run it from the repo root:

    python tool/make_icons.py

What it writes, and why each one:

* `mipmap-*/ic_launcher.png` and `ic_launcher_round.png` — the legacy icons, for
  the launchers and store listings that read a bitmap. The app's `minSdk` is 26,
  so the adaptive icon below is what every installed device actually draws; these
  exist so the Flutter logo is not left anywhere in the tree, and so a listing
  that needs a PNG has the real mark rather than a screenshot of one.
* `mipmap-*/ic_launcher_discreet.png` — the discreet entry's legacy icon, matching
  the adaptive one it already had.
* `drawable-*/splash_mark.png` — the mark alone, white, for the launch window.
  Alone and not on a tile, because the launch window already paints the brand
  colour behind it: a tile here would be a square of gradient floating on a
  rectangle of gradient, which is what the first version of this looked like.

The vector layers next to them (`ic_launcher_foreground.xml`,
`ic_launcher_background.xml`, `ic_launcher_monochrome.xml`, `ic_splash_mark.xml`,
`splash_background.xml`) are hand-written and NOT generated: they are the same
geometry in 108-unit canvas coordinates, which is the form an adaptive icon needs.
If the mark changes here, it changes there too — the geometry is written out in
both places on purpose, because a vector that silently disagrees with the raster
is worse than either.

The design, in one line each:

* The mark is a **cycle ring with a gap and a dot in the gap** — a period that
  comes round again, with the dot standing where the next one is due.
* The tile is the app's own ramp, crimson `#C81E48` to rose `#FF7A94`, on a
  rounded square. It is the same gradient the app's header wash uses, so the icon
  and the app look like the same thing.
* The discreet icon stays slate and grey and looks like a notebook. That is the
  whole point of it (`android/app/src/main/res/values/colors.xml`), and it is why
  the two icons share no colour at all.

Two proportions were wrong in the first version and are worth naming, because both
fail the same way — the mark reads as a closed ring and the "cycle" idea is lost:

* the gap was 70 degrees, and the round caps on its ends plus a dot that was wider
  than the stroke left about three degrees of visible space each side. It is now
  110 degrees, which stays legible down to a 48px bitmap;
* the mark was drawn at 62% of a tile that is never masked on a legacy launcher,
  so it sat lost in the middle. The adaptive foreground keeps the sign's own
  geometry (the launcher masks that one), and the flat bitmap is drawn 20% larger,
  which is the difference between an icon and a dot.
"""

from __future__ import annotations

import math
import os

from PIL import Image, ImageDraw

RES = os.path.normpath(
    os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'android', 'app', 'src', 'main', 'res')
)

# The app's own tokens, copied from lib/core/theme/app_theme.dart. Copied rather
# than read because this script must run without a Dart toolchain.
CRIMSON = (200, 30, 72)  # Rose.crimson
ROSE = (255, 122, 148)  # Rose.rose
WHITE = (255, 255, 255)

# The discreet palette, from values/colors.xml.
SLATE = (43, 48, 56)
DISCREET_CARD = (242, 243, 245)
DISCREET_SPINE = (195, 199, 206)
DISCREET_RULE = (138, 144, 153)

# The mark's geometry, in the 108-unit adaptive-icon canvas. These five numbers are
# repeated in the four vector drawables next to this script; changing one means
# changing both, which is the cost of not being able to parse XML from here.
CANVAS = 108.0
MID_RADIUS = 22.0
STROKE = 11.0
GAP_CENTRE = -45.0  # degrees, y downwards: the top-right
GAP_HALF_WIDTH = 55.0
DOT_RADIUS = 6.5

# The flat bitmap is never masked by the launcher, so its mark is drawn 20% larger
# than the adaptive one. At 1.0 the mark occupies 51% of the canvas, which looks
# correct inside a launcher's mask and undersized on a plain rounded square.
BITMAP_SCALE = 1.20

SUPERSAMPLE = 4

# density bucket -> launcher icon size in pixels (48dp)
LAUNCHER_SIZES = {
    'mdpi': 48,
    'hdpi': 72,
    'xhdpi': 96,
    'xxhdpi': 144,
    'xxxhdpi': 192,
}

# density bucket -> splash mark size in pixels (96dp)
SPLASH_SIZES = {
    'mdpi': 96,
    'hdpi': 144,
    'xhdpi': 192,
    'xxhdpi': 288,
    'xxxhdpi': 384,
}


def _ramp(c0, c1, steps):
    """The colours of a vertical ramp from [c0] to [c1], top to bottom."""
    out = []
    for i in range(steps):
        t = i / max(steps - 1, 1)
        out.append(tuple(round(a + (b - a) * t) for a, b in zip(c0, c1)))
    return out


def _tile(size, c0, c1, radius_fraction=0.26):
    """A rounded square filled with a vertical ramp, as a supersampled RGBA image."""
    big = size * SUPERSAMPLE
    ramp = Image.new('RGB', (1, big))
    for y, colour in enumerate(_ramp(c0, c1, big)):
        ramp.putpixel((0, y), colour)
    ramp = ramp.resize((big, big), Image.NEAREST)

    mask = Image.new('L', (big, big), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        (0, 0, big - 1, big - 1), radius=round(big * radius_fraction), fill=255
    )
    out = Image.new('RGBA', (big, big), (0, 0, 0, 0))
    out.paste(ramp, (0, 0), mask)
    return out


def _circle_tile(size):
    """The round legacy variant: the same ramp, clipped to a circle."""
    big = size * SUPERSAMPLE
    ramp = Image.new('RGB', (1, big))
    for y, colour in enumerate(_ramp(CRIMSON, ROSE, big)):
        ramp.putpixel((0, y), colour)
    ramp = ramp.resize((big, big), Image.NEAREST)

    mask = Image.new('L', (big, big), 0)
    ImageDraw.Draw(mask).ellipse((0, 0, big - 1, big - 1), fill=255)
    out = Image.new('RGBA', (big, big), (0, 0, 0, 0))
    out.paste(ramp, (0, 0), mask)
    return out


def _draw_mark(draw, cx, cy, unit, colour):
    """The cycle ring and its dot, where [unit] is the canvas-to-pixel scale.

    Drawn as a train of filled circles rather than an arc because PIL's arc has
    square ends and no antialiasing: this gives round caps for free, which is the
    difference between a ring and a bite out of a ring at 48px.
    """
    radius = MID_RADIUS * unit
    half = STROKE * unit / 2
    start = GAP_CENTRE + GAP_HALF_WIDTH
    sweep = 360.0 - GAP_HALF_WIDTH * 2
    samples = max(int(sweep * 2), 240)
    for i in range(samples + 1):
        angle = math.radians(start + sweep * i / samples)
        x = cx + radius * math.cos(angle)
        y = cy + radius * math.sin(angle)
        draw.ellipse((x - half, y - half, x + half, y + half), fill=colour)

    dot_angle = math.radians(GAP_CENTRE)
    dot = DOT_RADIUS * unit
    dx = cx + radius * math.cos(dot_angle)
    dy = cy + radius * math.sin(dot_angle)
    draw.ellipse((dx - dot, dy - dot, dx + dot, dy + dot), fill=colour)


def mark_only(size, colour=WHITE, scale=BITMAP_SCALE):
    """Just the ring and dot on transparency, for a mask, a splash or a preview."""
    big = size * SUPERSAMPLE
    image = Image.new('RGBA', (big, big), (0, 0, 0, 0))
    _draw_mark(ImageDraw.Draw(image), big / 2, big / 2, big / CANVAS * scale, colour)
    return image.resize((size, size), Image.LANCZOS)


def icon(size, round_icon=False):
    """The launch icon: the ramp tile with the mark centred on it."""
    image = _circle_tile(size) if round_icon else _tile(size, CRIMSON, ROSE)
    big = size * SUPERSAMPLE
    _draw_mark(ImageDraw.Draw(image), big / 2, big / 2, big / CANVAS * BITMAP_SCALE, WHITE)
    return image.resize((size, size), Image.LANCZOS)


def discreet_icon(size):
    """The discreet entry: a notebook on slate, in none of the app's colours.

    Proportions copied from `drawable/ic_discreet_foreground.xml` so the legacy
    bitmap is the same drawing as the vector, at the same place on the tile.
    """
    big = size * SUPERSAMPLE
    image = _tile(size, SLATE, SLATE, radius_fraction=0.26).resize((big, big), Image.NEAREST)
    draw = ImageDraw.Draw(image)
    unit = big / CANVAS

    def rect(x, y, w, h, colour):
        draw.rounded_rectangle(
            (x * unit, y * unit, (x + w) * unit, (y + h) * unit),
            radius=6 * unit,
            fill=colour,
        )

    rect(32, 30, 38, 48, DISCREET_CARD)  # card body
    draw.rectangle((32 * unit, 30 * unit, 38 * unit, 78 * unit), fill=DISCREET_SPINE)  # spine
    for i, width in enumerate((18, 18, 11)):  # three ruled lines
        y = 44 + i * 10
        draw.rectangle((46 * unit, y * unit, (46 + width) * unit, (y + 3.5) * unit), fill=DISCREET_RULE)
    return image.resize((size, size), Image.LANCZOS)


def _write(image, relative_path):
    path = os.path.join(RES, relative_path)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    image.save(path, 'PNG', optimize=True)
    print(f'  {relative_path}  ({image.width}x{image.height})')


def main():
    print('launcher icons')
    for bucket, size in LAUNCHER_SIZES.items():
        _write(icon(size), f'mipmap-{bucket}/ic_launcher.png')
        _write(icon(size, round_icon=True), f'mipmap-{bucket}/ic_launcher_round.png')
        _write(discreet_icon(size), f'mipmap-{bucket}/ic_launcher_discreet.png')

    print('splash mark')
    for bucket, size in SPLASH_SIZES.items():
        _write(mark_only(size), f'drawable-{bucket}/splash_mark.png')


if __name__ == '__main__':
    main()
