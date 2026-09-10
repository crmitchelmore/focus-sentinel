#!/usr/bin/env python3
"""Render the five status marks into `FocusUI`'s asset catalogue.

    scripts/make-status-glyphs.py [--check]

`--check` re-renders into a temporary directory and fails if the committed bytes differ, so a
hand-edited asset cannot survive the gate.

## Why the marks are generated rather than drawn

The same reason the app icon is (`scripts/make-appicon.sh`): this file is the source and
`Packages/FocusUI/Sources/FocusUI/Resources/StatusGlyphs.xcassets/*.imageset/*.png` is its
output, committed because the build needs it as an input. Running it again on any machine
reproduces the same bytes — there is no renderer, no font, no colour management and no system
appearance anywhere in the path, only integer arithmetic over a 16-unit grid.

## The geometry, and why it is *outlines* rather than a moving dot

`FocusStatus` has said since e01 that "silhouettes are deliberately unalike". The e11 direction
(§1.2) keeps the ring — it is already the app icon's mark — and breaks the **outline** for each
state rather than moving a dot inside a constant one. At 16 pt, in monochrome, with Differentiate
Without Colour on, a dot's position is a far weaker signal than a discontinuity in the outline.

    relevant    closed ring, dot inside          closed, symmetric, quiet
    uncertain   ring open at the top, dot above  the outline is discontinuous
    unrelated   three-quarter arc, dot low out   asymmetric even when blurred
    paused      two bars, no ring                a different object entirely
    onBreak     empty ring, no dot               presence and absence

Those five are the inline SVG on the settled canvas (`Glyphs.dc.html`), transcribed unit for
unit. SVG's y axis points down and this renders top-down too, so the numbers below are the
canvas's numbers and can be diffed against it by eye.

## Template images carry alpha, not colour

Every pixel written here is black with a coverage alpha. The menu bar decides the ink (F-146),
and so does `Image(_:)` under `.foregroundStyle` in the badge — a bitmap with its own colours in
it is the one thing the template contract forbids.

## Antialiasing

8×8 supersampling per pixel, coverage counted by point-in-shape tests. Deterministic integer
arithmetic rather than a rasteriser, because "same inputs, same bytes" has to hold on a machine
that is not this one.
"""

import math
import struct
import sys
import zlib
from pathlib import Path

#: The grid every shape below is expressed on. The canvas's `viewBox="0 0 16 16"`.
GRID = 16.0

#: Supersamples per pixel per axis.
SUPERSAMPLE = 8

#: (asset name, pixel side) for each scale an `.imageset` declares. 16 pt at 1× and 2×.
SCALES = [("1x", 16), ("2x", 32)]

#: The stroke every outline is drawn with, in grid units. One number: the family is one pen.
STROKE = 1.6


def ring(cx, cy, radius):
    """A stroked circle: the annulus between two radii."""
    inner = radius - STROKE / 2
    outer = radius + STROKE / 2
    return lambda x, y: inner * inner <= (x - cx) ** 2 + (y - cy) ** 2 <= outer * outer


def arc(cx, cy, radius, start_degrees, sweep_degrees):
    """A stroked arc, swept clockwise on screen from `start_degrees`.

    Angles are measured the way SVG measures them: 0° at three o'clock, increasing clockwise,
    because the y axis points down. Round caps, which is what the canvas draws — a butt cap at
    16 pt reads as a broken pen rather than as a deliberate opening.
    """
    inside = ring(cx, cy, radius)
    start = math.radians(start_degrees)
    sweep = math.radians(sweep_degrees)
    cap_radius = STROKE / 2
    caps = [
        (cx + radius * math.cos(angle), cy + radius * math.sin(angle))
        for angle in (start, start + sweep)
    ]

    def covered(x, y):
        for cap_x, cap_y in caps:
            if (x - cap_x) ** 2 + (y - cap_y) ** 2 <= cap_radius * cap_radius:
                return True
        if not inside(x, y):
            return False
        # The angle of this sample, folded into [0, 2π) from the start of the sweep.
        theta = (math.atan2(y - cy, x - cx) - start) % (2 * math.pi)
        return theta <= sweep

    return covered


def disc(cx, cy, radius):
    """A filled circle."""
    return lambda x, y: (x - cx) ** 2 + (y - cy) ** 2 <= radius * radius


def bar(x0, y0, width, height, radius):
    """A filled rounded rectangle.

    The signed-distance form rather than a corner case analysis: the distance from the point to
    the rectangle inset by `radius` is at most `radius` exactly on the rounded rectangle, on the
    edges and in the corners alike. Written the other way first, and it nicked all four corners
    of both bars.
    """
    x1, y1 = x0 + width, y0 + height

    def covered(x, y):
        dx = max(x0 + radius - x, 0.0, x - (x1 - radius))
        dy = max(y0 + radius - y, 0.0, y - (y1 - radius))
        return dx * dx + dy * dy <= radius * radius

    return covered


