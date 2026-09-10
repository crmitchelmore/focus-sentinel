import FocusCore
import FocusUI
import Foundation
import SwiftData
import Testing

@testable import FocusHost

/// **The double every lane in this programme uses instead of `SMAppService`** (D-12,
/// focus-odz.4).
///
/// `register()` writes into the person's Login Items. A test suite or a gate stage that called it
/// would be changing the machine it is measuring — so the shipping adapter is injected, this
/// stands in its place, and `CompositionRootWireTests.root(clock:)` defaults to one so that no
/// suite can reach the real service by forgetting to.
@MainActor
final class LaunchAtLoginDouble: LoginItemControlling {
    var status: LoginItemStatus
    private(set) var enabledCalls: [Bool] = []
    private(set) var settingsOpened = 0

    init(status: LoginItemStatus = .notRegistered) {
        self.status = status
    }

    @discardableResult
    func setEnabled(_ enabled: Bool) -> LoginItemStatus {
        enabledCalls.append(enabled)
        status = enabled ? .enabled : .notRegistered
        return status
    }

    func openSystemSettings() { settingsOpened += 1 }
}

/// **The composition root's half of opening at login** (D-12, focus-odz.4).
///
/// `LaunchAtLoginTests` holds the rule; this holds the wiring — that the offer waits for a
/// completed session, that both answers to it record the asking, that the switch's position is
/// read from the service rather than remembered, and that the pane's controls reach the service at
/// all.
@Suite("Opening at login, in the composition root", .serialized)
@MainActor
struct LaunchAtLoginHostTests {
    static func root(_ service: LaunchAtLoginDouble) -> AppComposition {
        CompositionRootWireTests.root(clock: FixedMonotonicClock(), loginItem: service)
    }

    /// Finish one session, which is the signal D-12 says the offer waits for.
    static func completeASession(in root: AppComposition) {
        root.sessionActions.startSession(kind: .openEnded, plannedSeconds: nil, deadlineAt: nil)
        root.sessionActions.completeSession()
    }

    /// **Never on a first launch**, which is the half D-12 is most about.
    @Test("with no session ever finished the cockpit makes no offer")
    func noOfferBeforeAFinishedSession() throws {
        let service = LaunchAtLoginDouble()
        let root = Self.root(service)
        defer { CompositionRootWireTests.tearDown(root) }
        root.joinHosts()

        #expect(root.finishedSessionCount == 0)
        #expect(!root.cockpitState.showsLaunchAtLoginOffer)
    }

    /// …and after one, it does. The pair is the claim: either reading alone is satisfied by a
    /// predicate that answers the same thing always.
    @Test("after a first finished session the cockpit makes the offer")
    func theOfferFollowsTheFirstFinishedSession() throws {
        let service = LaunchAtLoginDouble()
        let root = Self.root(service)
        defer { CompositionRootWireTests.tearDown(root) }
        root.joinHosts()

        Self.completeASession(in: root)

        #expect(root.finishedSessionCount == 1)
        #expect(root.cockpitState.showsLaunchAtLoginOffer)
    }

    /// **Accepting registers and ends the offer**, and the ending is read from the service rather
    /// than from a flag: the status moved, and the status is what the decision reads.
    @Test("accepting the offer registers the app and takes the row away")
    func acceptingRegistersAndEndsTheOffer() throws {
        let service = LaunchAtLoginDouble()
        let root = Self.root(service)
        defer { CompositionRootWireTests.tearDown(root) }
        root.joinHosts()
        Self.completeASession(in: root)
        #expect(root.cockpitState.showsLaunchAtLoginOffer)

        root.perform(LaunchAtLoginOfferAction.accept)

        #expect(service.enabledCalls == [true])
        #expect(service.status == .enabled)
        #expect(!root.cockpitState.showsLaunchAtLoginOffer)
    }

    /// **"Not now" is an answer, not a postponement.** It registers nothing and is recorded, so
    /// the row does not come back — in this launch or the next one.
    @Test("declining the offer registers nothing and is never asked again")
    func decliningIsRecordedAndRegistersNothing() throws {
        let service = LaunchAtLoginDouble()
        let root = Self.root(service)
        defer { CompositionRootWireTests.tearDown(root) }
        root.joinHosts()
        Self.completeASession(in: root)

        root.perform(LaunchAtLoginOfferAction.dismiss)

        #expect(service.enabledCalls.isEmpty, "declining registered the app anyway")
        #expect(service.status == .notRegistered)
        #expect(!root.cockpitState.showsLaunchAtLoginOffer)
        // …and it is in the store, which is what the *next* launch reads.
        #expect(
            FocusStore.shellState(in: root.modelContainer.mainContext).hasOfferedLaunchAtLogin
        )
    }

    /// Finding the switch in Settings and turning it on settles the offer too: somebody who has
    /// already said yes must not then be asked in the footer whether they would like to.
    @Test("using the Settings switch settles the offer as well")
    func theSettingsSwitchSettlesTheOffer() throws {
        let service = LaunchAtLoginDouble()
        let root = Self.root(service)
        defer { CompositionRootWireTests.tearDown(root) }
        root.joinHosts()
        Self.completeASession(in: root)

        root.perform(LaunchAtLoginAction.setEnabled(true))

        #expect(service.enabledCalls == [true])
        #expect(
            FocusStore.shellState(in: root.modelContainer.mainContext).hasOfferedLaunchAtLogin
        )
        #expect(!root.cockpitState.showsLaunchAtLoginOffer)
    }

    /// **The displayed state is read from the service, never from a stored `Bool`** (D-12).
    ///
    /// The service is moved underneath the root — which is what happens when somebody removes the
    /// app from Login Items in System Settings — and the pane's next reading has to follow it. A
    /// remembered answer would go on saying "on" for ever.
    @Test("the pane reads the switch from the service every time it is built")
    func theSwitchIsReadNotRemembered() throws {
        let service = LaunchAtLoginDouble(status: .enabled)
        let root = Self.root(service)
        defer { CompositionRootWireTests.tearDown(root) }
        root.joinHosts()

        #expect(root.settingsConnection().launchAtLogin.status == .enabled)

        // The person removes it in System Settings. Nothing tells this process.
        service.status = .notRegistered
        #expect(root.settingsConnection().launchAtLogin.status == .notRegistered)

        // …and an approval the app cannot grant reaches the pane as the state that says so.
        service.status = .requiresApproval
        let connection = root.settingsConnection()
        #expect(connection.launchAtLogin.needsApproval)
        #expect(!connection.launchAtLogin.isAdjustable)
    }

    /// The footnote's button is the honest response to a permission this app cannot grant itself.
    @Test("the pane's deep link reaches the service's own settings verb")
    func theDeepLinkReachesTheService() throws {
        let service = LaunchAtLoginDouble(status: .requiresApproval)
        let root = Self.root(service)
        defer { CompositionRootWireTests.tearDown(root) }
        root.joinHosts()

        root.perform(LaunchAtLoginAction.openSystemSettings)

        #expect(service.settingsOpened == 1)
        // Opening System Settings is not an answer to the offer: nothing was registered and
        // nothing was declined.
        #expect(service.enabledCalls.isEmpty)
    }
}
