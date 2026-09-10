#!/usr/bin/env python3
"""Measure whether the status marks are **unalike**, at the size and in the colour they ship in.

    scripts/glyph-distance.py [--floor N] [--print]

Prints one `<a> vs <b> distance=<value>` line per pair, then the minimum, and exits non-zero if
any pair falls below the floor in `Config/glyph-distance-floor.txt`.

## Why this exists

`FocusStatus` has claimed since e01 that "silhouettes are deliberately unalike: … they read
differently at a glance even in monochrome at small sizes". That was a sentence, and P-132 read
the five in the real menu bar and agreed with it — a person, once, about five SF Symbols that no
longer ship. The e11 direction replaces them with the app's own family, one ring with its outline
broken per state, and says plainly that a family drawn this way ships *behind a mechanical gate
rather than an assertion of taste* (§1.2). This is that gate, and it is a sibling of
`scripts/frame-ink.py`: the same move, one layer down — a claim about what an image looks like,
turned into a number a stage can hold.

## Ten images, not five

The menu bar does not draw the five marks. It draws the five marks **and** the five marks with an
attention dot composited into the top-trailing corner (`MenuBarController.marked(_:attention:)`),
and the mark eats the corner of whatever silhouette it lands on while the silhouette shrinks to
make room. That is where a broken outline is likeliest to collide with another one, so the fold
runs over all ten.

`noticing` — the hollow ring — is deliberately **not** an eleventh through fifteenth image.
`MenuBarController` says in as many words that the visual difference between the filled dot and
the ring is *not* the load-bearing one; the words are. Holding `waiting` and `noticing` apart at
this floor would be this script asserting a distinction the app refuses to rely on. What is
asserted about them is the honest bound: that they differ at all.

## The measure

Squint at it. Each image is rendered at 16 pt at 1× — the size the menu bar actually draws — as a
coverage mask, box-downsampled by two and blurred with a 3×3 binomial kernel twice. The distance
between two is the mean absolute difference of the blurred coverages, in 0–255 units, which is
`frame-ink.py`'s scale.

Blurring is the whole point. Two marks that differ only in a one-pixel detail are two marks a
person reading a menu bar at a glance cannot tell apart, and an unblurred difference would score
them as comfortably distinct. What survives a blur is the *silhouette*, which is what the doctrine
is about.

## Where the images come from

The five 1× PNGs committed by `scripts/make-status-glyphs.py`, read with the standard library
and nothing else — the toolchain here is whatever Apple shipped. The composite's three constants
are read **out of `MenuBarController.swift`**, not copied here: this script and the app must
composite the same picture, and the only way to be sure of that is for there to be one place the
numbers are written. A source that stops spelling them fails loudly rather than silently
measuring the wrong thing.
"""

import math
import re
import struct
import sys
import zlib
from pathlib import Path

REPOSITORY = Path(__file__).resolve().parent.parent
CATALOG = REPOSITORY / "Packages/FocusUI/Sources/FocusUI/Resources/StatusGlyphs.xcassets"
CONTROLLER = REPOSITORY / "Packages/FocusUI/Sources/FocusUI/MenuBar/MenuBarController.swift"
FLOOR_FILE = REPOSITORY / "Config/glyph-distance-floor.txt"

#: The five states, in the order `FocusStatus.allCases` declares them, and their asset names.
STATES = [
    ("relevant", "StatusMarkRelevant"),
    ("uncertain", "StatusMarkUncertain"),
    ("unrelated", "StatusMarkUnrelated"),
    ("paused", "StatusMarkPaused"),
    ("onBreak", "StatusMarkOnBreak"),
]

#: The side the marks are measured at: 16 pt at 1×, which is the menu bar.
SIDE = 16


