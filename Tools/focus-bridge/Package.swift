// swift-tools-version: 6.2
import PackageDescription

// AN AGENT BRIDGE, not part of the shipping app.
//
// `focus-bridge` lets a script or an MCP client (Copilot, Claude) ask Focus Sentinel what the
// person is working on and read their sessions back, without driving the app's UI. It lives in
// `Tools/` for the reason `windowid` does: nothing in the app links it, so it never enters the
// app's dependency graph and never weakens the zero-networking guarantee the app makes.
//
// It is the app's integration host, so the network lives here and not in the app. It listens on
// no socket — the MCP transport is stdio — but when the person has configured task sources it
// calls GitHub over HTTPS (`Tasks/`) to mirror and change their to-do list; the app runs
// `focus-bridge tasks sync` as a subprocess and reads the files it writes. With no task source
// it makes no connection at all. The store is read from a private SQLite backup — never the live
// file — so the running app's data is only ever read.
// The one verb that can change anything, `propose`, opens a `focus://start` URL, and the app
// changes nothing until the person presses Replace in its confirmation sheet.
//
// Zero third-party dependencies, like every package in this repository. `SQLite3` is the
// system library.
let package = Package(
    name: "focus-bridge",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "focus-bridge", targets: ["focus-bridge"])
    ],
    dependencies: [
        .package(path: "../../Packages/FocusCore")
    ],
    targets: [
        .target(
            name: "FocusBridgeKit",
            dependencies: [.product(name: "FocusCore", package: "FocusCore")]
        ),
        .executableTarget(
            name: "focus-bridge",
            dependencies: ["FocusBridgeKit"]
        ),
        .testTarget(
            name: "FocusBridgeKitTests",
            dependencies: ["FocusBridgeKit", .product(name: "FocusCore", package: "FocusCore")]
        )
    ]
)
