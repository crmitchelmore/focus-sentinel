import FocusCore
import Foundation
import Testing

@testable import FocusSensing

/// A workspace that opens nothing and remembers everything — **and counts the two calls this
/// programme must never make.**
///
/// `hideCalls` and `terminateCalls` can only ever be zero, and that is the point: `SessionLauncher`
/// talks through `WorkspaceLaunching`, which has no `hide` and no `terminate` member at all, so
/// there is no expression the launcher could contain that would move either counter. The
/// counters exist so the assertion is written down where a reader looks for it, and so that
/// adding such a member later would have to come past this test.
@MainActor
final class RecordingWorkspace: WorkspaceLaunching {
    struct OpenedApplication: Equatable {
        let url: URL
        let activates: Bool
    }

    private(set) var openedApplications: [OpenedApplication] = []
    private(set) var openedFiles: [URL] = []
    private(set) var hideCalls = 0
    private(set) var terminateCalls = 0

    /// Which bundle identifiers this Mac pretends to have installed.
    var installed: [String: URL]
    /// Whether `open(_:)` succeeds.
    var openSucceeds = true

    init(installed: [String: URL] = [:]) {
        self.installed = installed
    }

    @discardableResult
    func openApplication(at url: URL, activates: Bool) -> Bool {
        openedApplications.append(OpenedApplication(url: url, activates: activates))
        return true
    }

    @discardableResult
    func open(_ url: URL) -> Bool {
        guard openSucceeds else { return false }
        openedFiles.append(url)
        return true
    }

    func applicationURL(forBundleIdentifier bundleID: String) -> URL? {
        installed[bundleID]
    }
}

@MainActor
@Suite("Session launcher")
struct SessionLauncherTests {
    private static let addedAt = FixedDateProvider.reference.now

    private static func appItem(_ bundleID: String, order: TimeInterval = 0) -> ContextItemValue {
        ContextItemValue(
            kind: .app,
            value: bundleID,
            displayName: bundleID,
            addedAt: addedAt.addingTimeInterval(order)
        )
    }

    private static func domainItem(_ origin: String) -> ContextItemValue {
        ContextItemValue(kind: .domain, value: origin, displayName: origin, addedAt: addedAt)
    }

    private static func keywordItem(_ word: String) -> ContextItemValue {
        ContextItemValue(kind: .keyword, value: word, displayName: word, addedAt: addedAt)
    }

    /// A file item whose bookmark really resolves, made from a real temporary file.
    private static func realFileItem() throws -> (item: ContextItemValue, url: URL) {
        let url = URL.temporaryDirectory.appending(
            path: "focus-launcher-\(UUID().uuidString).txt",
            directoryHint: .notDirectory
        )
        try Data("focus".utf8).write(to: url)
        let bookmark = try SecurityScopedBookmark.create(for: url)
        return (
            ContextItemValue(
                kind: .file,
                value: url.path(percentEncoded: false),
                displayName: url.lastPathComponent,
                bookmark: bookmark,
                addedAt: addedAt
            ),
            url
        )
    }

    // MARK: - Off by default

