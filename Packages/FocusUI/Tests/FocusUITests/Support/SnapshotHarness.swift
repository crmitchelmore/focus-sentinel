import FocusCore
import Foundation
import SwiftUI
import Testing

@testable import FocusUI

/// One render of one component under one set of conditions.
struct Snapshot {
    let name: String
    let data: Data
    let pixels: PixelBuffer

    var width: Int { pixels.width }
    var height: Int { pixels.height }
}

/// The `ImageRenderer` snapshot lane.
///
/// It runs inside the ordinary unit lane: no app host, no window server session of its own,
/// no TCC grant. That is the whole point — every appearance variant and every dynamic-type
/// size is *injected*, so a machine where every accessibility setting is switched off can
/// still render all five variants deterministically, and the running app behaves identically
/// because it is handed the same values by its appearance observer.
///
/// Renders are written to `$FOCUS_SNAPSHOT_OUT` **and** attached to the test result. The
/// directory is what makes evidence capture a plain `cp -R` rather than a dependence on
/// `xcresulttool`'s shifting subcommand surface.
@MainActor
enum SnapshotHarness {
    /// 2×, like every Mac display this app will ever run on.
    static let scale: CGFloat = 2

    /// `FOCUS_SNAPSHOT_RECORD=1` rewrites the committed baselines instead of comparing
    /// against them. The recorded PNGs are then read by eye before being committed.
    ///
    /// Note that `xcodebuild` does **not** forward its own environment to a SwiftPM test
    /// target's process — measured: neither `FOCUS_SNAPSHOT_RECORD=1 xcodebuild test` nor
    /// the documented `TEST_RUNNER_` build-setting prefix reaches the test — so this flag is
    /// usable from `swift test` only. The route that works in the gate lane is deleting a
    /// baseline: a missing baseline is written and then *failed*, so the next run compares
    /// against it and nothing is ever re-recorded silently.
    static var isRecording: Bool {
        ProcessInfo.processInfo.environment["FOCUS_SNAPSHOT_RECORD"] == "1"
    }

    /// Where every render is written, whether or not it matches.
    static let outputDirectory: URL = {
        if let path = ProcessInfo.processInfo.environment["FOCUS_SNAPSHOT_OUT"], !path.isEmpty {
            return URL(filePath: path, directoryHint: .isDirectory)
        }
        return URL(filePath: NSTemporaryDirectory(), directoryHint: .isDirectory)
            .appending(path: "focus-snapshots", directoryHint: .isDirectory)
    }()

