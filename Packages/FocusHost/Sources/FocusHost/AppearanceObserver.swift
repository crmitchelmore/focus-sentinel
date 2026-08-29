import AppKit
import FocusCore
import Foundation

/// Turns the Mac's live appearance and accessibility settings into an `AppearanceTraits`
/// value, and republishes when the user changes one.
///
/// ## Why it lives in the composition layer (focus-2er)
///
/// It was in `App/`, and `App/` is not a package: no test bundle can import it, so every one of
/// this object's behaviours — the preference resolving into a colour scheme, the four
/// accessibility flags, the two notification registrations that make it *live* — was asserted by
/// nothing at all. Deleting `startObserving()` left the whole gate green: the app stopped
/// reacting to the person switching to dark mode or turning on Reduce Motion, and no lane could
/// see it.
///
/// It reads `AppKit` and publishes a value, which is what this layer is for; it declares no view
/// and imports no SwiftUI, so the boundary matrix is unchanged. `AppearanceObserverTests` drives
/// it by posting the real notifications.
///
/// The four accessibility flags come from `NSWorkspace`, which reports them without any
/// permission prompt. The colour scheme comes from the application's effective appearance,
/// resolved against the user's own preference (Match System / Light / Dark).
///
/// Everything downstream consumes the resulting *value*. Views never read `NSWorkspace`
/// themselves — that is what lets the snapshot lane render all five appearance variants on
/// a machine where every accessibility setting is switched off, without touching the
/// developer's System Settings.
@Observable
@MainActor
public final class AppearanceObserver {
    /// The user's stored choice. Setting it recomputes `traits`.
    public var preference: AppearancePreference {
        didSet { refresh() }
    }

    /// The current traits, as a value ready to inject into the environment.
    public private(set) var traits: AppearanceTraits

    /// Holds the notification tokens and unregisters them when this observer goes away.
    ///
    /// A separate object rather than a stored array on the observer itself, because
    /// `deinit` runs outside the main actor and so cannot touch main-actor-isolated state.
    /// The box's own `deinit` is nonisolated all the way down, which is what makes the
    /// clean-up legal instead of merely omitted.
    private let tokens = NotificationTokens()

    public init(preference: AppearancePreference = .matchSystem) {
        self.preference = preference
        self.traits = Self.currentTraits(preference: preference)
        startObserving()
    }

    /// Recompute from the live system. Called on every relevant notification, and callable
    /// directly when the user changes their preference.
    public func refresh() {
        traits = Self.currentTraits(preference: preference)
        refreshCount += 1
    }

    /// How many times the live system has been re-read.
    ///
    /// The observable half of "this object is attached to the Mac" (focus-2er). A registration
    /// that was never made and a notification that never arrives are the same reading without
    /// it, so `AppearanceObserverTests` posts the real notifications and watches this move.
    public private(set) var refreshCount = 0

    private func startObserving() {
        // Increase Contrast / Reduce Transparency / Reduce Motion / Differentiate Without
        // Colour all arrive through this one notification.
        let accessibilityToken = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refresh()
            }
        }

        // Light/dark switching does not come through the workspace centre; the system
        // broadcasts it.
        let themeToken = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refresh()
            }
        }

        tokens.workspace = [accessibilityToken]
        tokens.distributed = [themeToken]
    }

    /// What the system currently reports, before the user's preference is applied.
    public static var systemColorScheme: AppearanceColorScheme {
        let match = NSApplication.shared.effectiveAppearance
            .bestMatch(from: [.aqua, .darkAqua])
        return match == .darkAqua ? .dark : .light
    }

    private static func currentTraits(preference: AppearancePreference) -> AppearanceTraits {
        let workspace = NSWorkspace.shared
        return AppearanceTraits(
            colorScheme: preference.resolvedColorScheme(system: systemColorScheme),
            increasedContrast: workspace.accessibilityDisplayShouldIncreaseContrast,
            reduceTransparency: workspace.accessibilityDisplayShouldReduceTransparency,
            reduceMotion: workspace.accessibilityDisplayShouldReduceMotion,
            differentiateWithoutColor: workspace.accessibilityDisplayShouldDifferentiateWithoutColor
        )
    }
}

/// Owns the notification registrations so they can be torn down from a nonisolated
/// `deinit`. Every mutation happens on the main actor inside `AppearanceObserver`, which is
/// why the unchecked conformance is honest rather than a shrug.
private final class NotificationTokens: @unchecked Sendable {
    var workspace: [NSObjectProtocol] = []
    var distributed: [NSObjectProtocol] = []

    deinit {
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        for token in workspace {
            workspaceCenter.removeObserver(token)
        }
        let distributedCenter = DistributedNotificationCenter.default()
        for token in distributed {
            distributedCenter.removeObserver(token)
        }
    }
}
