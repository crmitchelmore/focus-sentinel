import AppKit
import FocusCore
import Foundation

/// The seam between this app and LaunchServices — and, just as importantly, the shape of what
/// it **cannot** do.
///
/// There is no `hide`, no `terminate`, no `activate(_:)` on somebody else's application, and no
/// Apple Event of any kind. That is the enforcement of D-07's coercion ban and of the Court's
/// cut: a launcher that could quit your other applications is not a focus tool, it is a
/// disciplinarian. The test double records that no such call was made; the seam is why no such
/// call *could* be.
@MainActor
public protocol WorkspaceLaunching: AnyObject {
    /// Open an application bundle. `activates` is `false` for every item but the first, so
    /// starting a session does not shuffle the person's windows.
    @discardableResult
    func openApplication(at url: URL, activates: Bool) -> Bool

    /// Open a file with whatever the person's Mac opens it with.
    @discardableResult
    func open(_ url: URL) -> Bool

    /// Where an application bundle with this identifier lives, or `nil` if it is not installed.
    func applicationURL(forBundleIdentifier bundleID: String) -> URL?
}

/// The production LaunchServices adapter.
@MainActor
public final class SystemWorkspaceLauncher: WorkspaceLaunching {
    public init() {}

    @discardableResult
    public func openApplication(at url: URL, activates: Bool) -> Bool {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = activates
        NSWorkspace.shared.openApplication(at: url, configuration: configuration)
        // LaunchServices answers asynchronously; the completion is deliberately not waited on.
        // A session must not stall because an application is slow to start, and the event this
        // writes is an *attempt*, which is what the person is entitled to see.
        return true
    }

    @discardableResult
    public func open(_ url: URL) -> Bool {
        NSWorkspace.shared.open(url)
    }

    public func applicationURL(forBundleIdentifier bundleID: String) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }
}

/// What one launch attempt did. Returned so the host can write exactly one event per attempt.
public struct LaunchAttempt: Sendable, Equatable, Hashable {
    public enum Outcome: String, Sendable, CaseIterable, Codable, Hashable {
        /// LaunchServices was asked to open it.
        case opened
        /// The item is not a thing to open. A domain chip is context for the classifier, and a
        /// keyword is not a place.
        case ignored
        /// A file whose bookmark no longer resolves, or an application that is not installed.
        /// Skipped **silently**: a session must not fail because a disk is unplugged.
        case skipped
    }

    public let itemID: UUID
    public let kind: ContextItemKind
    public let outcome: Outcome
    /// Whether this attempt was allowed to bring its application forward. True for at most one
    /// per launch, and only for the first application.
    public let activated: Bool

    public init(itemID: UUID, kind: ContextItemKind, outcome: Outcome, activated: Bool) {
        self.itemID = itemID
        self.kind = kind
        self.outcome = outcome
        self.activated = activated
    }
}

/// F-169's launcher: it opens, and that is all it does.
///
/// ## Off by default
///
/// `AppSettingsRecord.launchContextOnSessionStart` is `false`, and the caller checks it. A
/// focus app that rearranged your desktop the first time you pressed Start would have earned
/// every bit of the suspicion that followed.
///
/// ## What it opens, and what it deliberately does not
///
/// * `.app` items open through LaunchServices, with `activates = false` for **all but the
///   first** — starting a session should not shuffle the person's windows.
/// * `.file` items open through the security-scoped bookmark e02 stored. A bookmark that no
///   longer resolves is skipped **silently**: a session must not fail because a disk is
///   unplugged, and a modal about a missing file at the moment somebody sat down to work would
///   be the opposite of help.
/// * `.domain` items open **nothing**. Opening a web page means choosing a browser and
///   inventing a URL from an origin, and the origin is all that is stored — only normalised
///   origins are ever retained, never full URLs (standing condition 3). A domain chip is
///   context for the classifier, not a thing to launch.
/// * `.keyword` items open nothing, for the obvious reason.
/// * An unknown kind, written by a later build, opens nothing rather than being guessed at.
///
/// ## It never hides and never quits
///
/// There is no `hide()`, no `terminate()` and no Apple Events anywhere in it — and the seam it
/// talks through has no such member, so there is nothing to remember not to call.
@MainActor
public final class SessionLauncher {
    private let workspace: any WorkspaceLaunching

    public init(workspace: any WorkspaceLaunching = SystemWorkspaceLauncher()) {
        self.workspace = workspace
    }

    /// Open a priority's context pack, in the order the person added it.
    ///
    /// - Parameter isEnabled: the stored setting. Passed in rather than read here so that the
    ///   default-off rule has exactly one home and this type stays testable without a store.
    /// - Returns: one `LaunchAttempt` per item, so the caller writes one event per attempt and
    ///   the person can see what it did.
    @discardableResult
    public func launch(_ items: [ContextItemValue], isEnabled: Bool) -> [LaunchAttempt] {
        guard isEnabled else { return [] }

        var hasActivatedOne = false
        return items.map { item in
            switch item.kind {
            case .app:
                return openApplication(item, activateIfFirst: &hasActivatedOne)
            case .file:
                return openFile(item)
            case .domain, .keyword, .unknown:
                // Not a thing to open. Not a failure either — it is context, and context is
                // for the engine to read rather than for the launcher to act on.
                return LaunchAttempt(itemID: item.id, kind: item.kind, outcome: .ignored, activated: false)
            }
        }
    }

    private func openApplication(
        _ item: ContextItemValue,
        activateIfFirst hasActivatedOne: inout Bool
    ) -> LaunchAttempt {
        guard let url = workspace.applicationURL(forBundleIdentifier: item.value) else {
            // Not installed on this Mac. Skipped silently, for the same reason a missing file
            // is: the person's session is not the place to find that out loudly.
            return LaunchAttempt(itemID: item.id, kind: .app, outcome: .skipped, activated: false)
        }

        let activates = !hasActivatedOne
        if activates { hasActivatedOne = true }
        workspace.openApplication(at: url, activates: activates)
        return LaunchAttempt(itemID: item.id, kind: .app, outcome: .opened, activated: activates)
    }

    private func openFile(_ item: ContextItemValue) -> LaunchAttempt {
        guard
            let bookmark = item.bookmark,
            case .resolved(let url, _) = SecurityScopedBookmark.resolve(bookmark)
        else {
            return LaunchAttempt(itemID: item.id, kind: .file, outcome: .skipped, activated: false)
        }

        // The scope is opened and closed by the one file permitted to do it, around the one
        // call that needs it.
        let opened = SecurityScopedBookmark.withAccess(to: url) { resolved in
            workspace.open(resolved)
        }
        return LaunchAttempt(
            itemID: item.id,
            kind: .file,
            outcome: opened ? .opened : .skipped,
            activated: false
        )
    }
}
