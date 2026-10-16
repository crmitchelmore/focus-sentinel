// swift-tools-version: 6.2
import PackageDescription

// AN EVALUATION SPIKE, not part of the shipping app.
//
// It reads real windows through Accessibility — title, document or URL, focused element and the
// visible text — and asks the lane 2 question with that context, on the on-device model and on
// remote chat models, to measure what window content is worth. The owner set R-116 and the
// zero-capture rules aside for this test only (16 October 2026); nothing here is referenced by
// `FocusSentinel.xcodeproj`, and `check-forbidden.sh` / `check-boundaries.sh` do not search
// `Tools/`.
let package = Package(
    name: "ContextSpike",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(name: "ContextSpike", path: "Sources/ContextSpike")
    ]
)
