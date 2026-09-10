// swift-tools-version: 6.2
import PackageDescription

// FocusUpdates is the one package in this repository that may reach the network, and it may
// reach it for one purpose: asking a Sparkle appcast whether a newer build exists, when the
// person has switched that on (focus-h8jf).
//
// ## The one third-party dependency
//
// Every other `Package.swift` here declares local siblings only, and `check-boundaries.sh`
// fails the gate for a remote dependency anywhere but this package. Sparkle is here because
// the owner asked for a release train the app can update itself from, and because an updater
// written in-house would be more code doing the same thing with less scrutiny. The package
// pins a version rather than a branch, and the framework is the only code the shipped bundle
// carries outside `Contents/MacOS`.
//
// ## What confines it
//
// It may import Foundation, AppKit, Sparkle and FocusCore, and nothing else: no view, no store,
// no sensing. `SparkleUpdater` is inert until `setAutomaticChecks(true)` or `checkForUpdates()`
// is called — `SPUStandardUpdaterController` is built with `startingUpdater: false` — so a
// default install opens no socket, which the gate's `boundaries` stage reads off the product:
// the framework is linked, `SUEnableAutomaticChecks` is `false`, and no `SUFeedURL` is in the
// plist because the feed is the train's and is supplied by the delegate.
let package = Package(
    name: "FocusUpdates",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "FocusUpdates", targets: ["FocusUpdates"])
    ],
    dependencies: [
        .package(path: "../FocusCore"),
        .package(url: "https://github.com/sparkle-project/Sparkle.git", from: "2.9.6")
    ],
    targets: [
        .target(
            name: "FocusUpdates",
            dependencies: [
                .product(name: "FocusCore", package: "FocusCore"),
                .product(name: "Sparkle", package: "Sparkle")
            ]
        ),
        .testTarget(
            name: "FocusUpdatesTests",
            dependencies: ["FocusUpdates"]
        )
    ]
)
