#!/bin/zsh
# Render the app icon.
#
#   scripts/make-appicon.sh
#
# The icon is *generated*, not drawn by hand in an image editor: this script is the source,
# and `App/Assets.xcassets/AppIcon.appiconset/*.png` is its output, committed because the
# build needs it as an input. Running it again on the same machine reproduces the same bytes
# — the mark is drawn from fixed geometry and from system colours resolved explicitly in the
# aqua appearance, so nothing about the renderer's environment (the user's own light/dark
# setting, their accent colour) can leak into the file.
#
# The mark: concentric rings around a filled centre — the same ring the five status marks are
# drawn from, which is what the app is *for*: one thing in the middle, everything else arranged
# around it.
#
# THE PALETTE IS RESOLVED HERE, EXPLICITLY, AND THAT IS A KNOWN SEAM (focus-w41, e11 plan review).
# This script is standalone: it compiles a renderer with `swiftc` and has no access to FocusUI's
# bundle, so it cannot read `Palette.xcassets` and the six roles cannot be single-sourced across
# the boundary. The hexes below are therefore written twice — here and in
# `DesignTokens.Palette.Role` — and the second spelling is named in each comment so a person
# changing one can find the other. It is a smaller price than the alternatives: making the icon
# depend on a built package, or leaving the app's own front door in the system's aqua gradient
# while every other surface moved.
#
# WHY IT IS THE ONE SURFACE WITH A FACE. The icon is only ever seen when it is summoned — in the
# Dock, in a Finder window, in the launcher a person typed into. §6 of the direction spends the
# whole personality budget on exactly those surfaces and none of it on the uninvited ones.
set -u

REPO_ROOT="${0:A:h}/.."
cd "$REPO_ROOT" || exit 1

OUT="App/Assets.xcassets/AppIcon.appiconset"
WORK="$(mktemp -d -t focus-appicon)"
trap 'rm -rf -- "$WORK"' EXIT

mkdir -p -- "$OUT"

cat > "$WORK/render.swift" <<'SWIFT'
import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

/// One of the app's own palette roles, as an opaque sRGB colour.
///
/// Written as literal components rather than resolved from a system colour, and that is the
/// change e11b made: the icon used to be `systemTeal` over `systemBlue`, which is the platform's
/// gradient rather than the app's mark. There is nothing to resolve against an appearance here —
/// these are the light values of `DesignTokens.Palette.Role`, and an icon has no dark mode.
/// "Same inputs, same bytes" is therefore stronger than it was, not weaker: nothing about the
/// machine can reach these numbers at all.
func palette(_ red: Int, _ green: Int, _ blue: Int) -> Color {
    Color(
        nsColor: NSColor(
            srgbRed: CGFloat(red) / 255,
            green: CGFloat(green) / 255,
            blue: CGFloat(blue) / 255,
            alpha: 1
        )
    )
}

/// Bench — the ground. `DesignTokens.Palette.Role.bench`, light value `#F2F4F3`.
let bench = palette(0xF2, 0xF4, 0xF3)
/// Slate — the ink the rings are drawn in. `Role.slate`, light value `#1E2427`.
let slate = palette(0x1E, 0x24, 0x27)
/// Spruce — the centre, and the one hue on the icon. `Role.spruce`, light value `#176B73`.
let spruce = palette(0x17, 0x6B, 0x73)

/// The mark, drawn in a 1×1 unit square and scaled to whatever size is being rendered.
struct AppIcon: View {
    let side: CGFloat

    /// Below this many pixels the inner ring is not drawn at all.
    ///
    /// **Measured against the stroke, not chosen.** The inner ring is 5.5 % of the art wide and
    /// sits 11 % from the outer one; at 64 px that stroke is 3.2 px and the gap is 6 px, which
    /// still reads. At 32 px it is 1.6 px against a 3 px gap and the two rings merge into one
    /// thick smudge with a dot in it — worse than one ring, because it loses the ring *and* the
    /// centre. So below 64 the mark drops to what survives: one ring, and a centre grown to hold
    /// the middle on its own. The canvas says this in as many words at its 32 px cell.
    static let innerRingFloor: CGFloat = 64

