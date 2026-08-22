// swift-tools-version: 6.2
import PackageDescription

// FocusUI owns every view, scene, command and design token in the app. The app target is a
// composition root and holds no view code.
//
// It may import SwiftUI, AppKit and FocusCore. It may never import FocusSensing,
// FocusClassify or FocusRules: the UI consumes observable protocol shapes and value types,
// and the app target injects the concrete implementations. That one-way rule is what keeps
// the privacy posture checkable at the dependency-graph level rather than by reading code.
//
// `defaultLocalization` and the processed `Resources` directory are what make the String
// Catalog compile into `en.lproj/Localizable.strings` under xcodebuild and generate typed
// `LocalizedStringResource` symbols.
//
// `dependencies` contains only a local path to a sibling package in this repository; there
// are zero external/third-party dependencies.
let package = Package(
    name: "FocusUI",
    defaultLocalization: "en",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "FocusUI", targets: ["FocusUI"])
    ],
    dependencies: [
        .package(path: "../FocusCore")
    ],
    targets: [
        .target(
            name: "FocusUI",
            dependencies: [.product(name: "FocusCore", package: "FocusCore")],
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "FocusUITests",
            dependencies: ["FocusUI"],
            // The committed snapshot baselines are read from the source tree through
            // `#filePath` — they must be writable when re-recording, which a bundled copy
            // would not be — so they are excluded from the target rather than declared as
            // resources.
            exclude: ["__Snapshots__"]
        )
    ]
)
