import AppKit
import FocusCore
import Foundation

/// **The application "Back to …" would put the person in front of.**
///
/// A value with a bundle identifier and the name a person would recognise. It is produced only
/// from a **stored anchor** — the last subject the engine judged `relevant` — and never invented
/// from what happens to be running, because a button that took somebody to an application they
/// were not working in is worse than no button.
public struct ReturnTarget: Sendable, Equatable, Hashable {
    public let bundleIdentifier: String
    /// The application's localised name, for `{returnTarget}`. Falls back to the bundle
    /// identifier when the workspace has no name for it — which is honest, and still a thing the
    /// person can recognise.
    public let displayName: String
    /// Whether it is running right now. Decides `activate()` versus `openApplication` (R-88),
    /// and nothing else.
    public let isRunning: Bool

    public init(bundleIdentifier: String, displayName: String, isRunning: Bool) {
        self.bundleIdentifier = bundleIdentifier
        self.displayName = displayName
        self.isRunning = isRunning
    }
}

/// What happened when the person clicked "Back to …".
public enum ReturnOutcome: Sendable, Equatable {
    /// It was running and `NSRunningApplication.activate()` took it. P-135 measured this
    /// returning `true` and moving the frontmost application from a **never-active** background
    /// app at zero grants — including out of a full-screen space — with our own application
    /// never becoming active.
    case activated(ReturnTarget)
    /// It was not running and `NSWorkspace.openApplication(at:configuration:)` launched it.
    /// P-135 measured this launching TextEdit cold and making it frontmost.
    case launched(ReturnTarget)
    /// The platform declined. Reported rather than swallowed: a button that appears to do
    /// nothing is worse than one that says it could not.
    case failed(ReturnTarget, ReturnFailure)
    /// **There is no stored target, so the action was never offered.** Not a failure — the
    /// absence of an affordance (R-88.3).
    case notOffered
}

public enum ReturnFailure: String, Sendable, CaseIterable, Hashable {
    /// `activate()` returned `false`.
    case activationRefused
    /// Nothing on this Mac has that bundle identifier any more — the person uninstalled it, or
    /// the anchor outlived the application.
    case notInstalled
    /// `openApplication` came back with an error.
    case launchFailed
}

/// The two workspace calls R-88 sanctions, behind a seam.
///
/// A protocol so the unit lane can drive all three branches with no application to activate and
/// no application to launch. The real implementation is `SystemReturnWorkspace`, below, and it
/// contains exactly the two calls P-135 measured — and **not** `NSApp.activate()`, which
/// `check-forbidden.sh` bans outright in this module (R-96e).
@MainActor
public protocol ReturnWorkspace: AnyObject {
    /// The localised name of a **running** application with this bundle identifier, or `nil`
    /// when it is not running.
    func localizedNameOfRunningApplication(_ bundleIdentifier: String) -> String?
    /// Bring a running application forward. `false` when the platform declined.
    func activateRunningApplication(_ bundleIdentifier: String) -> Bool
    /// Where an installed-but-not-running application lives, or `nil` when none is installed.
    func applicationURL(for bundleIdentifier: String) -> URL?
    /// Launch it and bring it forward.
    func openApplication(at url: URL, completion: @escaping @MainActor (Bool) -> Void)
}

