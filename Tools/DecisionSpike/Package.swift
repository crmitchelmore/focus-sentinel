// swift-tools-version: 6.2
import PackageDescription

// AN EVALUATION SPIKE, not part of the shipping app.
//
// It asks a remote decision model (Microsoft-Decision-1 on Azure AI Foundry) the lane 2
// question and folds the answers through the same `ModelEvaluationHarness` the on-device tier
// is measured with, so the two tiers are compared on the committed model corpus with the same
// buckets and the same budget of zero seductions.
//
// It lives in `Tools/` because it opens a network connection. `Packages/*/Sources` may not name
// `URLSession` (check-boundaries.sh), and nothing here is referenced by
// `FocusSentinel.xcodeproj` or linked by the app. The dependencies are local paths only.
let package = Package(
    name: "DecisionSpike",
    platforms: [.macOS(.v26)],
    dependencies: [
        .package(path: "../../Packages/FocusCore"),
        .package(path: "../../Packages/FocusClassify"),
        .package(path: "../../Packages/FocusEvaluate")
    ],
    targets: [
        .executableTarget(
            name: "DecisionSpike",
            dependencies: [
                .product(name: "FocusCore", package: "FocusCore"),
                .product(name: "FocusClassify", package: "FocusClassify"),
                .product(name: "FocusEvaluateCore", package: "FocusEvaluate")
            ],
            path: "Sources/DecisionSpike"
        )
    ]
)
