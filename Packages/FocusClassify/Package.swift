// swift-tools-version: 6.2
import PackageDescription

// FocusClassify owns the classification seam and nothing else in e01.
//
// The point of standing it up now, near-empty, is that its zero-networking guarantee is
// *instituted* rather than retrofitted: from the first commit this package may not import
// Network, CFNetwork or URLSession-bearing Foundation networking, may not import AppKit or
// SwiftUI, and may not reach sideways into FocusSensing or FocusUI. The assertion is
// already failing-closed in `scripts/check-boundaries.sh` — a source-import lint, a
// dependency-graph assertion over `swift package describe --type json`, and an `nm -u`
// symbol scan of the built object.
//
// `dependencies` contains only local paths to sibling packages in this repository. There
// are zero external/third-party dependencies and there never will be. `FoundationModels`
// arrives in e06; it is an on-device Apple framework, not a package dependency.
let package = Package(
    name: "FocusClassify",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "FocusClassify", targets: ["FocusClassify"])
    ],
    dependencies: [
        .package(path: "../FocusCore"),
        .package(path: "../FocusRules")
    ],
    targets: [
        .target(
            name: "FocusClassify",
            dependencies: [
                .product(name: "FocusCore", package: "FocusCore"),
                .product(name: "FocusRules", package: "FocusRules")
            ]
        ),
        .testTarget(
            name: "FocusClassifyTests",
            dependencies: ["FocusClassify"],
            // `.copy`, never `.process` — the same ruling e02 made for the schema fixtures and
            // for the same reason: a directory of fixtures must reach the bundle with its
            // subdirectory structure intact, so that
            // `url(forResource:withExtension:subdirectory:)` resolves identically under
            // `swift test` and under `xcodebuild test` (R-66).
            resources: [.copy("Resources")]
        )
    ]
)
