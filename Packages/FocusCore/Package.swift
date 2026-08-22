// swift-tools-version: 6.2
import PackageDescription

// FocusCore owns the domain: value types, the SwiftData schema, the status token set,
// the appearance traits and the time sources. It imports Foundation, SwiftData and os —
// never AppKit, never SwiftUI, never anything that can open a socket, and never a
// sibling package. The `dependencies` array is empty and must stay empty: the app takes
// zero third-party code.
let package = Package(
    name: "FocusCore",
    defaultLocalization: "en",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "FocusCore", targets: ["FocusCore"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "FocusCore",
            resources: [.process("Resources")]
        ),
        // `.copy("Resources")` — not `.process` — because the SwiftData store fixture is a
        // directory of opaque sqlite files that must reach the bundle byte-for-byte, and
        // because a copied directory keeps its subdirectory structure so that
        // `Bundle.module.url(forResource:withExtension:subdirectory:)` can find it. This is
        // the only route that resolves under both `swift test` and `xcodebuild test`.
        .testTarget(
            name: "FocusCoreTests",
            dependencies: ["FocusCore"],
            resources: [.copy("Resources")]
        )
    ]
)
