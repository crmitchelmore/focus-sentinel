#!/usr/bin/env python3
"""Hold the committed app icon to the master it is packaged from.

    scripts/check-appicon.py

## Why the icon needs a check at all

`scripts/make-appicon.sh` is the source and `App/Assets.xcassets/AppIcon.appiconset/*.png` is
its output, committed because the build needs it as an input. Nothing else in the gate reads
the output. A committed PNG that stopped matching its generator — hand-edited, half-regenerated,
or regenerated from a different master — would ship as the app's front door with no stage
noticing, and the icon is the one surface a person sees before they have installed anything.

## What it used to claim, and why that had to change (focus-oqsx)

It described a *mark*: a Spruce centre on a Bench ground, two concentric rings at 128 px and one
at 32, counted as ink edges along the middle line. That was true of the drawn target the
generator used to compose. The identity round replaced it: `make-appicon.sh` now packages the
approved companion master at `Design/CompanionIcon.png`, which is a rendered illustration and
not a mark made of rings and flat palette fills. The old assertions did not become wrong about
the icon — they stayed right about an icon nobody ships. That failure never surfaced, because
the hosted lane the identity work ran under could not start a job.

So the claims are restated against what actually ships. The check is stricter than it was, not
looser: it no longer samples two pixels and counts edges, it compares the picture.

## The three claims

1. **Every size `Contents.json` declares exists, is not empty, and is exactly that many pixels
   square.** A catalogue naming a file nobody wrote fails to build on a machine that has not run
   the generator; a file written at the wrong size is a half-regenerated set, which is the defect
   this check exists for and which no previous claim would have caught.
2. **Each icon is the committed master, packaged.** The master is resampled to the art box the
   generator uses — 88 % of the side — and compared against the inside of the shipped PNG on a
   grid. The statistic is the **median** sampled difference, because a resampler disagreeing with
   `ImageRenderer` about one edge pixel is not a different picture: measured over the three sizes
   here, the median is 1 count per channel while individual high-contrast edges reach 173. A
   picture from a different master moves the median, not the tail.
3. **The mask is applied.** The outer margin is transparent and the middle is opaque, which is
   what says the rounded square was cut rather than the master written out whole.
"""

import json
import struct
import subprocess
import sys
import tempfile
from pathlib import Path

REPOSITORY = Path(__file__).resolve().parent.parent
ICONS = REPOSITORY / "App/Assets.xcassets/AppIcon.appiconset"
MASTER = REPOSITORY / "Design/CompanionIcon.png"

#: The fraction of the canvas the artwork is drawn at, from `make-appicon.sh`'s `AppIcon.art`.
#: Stated in both places because the generator is a heredoc of Swift this cannot import.
ART_FRACTION = 0.88

#: How far the median sampled channel may sit from the master. See claim 2: the measured median
#: is 1, so this is room for a different resampler rather than room for a different picture.
MEDIAN_TOLERANCE = 6

#: The sizes compared against the master. Every declared file is checked for existence and
#: dimensions; three are compared pixel by pixel, which is where the time goes.
COMPARED = ("icon_512x512.png", "icon_128x128.png", "icon_32x32.png")


