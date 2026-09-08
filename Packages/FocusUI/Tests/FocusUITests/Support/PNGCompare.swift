import CoreGraphics
import FocusUI
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// A decoded image, as straight RGBA bytes.
///
/// Comparison happens on pixels, never on file bytes: two PNG encodings of the same image
/// can differ byte-for-byte and still be the same picture, and a test that fails for that
/// reason teaches people to delete the test.
struct PixelBuffer: Equatable {
    let width: Int
    let height: Int
    /// Row-major RGBA, 8 bits per channel, premultiplied-last — the one format every image
    /// here is redrawn into so that comparison never has to reason about colour spaces.
    let bytes: [UInt8]

    var isEmpty: Bool { width == 0 || height == 0 }
}

/// The result of comparing two renders.
struct PixelComparison {
    let dimensionsMatch: Bool
    /// Mean absolute per-channel difference, in 0–255 units.
    let meanAbsoluteDifference: Double
    /// Proportion of pixels where any channel differs by more than the noise threshold.
    let proportionBeyondThreshold: Double

    /// The tolerance the snapshot lane holds itself to.
    ///
    /// Anti-aliasing and font rasterisation move a handful of edge pixels between runs; a
    /// changed colour, a changed layout or a missing string move far more than that. The two
    /// numbers together are what separate those cases: a small mean says "nothing moved much
    /// anywhere", the proportion says "and nothing moved a lot in a few places".
    static let meanTolerance = 2.0 / 255.0 * 255.0
    static let channelThreshold = 8.0
    static let proportionTolerance = 0.002

    var isWithinTolerance: Bool {
        dimensionsMatch
            && meanAbsoluteDifference <= Self.meanTolerance
            && proportionBeyondThreshold <= Self.proportionTolerance
    }

    var summary: String {
        String(
            format: "dimensions %@, mean |Δ| %.3f (≤ %.3f), pixels beyond ±%.0f: %.4f%% (≤ %.4f%%)",
            dimensionsMatch ? "match" : "DIFFER",
            meanAbsoluteDifference,
            Self.meanTolerance,
            Self.channelThreshold,
            proportionBeyondThreshold * 100,
            Self.proportionTolerance * 100
        )
    }
}

enum PNGCompare {
    enum Failure: Error, CustomStringConvertible {
        case notAnImage
        case cannotEncode

        var description: String {
            switch self {
            case .notAnImage: "the data could not be decoded as an image"
            case .cannotEncode: "the image could not be encoded as PNG"
            }
        }
    }

    /// Decode PNG data and redraw it into a known RGBA layout.
    static func decode(_ data: Data) throws -> PixelBuffer {
        guard
            let source = CGImageSourceCreateWithData(data as CFData, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            throw Failure.notAnImage
        }
        return try pixels(of: image)
    }

    /// Redraw a `CGImage` into row-major RGBA8.
    static func pixels(of image: CGImage) throws -> PixelBuffer {
        let width = image.width
        let height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)

        guard
            let context = bytes.withUnsafeMutableBytes({ buffer -> CGContext? in
                CGContext(
                    data: buffer.baseAddress,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: width * 4,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                )
            })
        else {
            throw Failure.notAnImage
        }

        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return PixelBuffer(width: width, height: height, bytes: bytes)
    }

    /// Encode a `CGImage` as PNG data.
    static func encode(_ image: CGImage) throws -> Data {
        let data = NSMutableData()
        guard
            let destination = CGImageDestinationCreateWithData(
                data as CFMutableData,
                UTType.png.identifier as CFString,
                1,
                nil
            )
        else {
            throw Failure.cannotEncode
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw Failure.cannotEncode }
        return data as Data
    }

    /// Compare two decoded renders.
    static func compare(_ candidate: PixelBuffer, _ baseline: PixelBuffer) -> PixelComparison {
        guard
            candidate.width == baseline.width,
            candidate.height == baseline.height,
            !candidate.isEmpty
        else {
            return PixelComparison(
                dimensionsMatch: false,
                meanAbsoluteDifference: .infinity,
                proportionBeyondThreshold: 1
            )
        }

        var total = 0.0
        var beyond = 0
        let pixelCount = candidate.width * candidate.height

        for pixel in 0..<pixelCount {
            var exceeded = false
            for channel in 0..<4 {
                let index = pixel * 4 + channel
                let delta = abs(Int(candidate.bytes[index]) - Int(baseline.bytes[index]))
                total += Double(delta)
                if Double(delta) > PixelComparison.channelThreshold { exceeded = true }
            }
            if exceeded { beyond += 1 }
        }

        return PixelComparison(
            dimensionsMatch: true,
            meanAbsoluteDifference: total / Double(pixelCount * 4),
            proportionBeyondThreshold: Double(beyond) / Double(pixelCount)
        )
    }

    /// How much of a render is ink rather than background.
    ///
    /// The background is taken from the top-left pixel, which every render in this lane
    /// paints deliberately. Counting ink is how "the text really reached the view" and "the
    /// text was not silently dropped" are measured on a layout that has slack in it: a
    /// component with room to spare keeps its frame when its strings grow, but it cannot
    /// keep the same amount of ink.
    ///
    /// **`paper` names any further ground that is not ink** (focus-6uya). The cockpit draws two
    /// of its zones on an Inlay well, and against the top-left Bench pixel a well is a solid
    /// block of "ink" — so text drawn *on* the well adds nothing the measure can see, and a
    /// pseudo-localised cockpit measured fewer ink pixels than the plain one while visibly
    /// drawing more text. A caller that knows the render stands on a second ground passes it
    /// here, and a pixel near either ground is paper. The default is the old measure exactly.
    static func inkPixels(_ buffer: PixelBuffer, paper: [DesignTokens.PaletteValue] = []) -> Int {
        guard !buffer.isEmpty else { return 0 }
        let threshold = Int(PixelComparison.channelThreshold)
        var grounds = [(Int(buffer.bytes[0]), Int(buffer.bytes[1]), Int(buffer.bytes[2]))]
        grounds += paper.map { ($0.red, $0.green, $0.blue) }
        var ink = 0
        for pixel in 0..<(buffer.width * buffer.height) {
            let index = pixel * 4
            let r = Int(buffer.bytes[index])
            let g = Int(buffer.bytes[index + 1])
            let b = Int(buffer.bytes[index + 2])
            let onPaper = grounds.contains { ground in
                max(abs(r - ground.0), max(abs(g - ground.1), abs(b - ground.2))) <= threshold
            }
            if !onPaper { ink += 1 }
        }
        return ink
    }

    /// Whether two renders are different pictures rather than the same one twice.
    ///
    /// Used by the cross-variant assertions: a component that claims to honour dark mode and
    /// renders identically in light and dark is not honouring it.
    static func areDistinct(_ first: PixelBuffer, _ second: PixelBuffer) -> Bool {
        let comparison = compare(first, second)
        return !comparison.dimensionsMatch || !comparison.isWithinTolerance
    }
}
