#!/usr/bin/env swift
// The Alpha train's app icon, derived from the shipped one (focus-h8jf).
//
//   swift scripts/make-alpha-icon.swift          # write App/Assets.xcassets/AppIconAlpha.appiconset
//   swift scripts/make-alpha-icon.swift --check  # compare, exit 1 on drift
//
// Two installs of the same app on one Mac need two icons a person can tell apart in the Dock,
// and the Alpha one has to say "this is the other one" without a second piece of artwork to
// keep in step with the first. So it is the Stable icon with its hue turned: every Stable PNG
// is read, rotated through `CIHueAdjust`, and written under the same name into the Alpha set,
// with the same `Contents.json`. Re-running this after the Stable icon changes is the whole
// maintenance, and the gate's `glyphs` stage checks the result is what this file draws.
//
// Run with Apple's `swift` from the repository root. It reads and writes PNGs and touches
// nothing else.
import AppKit
import CoreImage

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let source = root.appending(path: "App/Assets.xcassets/AppIcon.appiconset")
let target = root.appending(path: "App/Assets.xcassets/AppIconAlpha.appiconset")
let check = CommandLine.arguments.contains("--check")
/// Teal to violet: far enough round the wheel that the two icons never read as one family's
/// light and dark, near enough that the mark is still recognisably this app's.
let hueTurn: Float = 1.9

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

func rotated(_ data: Data) -> Data {
    guard let input = CIImage(data: data) else { fail("a Stable icon PNG did not decode") }
    guard let filter = CIFilter(name: "CIHueAdjust") else { fail("CIHueAdjust is unavailable") }
    filter.setValue(input, forKey: kCIInputImageKey)
    filter.setValue(hueTurn, forKey: kCIInputAngleKey)
    guard let output = filter.outputImage else { fail("CIHueAdjust produced nothing") }
    let context = CIContext(options: [.outputColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!])
    guard let png = context.pngRepresentation(
        of: output,
        format: .RGBA8,
        colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!
    ) else { fail("the rotated icon did not encode") }
    return png
}

let files = try FileManager.default.contentsOfDirectory(atPath: source.path)
    .filter { $0.hasSuffix(".png") || $0 == "Contents.json" }
    .sorted()
if files.isEmpty { fail("no Stable icon at \(source.path)") }

var drifted: [String] = []
if !check {
    try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
}
for name in files {
    let bytes = try Data(contentsOf: source.appending(path: name))
    let rendered = name == "Contents.json" ? bytes : rotated(bytes)
    let destination = target.appending(path: name)
    if check {
        let existing = try? Data(contentsOf: destination)
        if existing != rendered { drifted.append(name) }
    } else {
        try rendered.write(to: destination)
    }
}

if check {
    if drifted.isEmpty {
        print("ok   AppIconAlpha.appiconset is what make-alpha-icon.swift draws (\(files.count) files)")
    } else {
        fail("FAIL AppIconAlpha.appiconset has drifted: \(drifted.joined(separator: ", ")); re-run scripts/make-alpha-icon.swift")
    }
} else {
    print("wrote \(files.count) files to \(target.path)")
}