    var body: some View {
        let inset = side * 0.06
        let art = side - inset * 2
        let drawsInnerRing = side >= Self.innerRingFloor

        ZStack {
            // macOS icons carry their own shape: a continuous-curvature rounded square with
            // a little breathing room inside the canvas.
            RoundedRectangle(cornerRadius: art * 0.2237, style: .continuous)
                .fill(bench)
                .frame(width: art, height: art)

            // Two rings and a centre: the target the app keeps you pointed at. Slate rather than
            // white-on-a-gradient, so the mark is the same ink as the menu-bar marks and the
            // panels' text — one ring, in one colour, everywhere the app draws itself.
            Circle()
                .stroke(slate, lineWidth: art * 0.045)
                .frame(width: art * 0.62, height: art * 0.62)
            if drawsInnerRing {
                Circle()
                    .stroke(slate.opacity(0.55), lineWidth: art * 0.055)
                    .frame(width: art * 0.40, height: art * 0.40)
            }
            // The one hue on the icon, and it is the question's: Spruce is what the app is for —
            // the thing in the middle everything else is arranged around.
            Circle()
                .fill(spruce)
                .frame(
                    width: art * (drawsInnerRing ? 0.17 : 0.26),
                    height: art * (drawsInnerRing ? 0.17 : 0.26)
                )
        }
        .frame(width: side, height: side)
    }
}

@MainActor
func render(side: Int, to path: String) {
    let renderer = ImageRenderer(content: AppIcon(side: CGFloat(side)))
    renderer.scale = 1
    renderer.isOpaque = false

    guard let image = renderer.cgImage else {
        FileHandle.standardError.write(Data("FAILED to render \(side)px\n".utf8))
        exit(1)
    }

    let url = URL(fileURLWithPath: path)
    guard
        let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        )
    else {
        FileHandle.standardError.write(Data("FAILED to open \(path)\n".utf8))
        exit(1)
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        FileHandle.standardError.write(Data("FAILED to write \(path)\n".utf8))
        exit(1)
    }
    print("wrote \(path) (\(side)px)")
}

// name -> pixel side. One file per asset-catalog entry, named the way Xcode names them.
let outputs: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

MainActor.assumeIsolated {
    let directory = CommandLine.arguments[1]
    for (name, side) in outputs {
        render(side: side, to: "\(directory)/\(name)")
    }
}
SWIFT

print "== compiling the renderer"
swiftc -O "$WORK/render.swift" -o "$WORK/render" || exit 1

print "== rendering into $OUT"
"$WORK/render" "$OUT" || exit 1

print "== writing Contents.json"
cat > "$OUT/Contents.json" <<'JSON'
{
  "images" : [
    {
      "filename" : "icon_16x16.png",
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "16x16"
    },
    {
      "filename" : "icon_16x16@2x.png",
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "16x16"
    },
    {
      "filename" : "icon_32x32.png",
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "32x32"
    },
    {
      "filename" : "icon_32x32@2x.png",
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "32x32"
    },
    {
      "filename" : "icon_128x128.png",
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "128x128"
    },
    {
      "filename" : "icon_128x128@2x.png",
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "128x128"
    },
    {
      "filename" : "icon_256x256.png",
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "256x256"
    },
    {
      "filename" : "icon_256x256@2x.png",
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "256x256"
    },
    {
      "filename" : "icon_512x512.png",
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "512x512"
    },
    {
      "filename" : "icon_512x512@2x.png",
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "512x512"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
JSON

mkdir -p -- App/Assets.xcassets
cat > App/Assets.xcassets/Contents.json <<'JSON'
{
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
JSON

print
print "APPICON OK — $(ls -1 "$OUT" | wc -l | tr -d ' ') files in $OUT"
