// swift-tools-version: 6.2
import PackageDescription

// FocusHost is the composition layer: the objects that turn the five packages into a running
// application. `AppComposition` chooses the implementations, and the five hosts —
// `NudgeHost`, `RelevanceHost`, `SensingHost`, `SessionHost`, `PriorityHost` — hold the
// lifetimes that a value type cannot.
//
// ## Why this is a package and not the app target
//
// It used to be the app target, and that made it unreachable. `xcodebuild test` runs test
// bundles, and there was no test bundle that could see `App/` — so every claim about the
// wiring in this layer was made by a test that read the *source text* of `App/*.swift` and
// looked for the substrings the wiring happened to be spelled with. Three separate mutations
// to `NudgeHost` — including one that replaced a readability reading with a constant
// `.readable` — left 1 115 tests green, because the spelling was still there.
//
// A package has a test target. `FocusHostTests` instantiates `NudgeHost` against the real
// `NudgePanelController` and the real `MenuBarController` and drives it, so the wiring is
// asserted by running it. Nothing about the layer's *responsibilities* changed: it is still
// the only place that imports more than one sibling package, and it still decides nothing —
// `NudgeDecider` decides.
//
// The app target keeps what only an app can own: `@main`, the scenes, the entitlements, the
// icon and the appearance observer. It reaches this package through a deliberately narrow
// surface on `AppComposition` rather than through the hosts themselves.
//
// It may import Foundation, AppKit, SwiftData, Observation and os, and all five sibling
// packages — it is the layer whose whole job is to know them all at once. It may never import
// SwiftUI: views belong to FocusUI, and a composition root that could declare one would be a
// second place surfaces are written.
//
// `dependencies` contains only local paths to siblings in this repository; there are zero
// external/third-party dependencies.
let package = Package(
    name: "FocusHost",
    defaultLocalization: "en",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "FocusHost", targets: ["FocusHost"])
    ],
    dependencies: [
        .package(path: "../FocusCore"),
        .package(path: "../FocusRules"),
        .package(path: "../FocusClassify"),
        // e06. The composition layer is the only place that knows whether a model tier exists:
        // `FocusClassify` declares the port and imports no implementation of it, so the one
        // module permitted every sibling is the one that plugs the two together.
        .package(path: "../FocusModel"),
        .package(path: "../FocusSensing"),
        .package(path: "../FocusUI")
    ],
    targets: [
        .target(
            name: "FocusHost",
            dependencies: [
                .product(name: "FocusCore", package: "FocusCore"),
                .product(name: "FocusRules", package: "FocusRules"),
                .product(name: "FocusClassify", package: "FocusClassify"),
                .product(name: "FocusModel", package: "FocusModel"),
                .product(name: "FocusSensing", package: "FocusSensing"),
                .product(name: "FocusUI", package: "FocusUI")
            ],
            // The composition layer owns no user-visible text — `check-strings.sh` asserts the
            // catalog is empty — but it must still be a localised bundle, because the app's
            // `en.lproj` is assembled from the packages that declare one.
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "FocusHostTests",
            dependencies: ["FocusHost"]
        )
    ]
)
