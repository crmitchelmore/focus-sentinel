// swift-tools-version: 6.2
import PackageDescription

// A TEST DRIVER, not part of the shipping app.
//
// `Tools/` is deliberately outside `Packages/`: this package is not referenced by
// `FocusSentinel.xcodeproj`, nothing in the app links it, and it never appears in the app's
// dependency graph. `scripts/check-boundaries.sh` therefore does not police it and
// `scripts/check-forbidden.sh` excludes it — see the header of that script for why the
// exclusion is safe.
//
// Zero dependencies, like every package in this repository.
let package = Package(
    name: "windowid",
    platforms: [.macOS(.v26)],
    dependencies: [],
    targets: [
        .executableTarget(name: "windowid", path: "Sources/windowid")
    ]
)
