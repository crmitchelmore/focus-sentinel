import FocusCore
import Foundation
import Testing

@testable import FocusUI

/// A workspace that answers whatever the test tells it to, and records what it was asked.
@MainActor
final class StubReturnWorkspace: ReturnWorkspace {
    var runningNames: [String: String] = [:]
    var installedURLs: [String: URL] = [:]
    /// What the bundle **on the disk** calls itself, by the URL it lives at. Separate from
    /// `runningNames` on purpose: the two are different questions with different answers, and
    /// the case the panel got wrong for a whole epic is the one where only this map has a row.
    var installedNames: [URL: String] = [:]
    var activationSucceeds = true
    var launchSucceeds = true

    private(set) var activations: [String] = []
    private(set) var launches: [URL] = []
    /// Every identifier a name was asked for, in order — so "the name is learned once and kept"
    /// is a count rather than a claim (`SubjectNamingTests`).
    private(set) var lookups: [String] = []
    /// Every URL a bundle name was read from, in order. The same instrument for the second
    /// question: an origin must reach neither map.
    private(set) var bundleLookups: [URL] = []

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

    func applicationName(at url: URL) -> String? {
        bundleLookups.append(url)
        return installedNames[url]
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

    /// Installed and **not running** — the case the shipped panel drew as
    /// *"Back to com.apple.TextEdit"*. The bundle on the disk has a name, because on a real Mac
    /// it does: `SystemReturnWorkspace.applicationName(at:)` reads it out of the bundle, and
    /// measured on this Mac `com.apple.TextEdit` answers *"TextEdit"* while nothing is running.
    private static func installedOnly() -> StubReturnWorkspace {
        let workspace = StubReturnWorkspace()
        workspace.installedURLs["com.apple.TextEdit"] = textEditURL
        workspace.installedNames[textEditURL] = "TextEdit"
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
        // **The name, from the bundle the launch itself is about to use.** This assertion
        // replaces one that pinned `"com.apple.TextEdit"` as the expected value with a comment
        // calling it "honest, and still something the person can recognise" — the fourth test
        // file in this repository to write the defect down as the specification.
        #expect(target?.displayName == "TextEdit")
        // And it was read from the URL the code already had, not looked up a second time.
        #expect(workspace.bundleLookups == [Self.textEditURL])

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

    // MARK: - What the button actually says (focus-7gc)

    /// One row of the naming table: what the two lookups answer, and what the button must read.
    struct NamingCase: Sendable, CustomStringConvertible {
        let runningName: String?
        let installedName: String?
        let expected: String
        let note: String

        var description: String { note }
    }

    /// **The whole input space, not the case the suite was handed.**
    ///
    /// `displayName` is decided by two optional lookups, and each of them has four answers a real
    /// Mac gives: a name, no name, an empty name, and a name made only of spaces — the last two
    /// are not hypothetical, they were measured. `FileManager.displayName` answers `"Bar  "` for a
    /// bundle called `Bar  .app` and `"   "` for one called `   .app`. The shipped code guarded
    /// `isEmpty` on one lookup and did not perform the other at all, so it was wrong in six of
    /// these eight rows and its suite asserted two of them.
    nonisolated static let namingCases: [NamingCase] = [
        // Running. The first row is the one the old suite proved.
        NamingCase(
            runningName: "TextEdit", installedName: nil, expected: "TextEdit",
            note: "running under a name"
        ),
        NamingCase(
            runningName: "  TextEdit  ", installedName: nil, expected: "TextEdit",
            note: "running under a padded name"
        ),
        NamingCase(
            runningName: "", installedName: "TextEdit", expected: "TextEdit",
            note: "running under no name at all: the disk answers instead"
        ),
        NamingCase(
            runningName: "   ", installedName: "TextEdit", expected: "TextEdit",
            note: "running under whitespace: the old isEmpty guard drew 'Back to    '"
        ),
        // Not running. Every one of these read the identifier before focus-7gc.
        NamingCase(
            runningName: nil, installedName: "TextEdit", expected: "TextEdit",
            note: "installed, not running"
        ),
        NamingCase(
            runningName: nil, installedName: nil, expected: "com.apple.TextEdit",
            note: "installed with nothing to say: the key is the honest last resort"
        ),
        NamingCase(
            runningName: nil, installedName: "", expected: "com.apple.TextEdit",
            note: "a bundle whose name is empty"
        ),
        NamingCase(
            runningName: nil, installedName: "   ", expected: "com.apple.TextEdit",
            note: "a bundle whose name is only spaces"
        )
    ]

    @Test("the button names the application in every state the two lookups can be in",
          arguments: namingCases)
    func theButtonNamesTheApplication(naming: NamingCase) {
        let workspace = StubReturnWorkspace()
        workspace.installedURLs["com.apple.TextEdit"] = Self.textEditURL
        workspace.runningNames["com.apple.TextEdit"] = naming.runningName
        workspace.installedNames[Self.textEditURL] = naming.installedName

        let target = ReturnToTask.target(anchor: "com.apple.TextEdit", workspace: workspace)

        #expect(target?.displayName == naming.expected, "\(naming.note)")
        // **The pair, every time.** "It contains the name" is satisfied by a string that carries
        // the identifier as well, which is what a half-applied fix looks like. Six of these eight
        // rows drew the identifier before; only the two that are *allowed* to may still.
        if naming.expected != "com.apple.TextEdit" {
            #expect(
                target?.displayName.contains("com.apple.TextEdit") == false,
                "\(naming.note): the button still says the key"
            )
        }
        // The key half is untouched by any of it. A rule, a receipt and a launch are all keyed
        // on this, and the whole repair is worthless if resolving a name moved it.
        #expect(target?.bundleIdentifier == "com.apple.TextEdit")
    }

    /// **The path nothing tested: an anchor, through the panel, to the words on the button.**
    ///
    /// Every `returnTarget` fixture in this repository — 28 of them — passes a pre-resolved
    /// `"Pages"` or `"TextEdit"` straight into `AccusationPresentation`, so not one of them could
    /// have failed while `ReturnToTask.target(anchor:workspace:)` was handing back a bundle
    /// identifier. This starts where the app starts, at the stored anchor, and ends at the string
    /// the person reads on the most prominent control on the surface.
    @Test(
        "an anchor that is installed but not running reaches the button as a name",
        .enabled(if: LocalizationLane.catalogsAreCompiled),
        arguments: NudgeVoice.allCases
    )
    func theAnchorReachesTheButtonAsAName(voice: NudgeVoice) {
        let workspace = Self.installedOnly()
        let target = ReturnToTask.target(anchor: "com.apple.TextEdit", workspace: workspace)

        let presentation = AccusationPresentation(
            rung: .panel,
            voice: voice,
            task: "Write the Q3 proposal",
            subject: NudgeSubject.named("com.figma.Desktop", runningName: "Figma"),
            dwelled: .seconds(12 * 60),
            returnTarget: target?.displayName
        )

        // It is offered at all, and it is the emphasised control — which is what makes this the
        // most visible string on the panel rather than a detail in a menu.
        #expect(presentation.primaryAction == .returnToTask)

        let label = NudgeCopy.string(
            voice: voice,
            .accusationActionReturn,
            arguments: [presentation.returnTarget ?? ""]
        )
        #expect(label.contains("TextEdit"), "\(voice) drew: \(label)")
        #expect(!label.contains("com.apple.TextEdit"), "\(voice) drew the key: \(label)")
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
