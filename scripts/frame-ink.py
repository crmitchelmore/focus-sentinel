#!/usr/bin/env python3
"""Measure whether a captured frame has anything **legible** in it.

    scripts/frame-ink.py <frame.png> [<frame.png> …]

Prints one `<path> ink=<value> verdict=<ink|blank>` line per frame and exits non-zero if any
frame is blank.

## Why this exists

`screencapture -l <windowid>` reads a window's **backing store**. A window can render its
content perfectly into a backing store and still be somewhere a person cannot look — a live
drive measured a 380 × 190 nudge panel as a real 380 × 2212 window, captured the question
from its backing store in full, and captured a large blank white slab from the same
coordinates on the actual screen. Three green proofs went green over that. So the live lane
now takes both captures, and something has to be able to say that one of them is empty.

## Why "ink" and not a colour count or a file size

Both of the obvious measures were tried against that drive's own frames and both are wrong:

* the blank on-screen slab is **not** one flat colour — it is a vibrancy blur, so a
  distinct-colour count reads it as rich;
* the blank slab's PNG is **larger** than the readable one's (52 KB vs 36 KB), so file size
  reads the blank frame as the busier of the two.

What separates text from a blur is **local contrast**: glyph edges are high-frequency, a
gradient is not. `ink` is the mean absolute difference between horizontally adjacent
luminance samples, in 0–255 units. Measured on this machine, on real frames:

| frame | ink |
|---|---|
| a 190pt band of the rendered question | **6.70** |
| the menu-bar strip with the ambient glyph (D03) | 5.15 |
| the cockpit (D02) | 3.29 |
| the blank on-screen slab (D06), whose ink is a foreign dialog and the Dock, not the panel | 1.21 |
| the 2212pt backing store (D05) — **readable, but 190 rows of content in 2212** | 0.59 |

## Read the last row before using this on an arbitrary frame

`ink` is a **whole-frame mean**, so a small band of content in a large frame averages away.
That is not a flaw to be tuned around — it is the reason the live lane asserts the panel's
**geometry** first and only then measures its frames. Over a frame that is the size the
surface was supposed to be, this number says whether anything is written on it. Over a frame
of the wrong size it says the surface is the wrong size, which is the same failure.

## The decoder

`sips` converts the PNG to an uncompressed 24-bit BMP, which is a header and a pixel array.
That keeps this file free of any image dependency — no Pillow, no third-party anything — on a
machine where the toolchain is whatever Apple shipped.
"""

import struct
import subprocess
import sys
import tempfile
from pathlib import Path

#: Below this, a frame carries no legible content. It sits in the gap the table in the module
#: docstring measures: every frame with something written on it reads 3.29 or above, and the
#: blank slab reads 1.21 — and the 1.21 is not even the panel, it is a foreign dialog that
#: happened to be inside the same rectangle.
BLANK_INK_THRESHOLD = 2.0


def bmp_pixels(path: Path) -> tuple[int, int, bytes]:
    """(width, height, rows) from a 24- or 32-bit uncompressed BMP."""
    data = path.read_bytes()
    if data[:2] != b"BM":
        raise ValueError(f"{path} is not a BMP")
    offset = struct.unpack_from("<I", data, 10)[0]
    header_size = struct.unpack_from("<I", data, 14)[0]
    width, height = struct.unpack_from("<ii", data, 18)
    depth = struct.unpack_from("<H", data, 28)[0]
    compression = struct.unpack_from("<I", data, 30)[0]
    if header_size < 40 or compression not in (0, 3) or depth not in (24, 32):
        raise ValueError(f"{path}: unsupported BMP ({depth}bpp, compression {compression})")
    return width, abs(height), data[offset:], depth


def ink(path: Path) -> float:
    """Mean absolute luminance difference between horizontally adjacent pixels, 0–255."""
    with tempfile.TemporaryDirectory() as directory:
        bmp = Path(directory) / "frame.bmp"
        subprocess.run(
            ["sips", "-s", "format", "bmp", str(path), "--out", str(bmp)],
            check=True,
            capture_output=True,
        )
        width, height, pixels, depth = bmp_pixels(bmp)

        stride_bytes = depth // 8
        row_bytes = ((width * stride_bytes + 3) // 4) * 4
        total = 0
        samples = 0
        for row in range(height):
            base = row * row_bytes
            if base + row_bytes > len(pixels):
                break
            previous = None
            for column in range(width):
                start = base + column * stride_bytes
                blue, green, red = pixels[start], pixels[start + 1], pixels[start + 2]
                # Rec. 601 luma, integer-weighted: this is a contrast measure, not colour
                # science, and an exact float transform would not change any verdict.
                luma = (red * 299 + green * 587 + blue * 114) // 1000
                if previous is not None:
                    total += abs(luma - previous)
                    samples += 1
                previous = luma
        return total / samples if samples else 0.0


def main(argv: list[str]) -> int:
    if len(argv) < 2:
        print("usage: frame-ink.py <frame.png> [<frame.png> …]", file=sys.stderr)
        return 2

    failed = 0
    for argument in argv[1:]:
        path = Path(argument)
        if not path.is_file():
            print(f"{path} ink=n/a verdict=missing")
            failed = 1
            continue
        try:
            value = ink(path)
        except Exception as error:  # noqa: BLE001 — a frame that cannot be read is a failure
            print(f"{path} ink=n/a verdict=unreadable ({error})")
            failed = 1
            continue
        verdict = "blank" if value < BLANK_INK_THRESHOLD else "ink"
        print(f"{path} ink={value:.2f} verdict={verdict}")
        if verdict == "blank":
            failed = 1
    return failed


if __name__ == "__main__":
    sys.exit(main(sys.argv))
