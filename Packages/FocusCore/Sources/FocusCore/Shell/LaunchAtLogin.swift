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

    /// **Which sentence the pane draws under the switch, if any** (F-138, e10 §7.3 H7.3).
    ///
    /// A named answer rather than a chain of `if`s in the view, because the hostile criterion this
    /// row has to clear is *"the four statuses map to fewer than four distinct sentences"* — two
    /// statuses sharing a drawing is a lie about one of them. With the footnote as a value, the
    /// drawing of a status is `(isOn, isAdjustable, footnote)` and a fold can say whether the four
    /// are really four.
    public enum Footnote: String, Sendable, CaseIterable, Hashable, Codable {
        /// Registered, and waiting for the person to approve it in Login Items settings. Drawn
        /// beside the one button this app can honestly offer: the place they can approve it.
        case approval
        /// The service cannot find this bundle, so the switch would fail if it moved.
        case unavailable
    }

    /// The footnote this status owes, or none.
    public var footnote: Footnote? {
        switch status {
        case .requiresApproval: .approval
        case .notFound: .unavailable
        case .enabled, .notRegistered: nil
        }
    }

    /// Whether the pane draws the footnote that sends the person to Login Items settings.
    public var needsApproval: Bool { footnote == .approval }

    /// **What the person is shown for this state, as a value.** Two statuses with the same
    /// drawing are two statuses one of which is being lied about.
    public var drawing: String {
        "on=\(isOn) adjustable=\(isAdjustable) footnote=\(footnote?.rawValue ?? "none")"
    }

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

/// **One cell of the launch-at-login fold** (F-138, e10 §7.3).
///
/// The acceptance criterion D-12 was given is a fold and not three examples: three session
/// histories against all four service states, twelve cells, each saying whether the offer is made,
/// exactly what is drawn, and whether registration is possible at all. A suite that tests three
/// of them is green on an app that shows nothing when macOS asks the person to approve the item —
/// which is the single likeliest real-world state (**H7.1**).
public struct LaunchAtLoginCell: Sendable, Equatable, Hashable {
    public let status: LoginItemStatus
    public let completedSessions: Int

    public init(status: LoginItemStatus, completedSessions: Int) {
        self.status = status
        self.completedSessions = completedSessions
    }

    /// (a) whether the offer is made.
    public var offersToRegister: Bool {
        LaunchAtLoginOffer.shouldOffer(
            status: status,
            completedSessions: completedSessions,
            alreadyOffered: false
        )
    }

    /// (b) exactly what is drawn for this state.
    public var drawing: String { LaunchAtLogin(status: status).drawing }

    /// (c) whether registration is possible — the switch may be moved.
    public var registrationIsPossible: Bool { LaunchAtLogin(status: status).isAdjustable }

    /// A name for the cell, so a fold can say which one it reached.
    public var name: String { "\(status.rawValue)@\(completedSessions)" }
}

/// **The twelve cells, folded over the two vocabularies rather than listed** (F-138).
///
/// `LoginItemStatus.allCases` and nothing else, so a fifth service state joins the fold the day it
/// exists instead of the day somebody remembers. The session histories are the three that differ:
/// none, the first one, and more than one.
public enum LaunchAtLoginFold {
    /// None, the first, and more than one. `1` is the boundary the rule turns on and `0` and `3`
    /// are its two sides; a fourth count would test the same three answers again.
    public static let sessionCounts = [0, 1, 3]

    public static var cells: [LaunchAtLoginCell] {
        LoginItemStatus.allCases.flatMap { status in
            sessionCounts.map { LaunchAtLoginCell(status: status, completedSessions: $0) }
        }
    }

    /// The count a suite asserts it reached. A cell no input can produce is a cell the fold does
    /// not test.
    public static var cellCount: Int { LoginItemStatus.allCases.count * sessionCounts.count }

    /// **H7.3 as a number.** Four statuses that draw fewer than four distinct things are four
    /// statuses one of which is being lied about.
    public static var distinctDrawings: Int {
        Set(LoginItemStatus.allCases.map { LaunchAtLogin(status: $0).drawing }).count
    }
}
