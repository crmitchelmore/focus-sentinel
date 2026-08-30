import Foundation
import Testing

@testable import FocusUI

/// A workspace that answers whatever the test tells it to, and records what it was asked.
@MainActor
final class StubReturnWorkspace: ReturnWorkspace {
    var runningNames: [String: String] = [:]
    var installedURLs: [String: URL] = [:]
    var activationSucceeds = true
    var launchSucceeds = true

    private(set) var activations: [String] = []
    private(set) var launches: [URL] = []
    /// Every identifier a name was asked for, in order — so "the name is learned once and kept"
    /// is a count rather than a claim (`SubjectNamingTests`).
    private(set) var lookups: [String] = []

    func localizedNameOfRunningApplication(_ bundleIdentifier: String) -> String? {
        lookups.append(bundleIdentifier)
        return runningNames[bundleIdentifier]
    }

    func activateRunningApplication(_ bundleIdentifier: String) -> Bool {
        activations.append(bundleIdentifier)
        return activationSucceeds
    }

    func applicationURL(for bundleIdentifier: String) -> URL? {
        installedURLs[bundleIdentifier]
    }

    func openApplication(at url: URL, completion: @escaping @MainActor (Bool) -> Void) {
        launches.append(url)
        completion(launchSucceeds)
    }
}

/// **One click back into the work** (R-88, P-135, F-59).
@Suite("Return to task")
@MainActor
struct ReturnToTaskTests {
    private static let pagesURL = URL(fileURLWithPath: "/System/Applications/Pages.app")
    private static let textEditURL = URL(fileURLWithPath: "/System/Applications/TextEdit.app")

    private static func running() -> StubReturnWorkspace {
        let workspace = StubReturnWorkspace()
        workspace.runningNames["com.apple.iWork.Pages"] = "Pages"
        workspace.installedURLs["com.apple.iWork.Pages"] = pagesURL
        return workspace
    }

    private static func installedOnly() -> StubReturnWorkspace {
        let workspace = StubReturnWorkspace()
        workspace.installedURLs["com.apple.TextEdit"] = textEditURL
        return workspace
    }

    // MARK: - Branch 1: it is running

    @Test("a running anchor becomes a target that activates rather than launches")
    func runningAnchorActivates() {
        let workspace = Self.running()
        let target = ReturnToTask.target(anchor: "com.apple.iWork.Pages", workspace: workspace)

        #expect(target?.isRunning == true)
        // The localised name, so `{returnTarget}` reads "Back to Pages" rather than "Back to
        // com.apple.iWork.Pages".
        #expect(target?.displayName == "Pages")

        var outcome: ReturnOutcome?
        ReturnToTask.perform(target, workspace: workspace) { outcome = $0 }

        #expect(outcome == .activated(target!))
        #expect(workspace.activations == ["com.apple.iWork.Pages"])
        // **Nothing was launched.** A running application launched again is a second window and
        // a person wondering what just happened.
        #expect(workspace.launches.isEmpty)
    }

    @Test("a refused activation is reported rather than swallowed")
    func refusedActivationIsReported() {
        let workspace = Self.running()
        workspace.activationSucceeds = false
        let target = ReturnToTask.target(anchor: "com.apple.iWork.Pages", workspace: workspace)

        var outcome: ReturnOutcome?
        ReturnToTask.perform(target, workspace: workspace) { outcome = $0 }

        #expect(outcome == .failed(target!, .activationRefused))
        // It does not silently fall back to a launch: the application is running, and launching
        // a second copy is not what the person asked for.
        #expect(workspace.launches.isEmpty)
    }

    // MARK: - Branch 2: it is installed but not running

    @Test("an installed-but-not-running anchor is launched, not activated")
    func installedAnchorLaunches() {
        let workspace = Self.installedOnly()
        let target = ReturnToTask.target(anchor: "com.apple.TextEdit", workspace: workspace)

        #expect(target?.isRunning == false)
        // No localised name is available for something that is not running, so the identifier
        // stands in — honest, and still something the person can recognise.
        #expect(target?.displayName == "com.apple.TextEdit")

        var outcome: ReturnOutcome?
        ReturnToTask.perform(target, workspace: workspace) { outcome = $0 }

        #expect(outcome == .launched(target!))
        #expect(workspace.launches == [Self.textEditURL])
        #expect(workspace.activations.isEmpty)
    }

