// swift-tools-version: 6.2
import PackageDescription

// FocusSensing owns observation of the Mac: what is frontmost, what changed, and when the
// machine went idle. e03 supplies the adapters; e01 ships the protocol shapes plus a real
// null adapter, so the composition root wires a genuine no-op source rather than an
// unimplemented one.
//
// It may import Foundation, AppKit, CoreGraphics and IOKit, and FocusCore. It may never
// import FocusClassify, FocusRules or FocusUI: observation feeds the engine, never the
// other way round. It may never request `kCGWindowName` — window titles come from the
// Accessibility API with the user's consent, never from the window-list key that has been
// Screen-Recording-gated since 10.15.
//
// `dependencies` contains only local paths to siblings in this repository; there are zero
// external/third-party dependencies.
let package = Package(
    name: "FocusSensing",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "FocusSensing", targets: ["FocusSensing"])
    ],
    dependencies: [
        .package(path: "../FocusCore")
    ],
    targets: [
        .target(
            name: "FocusSensing",
            dependencies: [.product(name: "FocusCore", package: "FocusCore")]
        ),
        .testTarget(
            name: "FocusSensingTests",
            dependencies: ["FocusSensing"]
        )
    ]
)
