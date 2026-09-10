import Foundation

/// Where the snapshot lane's wall time actually goes.
///
/// This is a *reported metric*, not an assertion. The phase table is printed to stderr once at
/// process exit, so the gate's own unit-lane log carries the witness this bead is measured by —
/// what the snapshot lane spent, split by phase — rather than only a wall time that says
/// nothing about where it went. `FOCUS_SNAPSHOT_METRICS=0` silences it; the two clock reads
/// per phase are noise against a render.
///
/// Every counter is written from the main actor only — `SnapshotHarness` is `@MainActor` and
/// every call site is inside it — and read once, after the last test has finished, from the
/// `atexit` handler. That is why the storage is `nonisolated(unsafe)`: the isolation is real,
/// it just is not expressible on a global the exit handler has to reach.
enum SnapshotMetrics {
    static let isEnabled = ProcessInfo.processInfo.environment["FOCUS_SNAPSHOT_METRICS"] != "0"

    /// One measured phase of a render-and-verify.
    enum Phase: String, CaseIterable {
        /// `ImageRenderer.cgImage`, under the traits' own AppKit appearance.
        case render
        /// PNG-encoding the render.
        case encode
        /// Redrawing the render into RGBA8.
        case pixels
        /// Writing the render to `FOCUS_SNAPSHOT_OUT` and attaching it to the result.
        case write
        /// Reading the committed baseline off disk.
        case baselineRead
        /// Decoding the committed baseline into RGBA8.
        case baselineDecode
        /// The two ink scans.
        case ink
        /// The per-channel comparison.
        case compare
    }

    nonisolated(unsafe) private static var nanoseconds = [Int64](
        repeating: 0,
        count: Phase.allCases.count
    )
    nonisolated(unsafe) private static var counts = [Int64](
        repeating: 0,
        count: Phase.allCases.count
    )
    /// Verifications that matched the baseline byte for byte and never decoded it.
    nonisolated(unsafe) static var fastPathHits: Int64 = 0
    /// Verifications that fell through to the full pixel comparison.
    nonisolated(unsafe) static var fastPathMisses: Int64 = 0

    nonisolated(unsafe) private static var handlerInstalled = false

    /// Time one phase. When metrics are off this is the closure and nothing else.
    @inline(__always)
    static func measure<T>(_ phase: Phase, _ body: () throws -> T) rethrows -> T {
        guard isEnabled else { return try body() }
        installHandler()
        let start = DispatchTime.now().uptimeNanoseconds
        defer {
            let elapsed = DispatchTime.now().uptimeNanoseconds - start
            nanoseconds[phase.rawValueIndex] += Int64(elapsed)
            counts[phase.rawValueIndex] += 1
        }
        return try body()
    }

    static func note(_ counter: inout Int64) {
        guard isEnabled else { return }
        installHandler()
        counter += 1
    }

    private static func installHandler() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        atexit(snapshotMetricsDump)
    }

    static func report() -> String {
        var lines = ["", "=== snapshot lane phase totals ==="]
        var grandTotal = 0.0
        for phase in Phase.allCases {
            let seconds = Double(nanoseconds[phase.rawValueIndex]) / 1_000_000_000
            let count = counts[phase.rawValueIndex]
            grandTotal += seconds
            guard count > 0 else { continue }
            let each = seconds / Double(count) * 1000
            let label = phase.rawValue.padding(toLength: 16, withPad: " ", startingAt: 0)
            lines.append(
                label + String(format: "%9.2f s  n=%-6d  %8.2f ms each", seconds, Int(count), each)
            )
        }
        lines.append(
            "TOTAL".padding(toLength: 16, withPad: " ", startingAt: 0)
                + String(format: "%9.2f s", grandTotal)
        )
        lines.append("baseline fast-path hits \(fastPathHits), misses \(fastPathMisses)")
        lines.append("=== end snapshot lane phase totals ===")
        return lines.joined(separator: "\n") + "\n"
    }
}

extension SnapshotMetrics.Phase {
    fileprivate var rawValueIndex: Int {
        SnapshotMetrics.Phase.allCases.firstIndex(of: self) ?? 0
    }
}

/// The `atexit` handler, at file scope because a C function pointer cannot be formed from a
/// closure that captures anything — including an enclosing type.
private func snapshotMetricsDump() {
    FileHandle.standardError.write(Data(SnapshotMetrics.report().utf8))
}