def pixels(path: Path, resize: int | None = None):
    """(width, height, rows) as 8-bit RGBA, top-down, via `sips` — no image dependency."""
    with tempfile.TemporaryDirectory() as directory:
        source = str(path)
        if resize is not None:
            resized = Path(directory) / "resized.png"
            subprocess.run(
                ["sips", "-z", str(resize), str(resize), source, "--out", str(resized)],
                check=True,
                capture_output=True,
            )
            source = str(resized)
        bmp = Path(directory) / "icon.bmp"
        subprocess.run(
            ["sips", "-s", "format", "bmp", source, "--out", str(bmp)],
            check=True,
            capture_output=True,
        )
        data = bmp.read_bytes()
        offset = struct.unpack_from("<I", data, 10)[0]
        width, height = struct.unpack_from("<ii", data, 18)
        depth = struct.unpack_from("<H", data, 28)[0]
        stride = depth // 8
        row_bytes = ((width * stride + 3) // 4) * 4
        body = data[offset:]
        bottom_up = height > 0
        height = abs(height)
        rows = []
        for row in range(height):
            source_row = (height - 1 - row) if bottom_up else row
            base = source_row * row_bytes
            rows.append(
                [
                    (
                        body[base + c * stride + 2],
                        body[base + c * stride + 1],
                        body[base + c * stride],
                        body[base + c * stride + 3] if stride == 4 else 255,
                    )
                    for c in range(width)
                ]
            )
        return width, height, rows


def declared_sizes():
    """Every filename in `Contents.json` with the pixel side it is declared at."""
    catalogue = json.loads((ICONS / "Contents.json").read_text())
    sizes = {}
    for entry in catalogue["images"]:
        name = entry.get("filename")
        if not name:
            continue
        points = int(entry["size"].split("x")[0])
        scale = int(entry["scale"].rstrip("x"))
        sizes[name] = points * scale
    return sizes


def median_difference(icon, master, side: int):
    """The median per-channel distance between the shipped art and the resampled master.

    Sampled on a grid rather than over every pixel: at 512 that is a quarter of a million
    comparisons through a Python list of tuples, and the median of a few hundred samples spread
    over the art answers the same question.
    """
    art = round(side * ART_FRACTION)
    inset = (side - art) // 2
    step = max(1, art // 24)
    margin = art // 8
    distances = []
    for y in range(margin, art - margin, step):
        for x in range(margin, art - margin, step):
            shipped = icon[y + inset][x + inset]
            # Only where the mask has kept the art: a sample that straddles the rounded edge is
            # comparing the master against nothing.
            if shipped[3] < 250:
                continue
            expected = master[y][x]
            distances.append(max(abs(shipped[c] - expected[c]) for c in range(3)))
    if not distances:
        return None, 0
    distances.sort()
    return distances[len(distances) // 2], len(distances)


def main() -> int:
    failed = 0

    def check(ok, message, detail=""):
        nonlocal failed
        if ok:
            print(f"ok   {message}")
        else:
            print(f"FAIL [appicon] {message}{(' — ' + str(detail)) if detail else ''}")
            failed = 1

    check(MASTER.is_file() and MASTER.stat().st_size > 0, f"the master exists at {MASTER.name}")
    if not MASTER.is_file():
        print("\nAPPICON CHECK FAILED", file=sys.stderr)
        return 1

    sizes = declared_sizes()
    check(bool(sizes), "Contents.json declares at least one image")

    for name, side in sorted(sizes.items()):
        path = ICONS / name
        if not path.is_file() or path.stat().st_size == 0:
            check(False, f"{name} exists and is not empty")
            continue
        check(True, f"{name} exists and is not empty")
        width, height, _ = pixels(path)
        check(
            (width, height) == (side, side),
            f"{name} is {side} x {side} as Contents.json declares it",
            f"{width} x {height}",
        )

    for name in COMPARED:
        path = ICONS / name
        if not path.is_file():
            continue
        side = sizes.get(name)
        if side is None:
            check(False, f"{name} is compared against the master but Contents.json omits it")
            continue
        width, height, icon = pixels(path)
        if (width, height) != (side, side):
            continue
        art = round(side * ART_FRACTION)
        _, _, master = pixels(MASTER, resize=art)
        median, samples = median_difference(icon, master, side)
        check(
            median is not None and median <= MEDIAN_TOLERANCE,
            f"{name} is {MASTER.name} packaged",
            f"median {median} over {samples} samples, tolerance {MEDIAN_TOLERANCE}",
        )
        # The mask: a transparent margin outside the rounded square, opaque art in the middle.
        check(icon[1][1][3] == 0, f"{name}: the outer margin is transparent", icon[1][1])
        check(
            icon[side // 2][side // 2][3] == 255,
            f"{name}: the middle of the art is opaque",
            icon[side // 2][side // 2],
        )

    print()
    if failed:
        print("APPICON CHECK FAILED", file=sys.stderr)
        return 1
    print("APPICON OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