/// **One click back into the work** (R-88, P-135, F-59).
///
/// ## The sequence, measured rather than assumed
///
/// P-135 ran the whole of this at zero grants from an application that had **never been
/// active** — which is the exact posture a nudge fires in:
///
/// 1. **Running?** `NSRunningApplication.activate()`. Returned `true`; the frontmost application
///    changed; `weAreActiveAfter == false` throughout, so our own app never became active. It
///    also worked from inside a decoy's full-screen space, leaving the space behind it.
/// 2. **Not running?** `NSWorkspace.openApplication(at:configuration:)` with `activates = true`.
///    Launched TextEdit cold and made it frontmost.
/// 3. **No stored target at all?** The action is **not offered**. e04's mandate knows what the
///    drift is *from* only when an anchor exists; offering "back to work" with nowhere to go is
///    a button that lies.
///
/// ## `NSApplication.activate()` is banned, and not because of a measurement
///
/// P-135 recorded a negative — the call did *not* steal focus in the probe — and this code
/// explicitly does not rely on it. The probe application was `.accessory` with no activatable
/// window; the shipping app is `.regular` (F-01, F-85), so the reading does not transfer. The
/// ban stands on the policy rather than on the number, and R-96e is the lint that holds it.
public enum ReturnToTask {
    /// The target for a stored anchor, or `nil` when there is nothing to return to.
    ///
    /// - Parameters:
    ///   - anchor: the bundle identifier of the last application the engine judged `relevant`.
    ///     `nil`, empty or whitespace-only all mean the same thing: **there is no anchor**, and
    ///     the action is not offered.
    ///   - workspace: the seam. Consulted for the localised name and for whether it is running.
    @MainActor
    public static func target(
        anchor: String?,
        workspace: any ReturnWorkspace
    ) -> ReturnTarget? {
        guard let anchor else { return nil }
        let trimmed = anchor.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let name = workspace.localizedNameOfRunningApplication(trimmed) {
            return ReturnTarget(
                bundleIdentifier: trimmed,
                displayName: name.isEmpty ? trimmed : name,
                isRunning: true
            )
        }

        // Not running. It is still a target **if it is installed** — a cold launch is a
        // legitimate return, and P-135 measured one working at zero grants. If nothing on this
        // Mac has that identifier there is nowhere to go, and the honest answer is `nil`.
        guard workspace.applicationURL(for: trimmed) != nil else { return nil }
        return ReturnTarget(
            bundleIdentifier: trimmed,
            displayName: trimmed,
            isRunning: false
        )
    }

    /// Whether the panel should draw the action at all.
    @MainActor
    public static func isOffered(anchor: String?, workspace: any ReturnWorkspace) -> Bool {
        target(anchor: anchor, workspace: workspace) != nil
    }

    /// Put the person back in front of their work.
    ///
    /// - Parameter target: from `target(anchor:workspace:)`. `nil` produces `.notOffered`, which
    ///   is the value a host records when something raced the click — a target that vanished
    ///   between the panel being drawn and the button being pressed is not a failure to report
    ///   to the person.
    @MainActor
    public static func perform(
        _ target: ReturnTarget?,
        workspace: any ReturnWorkspace,
        completion: @escaping @MainActor (ReturnOutcome) -> Void
    ) {
        guard let target else {
            completion(.notOffered)
            return
        }

        // 1 — running: activate. Never `NSApp.activate()`; this application stays where it is.
        if target.isRunning {
            let activated = workspace.activateRunningApplication(target.bundleIdentifier)
            completion(activated ? .activated(target) : .failed(target, .activationRefused))
            return
        }

        // 2 — installed but not running: launch it, and let it come forward.
        guard let url = workspace.applicationURL(for: target.bundleIdentifier) else {
            completion(.failed(target, .notInstalled))
            return
        }
        workspace.openApplication(at: url) { launched in
            completion(launched ? .launched(target) : .failed(target, .launchFailed))
        }
    }
}

/// The real workspace, behind the seam.
///
/// Exactly the two calls R-88 sanctions and nothing else. In particular there is no
/// `NSApp.activate(`, no `NSApplication.shared.activate(` and no `activateIgnoringOtherApps`
/// anywhere in this file — `check-forbidden.sh` asserts that over the whole nudge module with no
/// allow-list at all (R-96e).
@MainActor
public final class SystemReturnWorkspace: ReturnWorkspace {
    public init() {}

    public func localizedNameOfRunningApplication(_ bundleIdentifier: String) -> String? {
        NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleIdentifier)
            .first?
            .localizedName
    }

    public func activateRunningApplication(_ bundleIdentifier: String) -> Bool {
        guard let application = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleIdentifier)
            .first
        else { return false }
        // The cooperative API, which is what P-135 measured: `true`, the frontmost application
        // changed, and this process never became active.
        return application.activate()
    }

    public func applicationURL(for bundleIdentifier: String) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
    }

    public func openApplication(
        at url: URL,
        completion: @escaping @MainActor (Bool) -> Void
    ) {
        let configuration = NSWorkspace.OpenConfiguration()
        // The whole point of the call: the person asked to be put back in front of it.
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { app, _ in
            let launched = app != nil
            Task { @MainActor in completion(launched) }
        }
    }
}
