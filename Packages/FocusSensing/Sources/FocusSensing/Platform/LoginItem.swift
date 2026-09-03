import AppKit
import FocusCore
import ServiceManagement

/// **The system's own login-item registration, behind `FocusCore`'s protocol** (D-12,
/// focus-odz.4).
///
/// `SMAppService.mainApp` is the supported way for a bundled app to add itself to Login Items on
/// macOS 13 and later: no helper bundle, no `SMLoginItemSetEnabled`, no login-item `plist` for a
/// person to find and not understand. It is a platform adapter, which is what this package is for.
///
/// ## The status is read, never remembered (D-12)
///
/// `status` asks the service every time. A stored `Bool` would go on saying "on" after somebody
/// removed the app from Login Items in System Settings — the truth changed outside this process,
/// and a switch that answers from its own memory is a switch that lies. That is the whole rule
/// D-12 states, and it is why this type has no stored state at all.
///
/// ## `.requiresApproval` is a real answer, not an error
///
/// Registering can leave the item **waiting for the person's approval**, which nothing this app
/// does can grant. `openSystemSettings()` is the honest response: it takes them to the one place
/// the approval can be given.
///
/// ## Nothing in the gate ever calls `setEnabled`
///
/// Registering writes into the person's Login Items. A test suite or a gate stage that did that
/// would be changing the machine it is measuring — so the self-check reads `status` and calls
/// neither verb, and every test drives `LaunchAtLoginOffer` through a double.
@MainActor
public final class SMAppServiceLoginItem: LoginItemControlling {
    private let service: SMAppService

    public init(service: SMAppService = .mainApp) {
        self.service = service
    }

    public var status: LoginItemStatus {
        Self.decode(service.status)
    }

    @discardableResult
    public func setEnabled(_ enabled: Bool) -> LoginItemStatus {
        do {
            if enabled {
                try service.register()
            } else {
                try service.unregister()
            }
        } catch {
            // Swallowed on purpose, and the reading below is why. What a person needs to know is
            // what the switch says **now**, and the service is the authority on that: a thrown
            // error whose registration nonetheless landed, or a silent failure that left the app
            // unregistered, are both answered correctly by asking again. Reporting the error
            // instead would put a second source of truth beside the one D-12 names.
            return status
        }
        return status
    }

    public func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    /// **The service's status, folded into the vocabulary the shell draws** (focus-odz.4).
    ///
    /// An exhaustive switch over the cases this SDK declares, with `@unknown default` answering
    /// `notFound` — the reading that makes the switch unavailable and says so. A future case this
    /// build cannot interpret must not be drawn as "on": telling somebody the app opens at login
    /// when it does not is the one wrong answer here.
    ///
    /// `nonisolated` and `static` so the table is a value a test can drive without a service.
    nonisolated public static func decode(_ status: SMAppService.Status) -> LoginItemStatus {
        switch status {
        case .notRegistered: .notRegistered
        case .enabled: .enabled
        case .requiresApproval: .requiresApproval
        case .notFound: .notFound
        @unknown default: .notFound
        }
    }
}