#: The five marks. Each is a list of shapes unioned into one coverage mask.
#:
#: Transcribed from `Glyphs.dc.html`, with **one measured amendment**. The `unrelated` arc is the
#: canvas's `M8 2 A6 6 0 1 1 2 8` unchanged — 270° swept clockwise from −90°, leaving the opening
#: in the top-left quadrant and the dot outside it, low and trailing.
#:
#: The `uncertain` arc is the canvas's `M11 2.8 A6 6 0 1 1 5 2.8` with **one number amended**: its
#: opening is widened from 60° to 180°, still centred on the top, so the ring is drawn as its lower
#: half with the dot detached above the opening. Everything else — the ring, the stroke, the
#: detached dot, the idea that the outline breaks — is the canvas's.
#:
#: The amendment is the gate doing the job it was built for, and the numbers are why. The canvas's
#: own figure does not survive it: at 16 pt, blurred, a 60° gap with the dot sitting over it
#: measured **1.43** against the plain ring of `onBreak`, which would have shipped the two most
#: confusable marks in the family — the dot fills the gap back in at exactly the size the
#: distinction has to hold. Widening to 120° reaches 11.64 unmarked but only **4.46** once the
#: attention mark is composited, because the mark eats the top-trailing corner (44 % of the side)
#: and takes half the gap with it. 180° is the smallest opening that holds the marked pair at
#: 10.75 — the same order as `relevant` vs `onBreak`, which the direction calls the strongest cue
#: it has. The design was settled on a 72-pixel swatch with no mark on it; this ships at sixteen
#: with one.
MARKS = {
    "relevant": [ring(8, 8, 6), disc(8, 8, 2.2)],
    "uncertain": [arc(8, 8, 6, 0, 180), disc(8, 1.6, 1.6)],
    "unrelated": [arc(8, 8, 6, -90, 270), disc(13.2, 13.2, 2.0)],
    "paused": [bar(4.2, 3, 2.6, 10, 1), bar(9.2, 3, 2.6, 10, 1)],
    "onBreak": [ring(8, 8, 6)],
}

#: The asset name each status resolves. Capitalised, undotted: `check-strings.sh` keys its
#: "this is a catalogue key" heuristic on dotted names under `nudge.`, `shell.` and `status.`,
#: and an asset named that way would be hunted for in a String Catalog for ever.
ASSET_NAMES = {
    "relevant": "StatusMarkRelevant",
    "uncertain": "StatusMarkUncertain",
    "unrelated": "StatusMarkUnrelated",
    "paused": "StatusMarkPaused",
    "onBreak": "StatusMarkOnBreak",
}


def coverage(shapes, side):
    """An 8-bit alpha plane, `side` × `side`, top-down."""
    scale = GRID / side
    step = scale / SUPERSAMPLE
    offset = step / 2
    plane = bytearray(side * side)
    for row in range(side):
        for column in range(side):
            hits = 0
            for sub_y in range(SUPERSAMPLE):
                y = row * scale + sub_y * step + offset
                for sub_x in range(SUPERSAMPLE):
                    x = column * scale + sub_x * step + offset
                    for shape in shapes:
                        if shape(x, y):
                            hits += 1
                            break
            plane[row * side + column] = round(255 * hits / (SUPERSAMPLE * SUPERSAMPLE))
    return plane


def png(alpha, side):
    """The alpha plane as an 8-bit greyscale+alpha PNG, black ink throughout.

    Written by hand rather than by a library for the reason the rest of `scripts/` has none:
    the toolchain here is whatever Apple shipped, and `zlib` and `struct` are in the standard
    one. Compression level 9 with no filtering, so the bytes are a function of the pixels alone.
    """
    raw = bytearray()
    for row in range(side):
        raw.append(0)  # filter type 0 — none
        for column in range(side):
            raw.append(0)  # luminance: black
            raw.append(alpha[row * side + column])

    def chunk(kind, payload):
        return (
            struct.pack(">I", len(payload))
            + kind
            + payload
            + struct.pack(">I", zlib.crc32(kind + payload) & 0xFFFFFFFF)
        )

    return (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", struct.pack(">IIBBBBB", side, side, 8, 4, 0, 0, 0))
        + chunk(b"IDAT", zlib.compress(bytes(raw), 9))
        + chunk(b"IEND", b"")
    )


def contents_json(asset):
    """The `.imageset`'s manifest, with the template rendering intent declared."""
    images = ",\n".join(
        f"""    {{
      "filename" : "{asset}-{side}.png",
      "idiom" : "mac",
      "scale" : "{scale}"
    }}"""
        for scale, side in SCALES
    )
    return f"""{{
  "images" : [
{images}
  ],
  "info" : {{
    "author" : "xcode",
    "version" : 1
  }},
  "properties" : {{
    "template-rendering-intent" : "template"
  }}
}}
"""


CATALOG_JSON = """{
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
"""


def render(root: Path) -> dict[Path, bytes]:
    """Every file this script owns, as path → bytes. Nothing is written by this function."""
    files = {root / "Contents.json": CATALOG_JSON.encode()}
    for status, shapes in MARKS.items():
        asset = ASSET_NAMES[status]
        directory = root / f"{asset}.imageset"
        files[directory / "Contents.json"] = contents_json(asset).encode()
        for _, side in SCALES:
            files[directory / f"{asset}-{side}.png"] = png(coverage(shapes, side), side)
    return files


def main(argv: list[str]) -> int:
    repository = Path(__file__).resolve().parent.parent
    root = repository / "Packages/FocusUI/Sources/FocusUI/Resources/StatusGlyphs.xcassets"
    files = render(root)

    if "--check" in argv[1:]:
        failed = 0
        for path, payload in sorted(files.items()):
            committed = path.read_bytes() if path.is_file() else None
            if committed != payload:
                print(f"FAIL {path.relative_to(repository)} is not what the geometry renders")
                failed = 1
            else:
                print(f"ok   {path.relative_to(repository)}")
        # And nothing else may live in the catalogue: a stray `.imageset` is a mark nobody
        # generated and nobody is holding to the distance floor.
        for path in sorted(root.rglob("*")):
            if path.is_file() and path not in files:
                print(f"FAIL {path.relative_to(repository)} is in the catalogue and is not generated")
                failed = 1
        return failed

    for path, payload in sorted(files.items()):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(payload)
        print(f"wrote {path.relative_to(repository)} ({len(payload)} bytes)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
