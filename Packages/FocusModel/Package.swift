// swift-tools-version: 6.2
import PackageDescription

// FocusModel is the ONLY place in this repository that names `FoundationModels`.
//
// Three reasons this is a package and not a file in `FocusClassify` (R-100):
//
//   1. `check-boundaries.sh` pins `ALLOWED_FRAMEWORKS[FocusClassify]` to the literal string
//      `Foundation NaturalLanguage os`, asserted unchanged since e01. That row is a promise
//      about what the module that decides whether to speak is made of. e06 keeping it
//      *literally unchanged* is a stronger statement than e06 re-recording it with a comment.
//   2. The `nm -u FocusClassify.o` zero-networking and no-privacy-symbol scans stay exactly as
//      e04 shipped them. `FocusModel` gets its own row, its own forbidden-import set and its
//      own scans — and the repo-wide networking-symbol scan covers it for free.
//   3. The dependency runs one way. `FocusModel` imports `FocusClassify`; `FocusClassify` does
//      not import `FocusModel`, and cannot, because the port it plugs into is declared in
//      `FocusClassify` itself beside `HeuristicRung`.
//
// `dependencies` contains only local paths to sibling packages in this repository. There are
// zero external/third-party dependencies and there never will be. `FoundationModels` is an
// on-device Apple framework, not a package dependency, and P-150 measured that reaching it
// needs no entitlement, opens no socket and pulls no asset.
let package = Package(
    name: "FocusModel",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "FocusModel", targets: ["FocusModel"])
    ],
    dependencies: [
        .package(path: "../FocusCore"),
        .package(path: "../FocusClassify")
    ],
    targets: [
        .target(
            name: "FocusModel",
            dependencies: [
                .product(name: "FocusClassify", package: "FocusClassify"),
                .product(name: "FocusCore", package: "FocusCore")
            ]
        ),
        .testTarget(
            name: "FocusModelTests",
            dependencies: [
                "FocusModel",
                .product(name: "FocusClassify", package: "FocusClassify"),
                .product(name: "FocusCore", package: "FocusCore")
            ]
        )
    ]
)
