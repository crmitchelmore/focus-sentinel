import Foundation

/// **What the system says about opening this app at login** (D-12, focus-odz.4).
///
/// A named vocabulary rather than a `Bool`, because "on" and "off" are not the states
/// `SMAppService` actually has. The middle one is the whole reason this type exists: a person can
/// register the app and then have the registration sit **waiting for their approval** in Login
/// Items, in which case a switch drawn as "on" is telling them something that is not yet true, and
/// a switch drawn as "off" invites them to register it again — which does nothing, because it
/// already is.
///
/// `CaseIterable` for the reason every folded vocabulary in this repository is: the day a fourth
/// state exists, every table over this one fails to compile rather than answering for it silently.
public enum LoginItemStatus: String, Sendable, CaseIterable, Hashable, Codable {
    /// The app is not registered. The only state in which the offer may be made.
    case notRegistered
    /// Registered, approved, and the app will open at login.
    case enabled
    /// Registered, and **waiting for the person to approve it in Login Items settings**. The
    /// switch cannot move from here: nothing this app does changes it, and only the person can.
    case requiresApproval
    /// The service could not find this app — an unregistered bundle, or one that has moved. It is
    /// a real reading and not an error: the switch is unavailable and says why.
    case notFound
}

/// **Everything a surface needs in order to draw the launch-at-login control** (focus-odz.4).
///
/// Derived from the status and nothing else. The rule D-12 turns on is that the displayed state is
/// **read from the service**, never from a stored `Bool`: a person who removes the app from Login
/// Items in System Settings has changed the truth, and a switch reading its own remembered answer
/// would go on saying "on" for ever.
public struct LaunchAtLogin: Sendable, Equatable, Hashable {
    public var status: LoginItemStatus

    public init(status: LoginItemStatus = .notRegistered) {
        self.status = status
    }

    /// What the switch draws. `requiresApproval` reads **on**, because the person has asked for
    /// it — what is missing is their approval, which the footnote is for, not their intent.
    public var isOn: Bool {
        switch status {
        case .enabled, .requiresApproval: true
        case .notRegistered, .notFound: false
        }
    }

    /// Whether the switch may be moved at all.
    ///
    /// It may not while approval is outstanding — nothing this app does changes that state — and
    /// it may not when the service cannot find the bundle, where a registration would fail.
    public var isAdjustable: Bool {
        switch status {
        case .enabled, .notRegistered: true
        case .requiresApproval, .notFound: false
        }
    }

    /// Whether the pane draws the footnote that sends the person to Login Items settings.
    public var needsApproval: Bool { status == .requiresApproval }

    /// What the app believes before it has asked. Not a guess at "off": `notRegistered` is what
    /// an app that has never been registered really is, which is every first launch.
    public static let unregistered = LaunchAtLogin()
}

/// What a click on the launch-at-login control asks for.
public enum LaunchAtLoginAction: Sendable, Equatable, Hashable {
    /// The state the person asked **for**, not a toggle, so a pane built a moment ago cannot
    /// invert it — the same rule `MenuBarAction.setSensingPaused` states.
    case setEnabled(Bool)
    /// Take them to Login Items in System Settings, which is the only place the approval this app
    /// cannot grant itself can be given.
    case openSystemSettings
}

/// What a click on the cockpit's one-time offer asks for.
public enum LaunchAtLoginOfferAction: Sendable, Equatable, Hashable {
    /// Turn it on. The row disappears either way: it is an offer, made once.
    case accept
    /// *"Not now."* Also made once — D-12's rule is that the app asks and does not nag.
    case dismiss
}

/// Something that can read and change this app's login-item registration.
///
/// A protocol so that every lane in this programme can drive the offer logic without ever
/// **registering** anything: `SMAppService.register()` writes into the person's Login Items, and a
/// test suite or a gate stage that did that would be changing the machine it is measuring. The
/// self-check reads the status and never calls either verb, for exactly the same reason.
@MainActor
public protocol LoginItemControlling: AnyObject {
    /// Read from the service every time. Never cached, and never a stored `Bool` (D-12).
    var status: LoginItemStatus { get }
    /// Register or unregister, and report what the service then says.
    @discardableResult
    func setEnabled(_ enabled: Bool) -> LoginItemStatus
    /// Open Login Items in System Settings.
    func openSystemSettings()
}

/// **Whether the one-time offer may be made** (D-12, focus-odz.4).
///
/// A pure decision over three facts, so the rule is held in one place and drivable with a double.
/// Every clause is a decision:
///
/// * **Never on a first launch.** The offer follows a *completed session*, which is the first
///   moment the app has done the thing it exists to do. An app that asks to be added to Login
///   Items before it has been any use is asking for a commitment it has not earned.
/// * **Never twice.** The app asks once and does not nag; the record of the asking is a date in
///   the store, so it survives the launch that made it.
/// * **Only when it is not already registered.** With the app already opening at login, or with
///   an approval outstanding in System Settings, there is nothing to offer — and offering anyway
///   would be the app failing to know its own state, which is the defect D-12's "read the status,
///   never a stored Bool" rule exists to prevent.
public enum LaunchAtLoginOffer {
    public static func shouldOffer(
        status: LoginItemStatus,
        completedSessions: Int,
        alreadyOffered: Bool
    ) -> Bool {
        guard status == .notRegistered else { return false }
        guard !alreadyOffered else { return false }
        return completedSessions >= 1
    }
}
