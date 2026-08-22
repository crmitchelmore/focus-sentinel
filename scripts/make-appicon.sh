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
# The mark: concentric rings around a filled centre — the silhouette family of the `relevant`
# status token (`checkmark.circle.fill`), which is what the app is *for*: one thing in the
# middle, everything else arranged around it.
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

/// A system colour, resolved in the aqua appearance and pinned to sRGB.
///
/// Without this the icon would depend on whatever appearance the machine happened to be in
/// when the script ran, and "same inputs, same bytes" would be false.
@MainActor
func fixed(_ color: NSColor) -> Color {
    var resolved = color
    NSAppearance(named: .aqua)?.performAsCurrentDrawingAppearance {
        resolved = color.usingColorSpace(.sRGB) ?? color
    }
    return Color(nsColor: resolved)
}

/// The mark, drawn in a 1×1 unit square and scaled to whatever size is being rendered.
struct AppIcon: View {
    let side: CGFloat

    var body: some View {
        let inset = side * 0.06
        let art = side - inset * 2

        ZStack {
            // macOS icons carry their own shape: a continuous-curvature rounded square with
            // a little breathing room inside the canvas.
            RoundedRectangle(cornerRadius: art * 0.2237, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [fixed(.systemTeal), fixed(.systemBlue)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: art, height: art)

            // Two rings and a centre: the target the app keeps you pointed at.
            Circle()
                .stroke(Color.white.opacity(0.55), lineWidth: art * 0.045)
                .frame(width: art * 0.62, height: art * 0.62)
            Circle()
                .stroke(Color.white.opacity(0.8), lineWidth: art * 0.055)
                .frame(width: art * 0.40, height: art * 0.40)
            Circle()
                .fill(Color.white)
                .frame(width: art * 0.17, height: art * 0.17)
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