    @Test("It is off by default: with the setting false nothing is opened at all")
    func offByDefault() {
        let workspace = RecordingWorkspace(installed: ["com.apple.TextEdit": URL(filePath: "/System/Applications/TextEdit.app")])
        let launcher = SessionLauncher(workspace: workspace)

        let attempts = launcher.launch([Self.appItem("com.apple.TextEdit")], isEnabled: false)

        #expect(attempts.isEmpty)
        #expect(workspace.openedApplications.isEmpty)
        // A focus app that rearranged your desktop the first time you pressed Start would have
        // earned every bit of the suspicion that followed.
        #expect(FocusSchemaV3.AppSettingsRecord(
            appearancePreferenceRaw: "matchSystem",
            schemaTouchedAt: Self.addedAt
        ).launchContextOnSessionStart == false)
    }

    // MARK: - It never hides and never quits

    @Test("No hide and no terminate call is ever made")
    func neverHidesAndNeverQuits() throws {
        let (file, url) = try Self.realFileItem()
        defer { try? FileManager.default.removeItem(at: url) }

        let workspace = RecordingWorkspace(installed: [
            "com.apple.TextEdit": URL(filePath: "/System/Applications/TextEdit.app"),
            "com.apple.Calculator": URL(filePath: "/System/Applications/Calculator.app")
        ])
        let launcher = SessionLauncher(workspace: workspace)

        launcher.launch(
            [
                Self.appItem("com.apple.TextEdit", order: 0),
                Self.appItem("com.apple.Calculator", order: 1),
                Self.domainItem("https://example.com"),
                Self.keywordItem("proposal"),
                file
            ],
            isEnabled: true
        )

        #expect(workspace.hideCalls == 0)
        #expect(workspace.terminateCalls == 0)
    }

    // MARK: - Applications

    @Test("Only the first application is allowed to come forward")
    func onlyTheFirstApplicationActivates() {
        let workspace = RecordingWorkspace(installed: [
            "com.first": URL(filePath: "/Applications/First.app"),
            "com.second": URL(filePath: "/Applications/Second.app"),
            "com.third": URL(filePath: "/Applications/Third.app")
        ])
        let launcher = SessionLauncher(workspace: workspace)

        let attempts = launcher.launch(
            [
                Self.appItem("com.first", order: 0),
                Self.appItem("com.second", order: 1),
                Self.appItem("com.third", order: 2)
            ],
            isEnabled: true
        )

        // Starting a session should not shuffle the person's windows.
        #expect(workspace.openedApplications.map(\.activates) == [true, false, false])
        #expect(attempts.map(\.activated) == [true, false, false])
        #expect(attempts.allSatisfy { $0.outcome == .opened })
    }

    @Test("An application that is not installed is skipped silently")
    func uninstalledApplicationIsSkipped() {
        let workspace = RecordingWorkspace(installed: [:])
        let launcher = SessionLauncher(workspace: workspace)

        let attempts = launcher.launch([Self.appItem("com.example.NotHere")], isEnabled: true)

        #expect(attempts.map(\.outcome) == [.skipped])
        #expect(workspace.openedApplications.isEmpty)
    }

    @Test("A skipped first application does not spend the one activation")
    func aSkippedApplicationDoesNotSpendTheActivation() {
        let workspace = RecordingWorkspace(installed: ["com.second": URL(filePath: "/Applications/Second.app")])
        let launcher = SessionLauncher(workspace: workspace)

        launcher.launch(
            [Self.appItem("com.missing", order: 0), Self.appItem("com.second", order: 1)],
            isEnabled: true
        )

        // The person asked for two applications and got one; the one they got is the one that
        // comes forward, rather than nothing coming forward because the first was uninstalled.
        #expect(workspace.openedApplications.map(\.activates) == [true])
    }

    // MARK: - Files

    @Test("A file opens through its bookmark")
    func fileOpensThroughItsBookmark() throws {
        let (file, url) = try Self.realFileItem()
        defer { try? FileManager.default.removeItem(at: url) }

        let workspace = RecordingWorkspace()
        let launcher = SessionLauncher(workspace: workspace)

        let attempts = launcher.launch([file], isEnabled: true)

        #expect(attempts.map(\.outcome) == [.opened])
        #expect(workspace.openedFiles.count == 1)
        #expect(workspace.openedFiles.first?.lastPathComponent == url.lastPathComponent)
    }

    @Test("A missing bookmark is skipped silently")
    func missingBookmarkIsSkippedSilently() throws {
        let (file, url) = try Self.realFileItem()
        try FileManager.default.removeItem(at: url)

        let workspace = RecordingWorkspace()
        let launcher = SessionLauncher(workspace: workspace)

        let attempts = launcher.launch([file], isEnabled: true)

        // A session must not fail because a disk is unplugged, and a modal about a missing
        // file at the moment somebody sat down to work would be the opposite of help.
        #expect(attempts.map(\.outcome) == [.skipped])
        #expect(workspace.openedFiles.isEmpty)
    }

    @Test("A file item with no bookmark at all is skipped")
    func fileWithNoBookmarkIsSkipped() {
        let item = ContextItemValue(
            kind: .file,
            value: "/Users/someone/Documents/thing.txt",
            displayName: "thing.txt",
            bookmark: nil,
            addedAt: Self.addedAt
        )
        let workspace = RecordingWorkspace()

        let attempts = SessionLauncher(workspace: workspace).launch([item], isEnabled: true)

        // A path is not a file. The durable handle is the bookmark, and without one there is
        // nothing this app is entitled to reach.
        #expect(attempts.map(\.outcome) == [.skipped])
        #expect(workspace.openedFiles.isEmpty)
    }

    // MARK: - Domains and keywords open nothing

    @Test("A domain item opens nothing")
    func domainsOpenNothing() {
        let workspace = RecordingWorkspace()
        let launcher = SessionLauncher(workspace: workspace)

        let attempts = launcher.launch([Self.domainItem("https://example.com")], isEnabled: true)

        // Opening a web page means choosing a browser and inventing a URL from an origin — and
        // the origin is all that is stored, because only normalised origins are ever retained.
        #expect(attempts.map(\.outcome) == [.ignored])
        #expect(workspace.openedFiles.isEmpty)
        #expect(workspace.openedApplications.isEmpty)
    }

    @Test("A keyword item opens nothing")
    func keywordsOpenNothing() {
        let workspace = RecordingWorkspace()
        let attempts = SessionLauncher(workspace: workspace)
            .launch([Self.keywordItem("proposal")], isEnabled: true)

        #expect(attempts.map(\.outcome) == [.ignored])
    }

    @Test("A kind this build does not understand opens nothing rather than being guessed at")
    func unknownKindsOpenNothing() {
        let item = ContextItemValue(
            kind: .unknown("somethingALaterBuildInvented"),
            value: "whatever",
            displayName: "whatever",
            addedAt: Self.addedAt
        )
        let workspace = RecordingWorkspace()

        let attempts = SessionLauncher(workspace: workspace).launch([item], isEnabled: true)

        #expect(attempts.map(\.outcome) == [.ignored])
        #expect(workspace.openedApplications.isEmpty)
        #expect(workspace.openedFiles.isEmpty)
    }

    // MARK: - One attempt per item

    @Test("Every item produces exactly one attempt, in the order the person added them")
    func oneAttemptPerItem() throws {
        let (file, url) = try Self.realFileItem()
        defer { try? FileManager.default.removeItem(at: url) }

        let workspace = RecordingWorkspace(installed: ["com.first": URL(filePath: "/Applications/First.app")])
        let launcher = SessionLauncher(workspace: workspace)

        let items = [
            Self.appItem("com.first", order: 0),
            Self.domainItem("https://example.com"),
            file,
            Self.keywordItem("proposal")
        ]
        let attempts = launcher.launch(items, isEnabled: true)

        // One event per attempt is what lets the person see what it did.
        #expect(attempts.count == items.count)
        #expect(attempts.map(\.itemID) == items.map(\.id))
        #expect(attempts.map(\.kind) == [.app, .domain, .file, .keyword])
        #expect(attempts.map(\.outcome) == [.opened, .ignored, .opened, .ignored])
    }
}
