import AppKit
import FocusCore
import Foundation
import Observation

/// **What macOS currently lets the app do, for the grants the person switched on** — kept where
/// a SwiftUI body can see it change (issue #24 follow-up).
///
/// A grant is given in System Settings, in another application, at a moment this one cannot
/// see; and it is taken away the same way, or silently, when a rebuilt or moved copy no longer
/// matches the one the person allowed. So the state is never inferred from a click. It is read,
/// without asking, by `GrantGate.state` — on every cockpit tick (a menu-bar app is seldom the
/// active one, so becoming active is not enough), when the app becomes active, and
/// every `pollInterval` for `pollLimit` ticks after the person opened System Settings from the
/// Privacy pane, stopping as soon as every switched-on grant is allowed. The same shape the
/// owner's Pasta and Just Speak to It use.
///
/// `@Observable`, for the reason `SettingsTabSelection` is: `AppComposition` is a plain class,
/// and a write to one of its stored properties invalidates no body. With the switches and the
/// states here, the Privacy pane redraws the moment either moves.
@Observable
@MainActor
public final class GrantAccessWatch {
    /// How often a watch reads the grants while the person is in System Settings.
    static let pollInterval: Duration = .milliseconds(500)
    /// How many reads one watch makes before it gives up: two minutes.
    static let pollLimit = 240

    /// The System Settings pane that holds `grant`, as a link macOS opens at the right list.
    static func systemSettingsURL(for grant: GrantOptIn) -> URL {
        let anchor = switch grant {
        case .accessibilityWindowContext: "Privacy_Accessibility"
        case .screenCapture: "Privacy_ScreenCapture"
        }
        // A constant string with a fixed scheme always parses; a failure here is a typo.
        // swiftlint:disable:next force_unwrapping
        return URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)")!
    }

    /// Open `url` in System Settings: the shipping opener.
    static func openInSystemSettings(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    /// The asks the person switched on, as the store holds them.
    public private(set) var optIns: GrantOptIns = .none
    /// What macOS said, for each switched-on grant, the last time it was read.
    public private(set) var states: [GrantOptIn: CapabilityState] = [:]

    @ObservationIgnored private let requester: any GrantRequesting
    @ObservationIgnored private var watch: Task<Void, Never>?
    /// Called after a read that changed a state, so the composition root can redraw the cockpit
    /// and let the judgement read with the grant it now has.
    @ObservationIgnored var onChange: (() -> Void)?

    init(requester: any GrantRequesting) {
        self.requester = requester
    }

    /// What macOS lets the app do for `grant`: `notRequested` unless the person switched it on.
    public func state(of grant: GrantOptIn) -> CapabilityState {
        optIns.isEnabled(grant) ? states[grant] ?? .notRequested : .notRequested
    }

    /// Whether a watch is running.
    var isWatching: Bool { watch != nil }

    /// Take the switches from the store, and read the grants they cover.
    func apply(_ optIns: GrantOptIns) {
        if self.optIns != optIns { self.optIns = optIns }
        refresh()
        if allSwitchedOnGrantsAreAllowed { stopWatching() }
    }

    /// Read every switched-on grant without asking. `true` when anything changed. `notify` is
    /// `false` from the cockpit tick, which is already redrawing everything `onChange` would.
    @discardableResult
    func refresh(notify: Bool = true) -> Bool {
        var read: [GrantOptIn: CapabilityState] = [:]
        for grant in GrantOptIn.allCases where optIns.isEnabled(grant) {
            read[grant] = GrantGate.state(of: grant, optIns: optIns, using: requester)
        }
        guard read != states else { return false }
        states = read
        if notify { onChange?() }
        return true
    }

    /// Read the grants every `pollInterval` until each switched-on one is allowed, or for
    /// `pollLimit` reads. A second call restarts the count rather than starting a second watch.
    func watchUntilAllowed() {
        stopWatching()
        guard !allSwitchedOnGrantsAreAllowed else { return }
        watch = Task { [weak self] in
            for _ in 0..<Self.pollLimit {
                try? await Task.sleep(for: Self.pollInterval)
                guard let self, !Task.isCancelled else { return }
                self.refresh()
                if self.allSwitchedOnGrantsAreAllowed { break }
            }
            self?.watch = nil
        }
    }

    func stopWatching() {
        watch?.cancel()
        watch = nil
    }

    private var allSwitchedOnGrantsAreAllowed: Bool {
        GrantOptIn.allCases
            .filter(optIns.isEnabled)
            .allSatisfy { states[$0] == .available }
    }
}
