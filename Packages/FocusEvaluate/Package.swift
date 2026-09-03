// swift-tools-version: 6.2
import PackageDescription

// FocusEvaluate owns the evaluation lane and nothing else.
//
// WHY IT IS ITS OWN PACKAGE (e06, review failure 1). `FocusEvaluateCore` and the
// `FocusEvaluate` executable were targets inside `Packages/FocusClassify` from e04. e06 adds
// `FocusModel`, which depends on `FocusClassify` (R-100), and lane 2 of the evaluation needs
// `FocusEvaluate` to depend on `FocusModel`. SwiftPM dependencies are **package**-level, so
// leaving the harness inside FocusClassify would have asked for
// `FocusClassify -> FocusModel -> FocusClassify` and SwiftPM rejects it outright. The cycle is
// not a matter of taste: `FocusClassifyTests` also depended on `FocusEvaluateCore`, so the
// tests had to move with the sources or the cycle would have survived the move.
//
// Nothing here is in the shipping graph. No application target links either product,
// `check-boundaries.sh` asserts that rather than assuming it, and the project file naming an
// evaluation target is itself a gate failure.
//
// `dependencies` contains only local paths to sibling packages in this repository. There are
// zero external/third-party dependencies and there never will be.
let package = Package(
    name: "FocusEvaluate",
    platforms: [.macOS(.v26)],
    products: [
        // The test-lane library. R-75 moves the evaluation harness out of the test target
        // because a harness that lives in a test target can only ever be run by a test, and
        // T103a's `FocusEvaluate` executable and the swift-testing suites both need it.
        .library(name: "FocusEvaluateCore", targets: ["FocusEvaluateCore"]),
        // Emission as a product rather than a test side effect (R-75, T103a). A plain process
        // carries its environment, which `xcodebuild` does not do for a SwiftPM test target —
        // measured twice on this machine — so `$FOCUS_EVAL_OUT` and `$FOCUS_GATE_RUN_ID` only
        // reach the harness through an executable.
        .executable(name: "FocusEvaluate", targets: ["FocusEvaluate"])
    ],
    dependencies: [
        .package(path: "../FocusCore"),
        .package(path: "../FocusRules"),
        .package(path: "../FocusClassify")
    ],
    targets: [
        .target(
            name: "FocusEvaluateCore",
            dependencies: [
                .product(name: "FocusClassify", package: "FocusClassify"),
                .product(name: "FocusCore", package: "FocusCore"),
                .product(name: "FocusRules", package: "FocusRules")
            ]
        ),
        // The executable names all three sibling products even though `main.swift` imports
        // only `FocusCore` and `FocusEvaluateCore`. `check-boundaries.sh` compares
        // `ALLOWED_PRODUCTS[FocusEvaluate]` against the product dependencies of the target
        // named after the package, so this list IS the matrix row — declaring less here would
        // leave the row saying nothing about what the package may reach, and the executable
        // links all three transitively through `FocusEvaluateCore` regardless.
        .executableTarget(
            name: "FocusEvaluate",
            dependencies: [
                "FocusEvaluateCore",
                .product(name: "FocusClassify", package: "FocusClassify"),
                .product(name: "FocusCore", package: "FocusCore"),
                .product(name: "FocusRules", package: "FocusRules")
            ]
        ),
        .testTarget(
            name: "FocusEvaluateTests",
            dependencies: [
                "FocusEvaluateCore",
                .product(name: "FocusClassify", package: "FocusClassify")
            ],
            // `.copy`, never `.process` — the same ruling e02 made for the schema fixtures and
            // for the same reason: a directory of fixtures must reach the bundle with its
            // subdirectory structure intact, so that
            // `url(forResource:withExtension:subdirectory:)` resolves identically under
            // `swift test` and under `xcodebuild test` (R-66).
            resources: [.copy("Resources")]
        )
    ]
)
