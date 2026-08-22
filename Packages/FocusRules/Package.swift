// swift-tools-version: 6.2
import PackageDescription

// FocusRules owns the typed rule model and the rule-store protocol. It imports Foundation
// and FocusCore, and nothing else — no AppKit, no SwiftUI, no networking, no sibling
// engine package.
//
// The only entry in `dependencies` is a **local path** to a sibling package in this
// repository. There are, and must remain, zero external/third-party dependencies: no URL,
// no registry identity, no vendored source. `scripts/check-boundaries.sh` asserts exactly
// that, and asserts that the set of local dependencies matches the published import
// matrix.
let package = Package(
    name: "FocusRules",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "FocusRules", targets: ["FocusRules"])
    ],
    dependencies: [
        .package(path: "../FocusCore")
    ],
    targets: [
        .target(
            name: "FocusRules",
            dependencies: [.product(name: "FocusCore", package: "FocusCore")]
        ),
        .testTarget(
            name: "FocusRulesTests",
            dependencies: ["FocusRules"]
        )
    ]
)
