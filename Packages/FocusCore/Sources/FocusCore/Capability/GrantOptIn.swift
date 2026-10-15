import Foundation

/// **A grant the person may switch on** (focus-exdi.4, owner ruling 2026-09-08).
///
/// The programme shipped under PD-1, the zero-grant doctrine: the app asks macOS for nothing, and
/// invariant I-3 proves it twice — no request selector in either configuration's Mach-O, and no
/// authorisation surface on screen while the app runs. The owner overruled the absolute form of
/// it: the app **may** ask, for these two grants, *only* where the person has switched the ask
/// on in Settings.
///
/// So the doctrine becomes a conditional one, and it is worth stating exactly, because a
/// conditional invariant that nobody writes down is an invariant nobody can check:
///
/// > **The app asks for nothing unless the person switched that ask on.** On a default install
/// > nothing is asked, nothing prompts, and the capability table reads exactly as it did under
/// > PD-1. The only route from "not asked" to "asked" is a control the person operated.
///
/// Two grants, and no more: each one names the reading it would unlock, so a switch is never a
/// blank cheque. A third case here is a change to the doctrine and has to be argued for.
public enum GrantOptIn: String, Sendable, CaseIterable, Hashable, Codable, Identifiable {
    /// Accessibility: the front window's title, or the selected row or main heading inside it,
    /// in the frontmost application, reduced on device to the selected item (issue #24, owner's ruling 2026-10-15). What `e07` always meant by
    /// "with consent" (`Capability.accessibilityWindowContext`).
    case accessibilityWindowContext
    /// Screen Recording: pixel capture, parked by the Feasibility Court as dissent D-04 and
    /// still parked — the switch exists, and nothing yet reads what it would unlock.
    case screenCapture

    public var id: String { rawValue }

    /// The capability the grant would move off `.notRequested`.
    public var capability: Capability {
        switch self {
        case .accessibilityWindowContext: .accessibilityWindowContext
        case .screenCapture: .screenCapture
        }
    }

    /// Whether anything in this build actually reads what the grant unlocks.
    ///
    /// Accessibility is read (issue #24): `FocusHost.SystemSelectedItemReader` reads the front
    /// window's title — or, when that names nothing, the selected row or main heading inside it —
    /// of the frontmost application, on device, and reduces it to a `SelectedItem` before
    /// anything keeps it. Screen Recording is still parked. The pane says
    /// so beside a switch nothing reads, rather than implying a feature that does not exist — a
    /// switch that asks a person for a permission and then uses it for nothing is the worst
    /// version of this change, and this is the flag that keeps the copy honest.
    public var isConsumedByThisBuild: Bool {
        switch self {
        case .accessibilityWindowContext: true
        case .screenCapture: false
        }
    }

    /// Total: a stored key this build does not know reads as `nil` rather than throwing (R-45).
    public static func decode(_ raw: String) -> GrantOptIn? {
        allCases.first { $0.rawValue == raw }
    }
}

/// The set of grants the person has switched on.
public struct GrantOptIns: Sendable, Equatable, Hashable, Codable {
    public private(set) var enabled: Set<GrantOptIn>

    public init(enabled: Set<GrantOptIn> = []) {
        self.enabled = enabled
    }

    /// The shipped state: nothing switched on, so nothing may be asked for.
    public static let none = GrantOptIns()

    public var asksForNothing: Bool { enabled.isEmpty }

    public func isEnabled(_ grant: GrantOptIn) -> Bool { enabled.contains(grant) }

    public mutating func set(_ grant: GrantOptIn, to isEnabled: Bool) {
        if isEnabled { enabled.insert(grant) } else { enabled.remove(grant) }
    }
}

/// **The one seam that may ask macOS for a grant** (focus-exdi.4).
///
/// A protocol so that the request lives behind one named door: `FocusCore` describes the ask and
/// holds the rule about when it is permitted, and only `FocusHost` implements it against the
/// system APIs. Every test drives a recording double, which is what lets the suite prove "asked
/// exactly once, and only after the switch" without any Mac ever showing a dialog.
@MainActor
public protocol GrantRequesting: AnyObject {
    /// Ask the system for this grant, and answer with the state it left the app in.
    ///
    /// Called only through `GrantGate.request(_:optIns:using:)`, which is where the rule lives.
    func requestGrant(_ grant: GrantOptIn) -> CapabilityState

    /// Read the grant's current state without asking for anything.
    func grantState(_ grant: GrantOptIn) -> CapabilityState

    /// How many times this object has been asked to request a grant, ever.
    ///
    /// The counter invariant I-3 already reads for notifications, generalised: on a default
    /// install it is zero, and the self-check says so.
    var requestCount: Int { get }
}

/// **Where the conditional doctrine is enforced, once** (focus-exdi.4).
///
/// Every route to a request goes through here, so "the app asked for something the person never
/// switched on" is one function's behaviour rather than a property of every call site.
public enum GrantGate {
    /// Ask, if and only if the person switched this grant on.
    ///
    /// Returns the resulting state, or `.notRequested` when the ask was refused by the gate —
    /// which is the same state the capability was already in, so a caller that ignores the rule
    /// still cannot observe a grant it did not earn.
    @MainActor
    @discardableResult
    public static func request(
        _ grant: GrantOptIn,
        optIns: GrantOptIns,
        using requester: any GrantRequesting
    ) -> CapabilityState {
        guard optIns.isEnabled(grant) else { return .notRequested }
        return requester.requestGrant(grant)
    }

    /// What the capability table should say about a grant, given the opt-ins.
    ///
    /// Not switched on is `.notRequested`, always and without asking the system anything: a Mac
    /// where somebody granted Accessibility to this app by hand still reads `.notRequested`
    /// while the switch is off, because the app has not taken it up. That is the half of I-3
    /// which says the app does not *hold* what it did not ask for.
    @MainActor
    public static func state(
        of grant: GrantOptIn,
        optIns: GrantOptIns,
        using requester: any GrantRequesting
    ) -> CapabilityState {
        guard optIns.isEnabled(grant) else { return .notRequested }
        return requester.grantState(grant)
    }
}