    @Test("a launch the platform refuses is reported")
    func refusedLaunchIsReported() {
        let workspace = Self.installedOnly()
        workspace.launchSucceeds = false
        let target = ReturnToTask.target(anchor: "com.apple.TextEdit", workspace: workspace)

        var outcome: ReturnOutcome?
        ReturnToTask.perform(target, workspace: workspace) { outcome = $0 }

        #expect(outcome == .failed(target!, .launchFailed))
    }

    // MARK: - Branch 3: there is nowhere to go, so nothing is offered

    /// **R-88.3.** A "back to work" button with nowhere to go is a button that lies, so the
    /// action is withdrawn rather than offered and then explained away.
    @Test("no anchor means the action is not offered at all", arguments: [nil, "", "   "])
    func noAnchorIsNotOffered(anchor: String?) {
        let workspace = Self.running()
        #expect(ReturnToTask.target(anchor: anchor, workspace: workspace) == nil)
        #expect(!ReturnToTask.isOffered(anchor: anchor, workspace: workspace))

        var outcome: ReturnOutcome?
        ReturnToTask.perform(nil, workspace: workspace) { outcome = $0 }
        #expect(outcome == .notOffered)
        #expect(workspace.activations.isEmpty)
        #expect(workspace.launches.isEmpty)
    }

    /// An anchor that outlived the application it named. Nothing on this Mac has that
    /// identifier, so there is nowhere to go and nothing is offered.
    @Test("an anchor for something no longer installed is not offered")
    func uninstalledAnchorIsNotOffered() {
        let workspace = StubReturnWorkspace()
        #expect(ReturnToTask.target(anchor: "com.example.Gone", workspace: workspace) == nil)
        #expect(!ReturnToTask.isOffered(anchor: "com.example.Gone", workspace: workspace))
    }

    /// The one racy case: the target vanished between the panel being drawn and the button
    /// being pressed. Reported as `.notOffered` rather than as a failure — that is a fact about
    /// the app's timing, not something to tell the person off about.
    @Test("a target that vanished between the draw and the click is not a failure")
    func vanishedTargetIsNotAFailure() {
        let workspace = Self.installedOnly()
        let target = ReturnToTask.target(anchor: "com.apple.TextEdit", workspace: workspace)
        workspace.installedURLs.removeAll()

        var outcome: ReturnOutcome?
        ReturnToTask.perform(target, workspace: workspace) { outcome = $0 }
        #expect(outcome == .failed(target!, .notInstalled))
    }

    // MARK: - The ban lives in the lint, and only in the lint

    /// **There is deliberately no source scan here.**
    ///
    /// `check-forbidden.sh`'s R-96e bans `NSApp.activate(`,
    /// `NSApplication.shared.activate(` and `activateIgnoringOtherApps` over the whole nudge
    /// module with **no allow-list at all**, and a copy of that needle list in this file was
    /// written, run, and removed: it failed the very lint it was restating, because the lint
    /// searches `Packages` and a test naming the banned strings is a file naming the banned
    /// strings.
    ///
    /// That is the doctrine working rather than an inconvenience. A vocabulary written down in a
    /// second place is a vocabulary that drifts, and the assertion this suite *can* make without
    /// naming the calls is the behavioural one: every branch below goes through
    /// `ReturnWorkspace`, so a return that brought this application forward would have to do it
    /// through a seam the tests can see.
    @Test("every return goes through the workspace seam and nowhere else")
    func everyReturnGoesThroughTheSeam() {
        let workspace = Self.running()
        let target = ReturnToTask.target(anchor: "com.apple.iWork.Pages", workspace: workspace)

        ReturnToTask.perform(target, workspace: workspace) { _ in }

        // One activation, no launches, and nothing else could have happened: the only calls
        // this type can make are the four on the protocol.
        #expect(workspace.activations.count == 1)
        #expect(workspace.launches.isEmpty)
    }
}
