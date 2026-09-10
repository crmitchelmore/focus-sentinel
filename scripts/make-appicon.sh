#!/bin/zsh
# Render the app icon.
#
#   scripts/make-appicon.sh
#
# Package the approved companion master at every macOS icon size. The source lives at
# Design/CompanionIcon.png; runtime/builds never ask an image service for new artwork.
# SwiftUI supplies the standard macOS rounded-square mask and transparent outer margin.
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

struct AppIcon: View {
    let side: CGFloat
    let artwork: NSImage
    var body: some View {
        let art = side * 0.88
        Image(nsImage: artwork)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: art, height: art)
            .clipShape(RoundedRectangle(cornerRadius: art * 0.2237, style: .continuous))
            .frame(width: side, height: side)
    }
}

@MainActor
func render(side: Int, to path: String) {
    guard let artwork = NSImage(contentsOfFile: CommandLine.arguments[2]) else {
        fatalError("The companion icon source could not be loaded")
    }
    let renderer = ImageRenderer(content: AppIcon(side: CGFloat(side), artwork: artwork))
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
"$WORK/render" "$OUT" "$REPO_ROOT/Design/CompanionIcon.png" || exit 1

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