def read_png_alpha(path: Path) -> list[float]:
    """The alpha plane of an 8-bit greyscale+alpha, non-interlaced PNG, as 0…1 floats.

    Written out rather than imported for `frame-ink.py`'s reason — no Pillow, no third-party
    anything — and reading the file directly rather than going through `sips`, because `sips`
    composites a transparent image onto a ground of its own choosing and the ground is exactly
    what a template image does not have.
    """
    data = path.read_bytes()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError(f"{path} is not a PNG")

    index = 8
    width = height = None
    idat = bytearray()
    while index < len(data):
        length = struct.unpack_from(">I", data, index)[0]
        kind = data[index + 4:index + 8]
        payload = data[index + 8:index + 8 + length]
        if kind == b"IHDR":
            width, height, depth, colour, compression, filter_method, interlace = (
                struct.unpack(">IIBBBBB", payload)
            )
            if (depth, colour, compression, filter_method, interlace) != (8, 4, 0, 0, 0):
                raise ValueError(f"{path}: not an 8-bit greyscale+alpha, non-interlaced PNG")
        elif kind == b"IDAT":
            idat += payload
        elif kind == b"IEND":
            break
        index += 12 + length

    raw = zlib.decompress(bytes(idat))
    stride = width * 2
    alpha = []
    previous = bytearray(stride)
    position = 0
    for _ in range(height):
        filter_type = raw[position]
        position += 1
        line = bytearray(raw[position:position + stride])
        position += stride
        for i in range(stride):
            a = line[i - 2] if i >= 2 else 0
            b = previous[i]
            c = previous[i - 2] if i >= 2 else 0
            if filter_type == 0:
                pass
            elif filter_type == 1:
                line[i] = (line[i] + a) & 0xFF
            elif filter_type == 2:
                line[i] = (line[i] + b) & 0xFF
            elif filter_type == 3:
                line[i] = (line[i] + (a + b) // 2) & 0xFF
            elif filter_type == 4:
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                nearest = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                line[i] = (line[i] + nearest) & 0xFF
            else:
                raise ValueError(f"{path}: unknown PNG filter {filter_type}")
        alpha.extend(line[i] / 255 for i in range(1, stride, 2))
        previous = line
    return alpha


def composite_constants() -> tuple[float, float, float]:
    """`(markShare, markClearance, markStrokeShare)`, read out of `MenuBarController.swift`.

    One source for the numbers. A script that copied them would go on measuring a picture the app
    had stopped drawing, and the failure would look like a green gate.
    """
    text = CONTROLLER.read_text()
    values = []
    for name in ("markShare", "markClearance", "markStrokeShare"):
        found = re.search(rf"\b{name}\s*=\s*([0-9.]+)", text)
        if not found:
            raise SystemExit(
                f"FAIL [glyphs] {CONTROLLER.name} no longer spells `{name}` — this script "
                f"cannot composite the picture the menu bar draws"
            )
        values.append(float(found.group(1)))
    return tuple(values)


def marked(plane: list[float], share: float, clearance: float) -> list[float]:
    """`plane` with the **waiting** attention mark drawn in, as `MenuBarController.marked` does.

    The silhouette is scaled down uniformly and anchored where `NSImage(size:flipped: false)`
    anchors it — the bottom-left — and the mark is a filled disc in the top-trailing corner. Both
    are expressed here in top-down rows, which is why the glyph's rows are offset from the bottom
    and the mark's are not.
    """
    diameter = SIDE * share
    scale = (SIDE - diameter * clearance) / SIDE
    inset = SIDE * (1 - scale)  # how far down the shrunken glyph's top edge starts

    out = [0.0] * (SIDE * SIDE)
    for row in range(SIDE):
        for column in range(SIDE):
            # Sample the original at the centre of this destination pixel, mapped back.
            y = (row + 0.5 - inset) / scale
            x = (column + 0.5) / scale
            if 0 <= x < SIDE and 0 <= y < SIDE:
                out[row * SIDE + column] = plane[int(y) * SIDE + int(x)]

    radius = diameter / 2
    centre_x = SIDE - radius
    centre_y = radius
    for row in range(SIDE):
        for column in range(SIDE):
            dx = column + 0.5 - centre_x
            dy = row + 0.5 - centre_y
            if dx * dx + dy * dy <= radius * radius:
                out[row * SIDE + column] = 1.0
    return out


def squint(plane: list[float]) -> list[float]:
    """Box-downsample by two, then blur twice with a 3×3 binomial kernel."""
    half = SIDE // 2
    small = [
        sum(
            plane[(2 * row + dy) * SIDE + (2 * column + dx)]
            for dy in (0, 1)
            for dx in (0, 1)
        )
        / 4
        for row in range(half)
        for column in range(half)
    ]

    kernel = [1, 2, 1]
    for _ in range(2):
        blurred = [0.0] * (half * half)
        for row in range(half):
            for column in range(half):
                total = 0.0
                weight = 0.0
                for dy in (-1, 0, 1):
                    for dx in (-1, 0, 1):
                        y, x = row + dy, column + dx
                        if 0 <= y < half and 0 <= x < half:
                            w = kernel[dy + 1] * kernel[dx + 1]
                            total += w * small[y * half + x]
                            weight += w
                blurred[row * half + column] = total / weight
        small = blurred
    return small


def distance(a: list[float], b: list[float]) -> float:
    """Mean absolute difference of two blurred coverages, in 0–255 units."""
    return 255 * sum(abs(x - y) for x, y in zip(a, b)) / len(a)


def committed_floor() -> float:
    """The floor, read from `Config/glyph-distance-floor.txt`."""
    for line in FLOOR_FILE.read_text().splitlines():
        line = line.strip()
        if line and not line.startswith("#"):
            return float(line)
    raise SystemExit(f"FAIL [glyphs] {FLOOR_FILE} carries no floor")


def main(argv: list[str]) -> int:
    share, clearance, stroke_share = composite_constants()
    _ = stroke_share  # read so a source that stops spelling it fails; the ring is not measured

    images: dict[str, list[float]] = {}
    for state, asset in STATES:
        path = CATALOG / f"{asset}.imageset" / f"{asset}-{SIDE}.png"
        if not path.is_file():
            print(f"FAIL [glyphs] {path.relative_to(REPOSITORY)} is missing", file=sys.stderr)
            return 1
        plane = read_png_alpha(path)
        images[state] = squint(plane)
        images[f"{state}+mark"] = squint(marked(plane, share, clearance))

    names = list(images)
    if len(names) != 10:
        print(f"FAIL [glyphs] the fold covers {len(names)} images, not ten", file=sys.stderr)
        return 1

    floor = committed_floor()
    if "--floor" in argv:
        floor = float(argv[argv.index("--floor") + 1])

    worst = math.inf
    worst_pair = ("", "")
    failed = 0
    for i, a in enumerate(names):
        for b in names[i + 1:]:
            value = distance(images[a], images[b])
            verdict = "apart" if value >= floor else "ALIKE"
            print(f"{a} vs {b} distance={value:.2f} verdict={verdict}")
            if value < worst:
                worst, worst_pair = value, (a, b)
            if value < floor:
                failed = 1

    print(f"\nminimum={worst:.2f} ({worst_pair[0]} vs {worst_pair[1]})  floor={floor:.2f}")
    if failed:
        print(
            "FAIL [glyphs] two status marks are not unalike at 16 pt in monochrome — "
            "the doctrine `FocusStatus` states is no longer true of the family that ships",
            file=sys.stderr,
        )
        return 1
    print("GLYPH DISTANCE OK")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