    /// The committed baselines, found from this file's own source path.
    ///
    /// `#filePath` rather than `Bundle.module`: the baselines have to be *writable* in the
    /// source tree when recording, and a bundled copy cannot be written back to.
    static let baselineDirectory: URL = URL(filePath: #filePath)
        .deletingLastPathComponent()      // …/Tests/FocusUITests/Support
        .deletingLastPathComponent()      // …/Tests/FocusUITests
        .appending(path: "__Snapshots__", directoryHint: .isDirectory)

    // MARK: - Rendering

    /// Render a component under one set of conditions.
    ///
    /// - Parameters:
    ///   - width: a fixed width, so text wraps rather than the layout growing sideways
    ///     forever. `nil` lets the component size itself, which is what a badge wants.
    ///   - transform: the string transform — `identity` for the shell, the pseudo-locale
    ///     transform for the localisation pass.
    ///   - textScale: how large the shell draws its text. Injected rather than taken from
    ///     `dynamicTypeSize`, which macOS ignores: measured on this machine, an injected
    ///     `dynamicTypeSize` of `.accessibility5` renders a paragraph at exactly the same
    ///     pixel height as `.large` and leaves `@ScaledMetric` untouched.
    static func render(
        _ content: some View,
        traits: AppearanceTraits,
        textScale: ShellTextScale = .standard,
        width: CGFloat? = 520,
        transform: ShellStringTransform = .identity,
        name: String
    ) throws -> Snapshot {
        let subject = content
            .shellStringTransform(transform)
            .appearanceTraits(traits)
            .shellTextScale(textScale)
            .padding(16)
            .frame(width: width)
            .fixedSize(horizontal: width == nil, vertical: true)
            // Painted last, so the whole frame is filled rather than leaving an unpainted
            // margin around a dark render.
            .background(DesignTokens.Palette.windowBackground)

        let renderer = ImageRenderer(content: subject)
        renderer.scale = scale
        renderer.isOpaque = true

        guard let image = renderer.cgImage else {
            throw SnapshotFailure.renderProducedNothing(name)
        }

        let data = try PNGCompare.encode(image)
        let pixels = try PNGCompare.pixels(of: image)
        let snapshot = Snapshot(name: name, data: data, pixels: pixels)

        try write(snapshot)
        Attachment.record(Attachment(data, named: "\(name).png"))
        return snapshot
    }

    /// The canonical file name for a render: `<component>.<variant>.<size>.png`.
    static func name(component: String, variant: String, textScale: String) -> String {
        "\(component).\(variant).\(textScale)"
    }

    // MARK: - Verification

    /// Compare a render against its committed baseline, or record it.
    ///
    /// Recording is never silent: it writes the baseline and returns, and the caller's test
    /// still runs its structural assertions. Reading the recorded PNGs by eye before
    /// committing them is a human step this code cannot do for anyone.
    static func verify(_ snapshot: Snapshot) throws {
        let baselineURL = baselineDirectory.appending(path: "\(snapshot.name).png")

        if isRecording {
            try FileManager.default.createDirectory(
                at: baselineDirectory,
                withIntermediateDirectories: true
            )
            try snapshot.data.write(to: baselineURL, options: .atomic)
            return
        }

        guard let baselineData = try? Data(contentsOf: baselineURL) else {
            // Write the candidate so it can be read by eye, then fail. Recording is never
            // silent: a deleted or forgotten baseline must cost a red run, not pass because
            // the lane obligingly re-recorded whatever the code happens to draw today.
            try FileManager.default.createDirectory(
                at: baselineDirectory,
                withIntermediateDirectories: true
            )
            try snapshot.data.write(to: baselineURL, options: .atomic)
            throw SnapshotFailure.missingBaseline(
                snapshot.name,
                baselineURL.path(percentEncoded: false)
            )
        }

        let baseline = try PNGCompare.decode(baselineData)
        let comparison = PNGCompare.compare(snapshot.pixels, baseline)

        if !comparison.isWithinTolerance {
            // Both sides are attached, so a failure in a log is enough to see what changed.
            Attachment.record(Attachment(baselineData, named: "\(snapshot.name).baseline.png"))
            Attachment.record(Attachment(snapshot.data, named: "\(snapshot.name).candidate.png"))
            throw SnapshotFailure.mismatch(snapshot.name, comparison.summary)
        }
    }

    /// Render and verify in one step.
    @discardableResult
    static func assertSnapshot(
        _ content: some View,
        component: String,
        variant: String,
        textScale: ShellTextScale = .standard,
        width: CGFloat? = 520,
        transform: ShellStringTransform = .identity
    ) throws -> Snapshot {
        let snapshot = try render(
            content,
            traits: variantTraits(named: variant),
            textScale: textScale,
            width: width,
            transform: transform,
            name: name(component: component, variant: variant, textScale: textScale.rawValue)
        )
        try verify(snapshot)
        return snapshot
    }

    static func variantTraits(named variant: String) -> AppearanceTraits {
        guard let match = AppearanceTraits.namedVariants.first(where: { $0.name == variant }) else {
            preconditionFailure("no appearance variant named \(variant)")
        }
        return match.traits
    }

    // MARK: - Evidence

    private static func write(_ snapshot: Snapshot) throws {
        try FileManager.default.createDirectory(
            at: outputDirectory,
            withIntermediateDirectories: true
        )
        try snapshot.data.write(
            to: outputDirectory.appending(path: "\(snapshot.name).png"),
            options: .atomic
        )
    }
}

enum SnapshotFailure: Error, CustomStringConvertible {
    case renderProducedNothing(String)
    case missingBaseline(String, String)
    case mismatch(String, String)

    var description: String {
        switch self {
        case .renderProducedNothing(let name):
            "ImageRenderer produced no image for \(name)"
        case .missingBaseline(let name, let path):
            "no committed baseline for \(name): the candidate has been written to \(path) — read it, then re-run"
        case .mismatch(let name, let summary):
            "\(name) differs from its baseline: \(summary)"
        }
    }
}

/// The two text sizes every component is rendered at: the system's own typography, and
/// roughly twice it. A component that survives both survives everything between them.
enum SnapshotTypeSize: String, CaseIterable {
    case standard
    case accessibilityLarge

    var textScale: ShellTextScale {
        switch self {
        case .standard: .standard
        case .accessibilityLarge: .accessibilityLarge
        }
    }
}
