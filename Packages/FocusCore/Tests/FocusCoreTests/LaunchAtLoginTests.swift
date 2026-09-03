import Foundation
import Testing

@testable import FocusCore

/// **Opening at login: opt-in, offered once, and never on a first launch** (D-12, focus-odz.4).
///
/// Every assertion here is over pure values, and that is not a convenience. `SMAppService
/// .register()` writes into the person's Login Items, so a suite that exercised the real service
/// would be changing the machine it is measuring — which is exactly why `LoginItemControlling`
/// exists and why the shipping adapter is injected rather than reached for.
@Suite("Opening at login")
struct LaunchAtLoginTests {
    /// **The switch's position is a projection of the status, and two states share one.**
    ///
    /// `requiresApproval` reads **on**, because the person has asked for it — what is missing is
    /// their approval, which the footnote is for, not their intent. Drawing it as off would invite
    /// them to register an app that already is registered, which does nothing.
    @Test("the switch reads on for the two states in which the person has asked for it")
    func theSwitchPosition() {
        #expect(LaunchAtLogin(status: .enabled).isOn)
        #expect(LaunchAtLogin(status: .requiresApproval).isOn)
        #expect(!LaunchAtLogin(status: .notRegistered).isOn)
        #expect(!LaunchAtLogin(status: .notFound).isOn)
    }

    /// **It may not be moved in the two states where moving it would do nothing.**
    ///
    /// Nothing this app does grants an outstanding approval, and a registration against a bundle
    /// the service cannot find fails — so a switch that could be flicked there would be a control
    /// that silently does nothing, which is the rule `CockpitView` states about the menu.
    @Test("the switch is unavailable exactly where moving it would change nothing")
    func theSwitchIsGuarded() {
        #expect(LaunchAtLogin(status: .enabled).isAdjustable)
        #expect(LaunchAtLogin(status: .notRegistered).isAdjustable)
        #expect(!LaunchAtLogin(status: .requiresApproval).isAdjustable)
        #expect(!LaunchAtLogin(status: .notFound).isAdjustable)
    }

    /// The footnote appears in exactly one state, and it is the one only the person can end.
    @Test("the approval footnote is drawn only while approval is outstanding")
    func theFootnoteIsNarrow() {
        for status in LoginItemStatus.allCases {
            #expect(
                LaunchAtLogin(status: status).needsApproval == (status == .requiresApproval)
            )
        }
    }

    /// **What the app believes before it has asked.** Not a guess at "off": `notRegistered` is
    /// what an app that has never been registered really is, which is every first launch.
    @Test("the default reading is 'not registered', which is a fact rather than a guess")
    func theDefaultIsAFact() {
        #expect(LaunchAtLogin.unregistered.status == .notRegistered)
        #expect(!LaunchAtLogin.unregistered.isOn)
    }

    // MARK: - The one-time offer

    /// **Never on a first launch**, which is the half D-12 is most about.
    @Test("with no session ever finished the offer is never made")
    func noOfferBeforeAFinishedSession() {
        #expect(
            !LaunchAtLoginOffer.shouldOffer(
                status: .notRegistered,
                completedSessions: 0,
                alreadyOffered: false
            )
        )
    }

    /// **Never twice.** The app asks once and does not nag, and *"not now"* is an answer.
    @Test("once offered, it is never offered again")
    func neverOfferedTwice() {
        #expect(
            !LaunchAtLoginOffer.shouldOffer(
                status: .notRegistered,
                completedSessions: 12,
                alreadyOffered: true
            )
        )
    }

    /// **Only when there is something to offer.** With the app already opening at login, or with
    /// an approval outstanding, offering would be the app failing to know its own state.
    @Test("only an unregistered app is offered anything", arguments: LoginItemStatus.allCases)
    func offeredOnlyWhenUnregistered(status: LoginItemStatus) {
        #expect(
            LaunchAtLoginOffer.shouldOffer(
                status: status,
                completedSessions: 1,
                alreadyOffered: false
            ) == (status == .notRegistered)
        )
    }

    /// The one state in which it is made, so the three refusals above are not the whole function.
    @Test("after a first finished session, an unregistered app is offered once")
    func theOfferIsMadeExactlyOnce() {
        #expect(
            LaunchAtLoginOffer.shouldOffer(
                status: .notRegistered,
                completedSessions: 1,
                alreadyOffered: false
            )
        )
    }

    /// A double, standing where `SMAppServiceLoginItem` stands. It is what every lane in the
    /// programme uses, and the reason is at the top of this file.
    @MainActor
    final class LoginItemDouble: LoginItemControlling {
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

    /// **The offer stops being made the moment it is accepted**, without anybody storing a flag
    /// about it: registering changes the status, and the status is what the decision reads.
    @Test("accepting the offer takes it off the screen through the service, not through a flag")
    @MainActor
    func acceptingEndsTheOffer() {
        let service = LoginItemDouble()
        #expect(
            LaunchAtLoginOffer.shouldOffer(
                status: service.status,
                completedSessions: 1,
                alreadyOffered: false
            )
        )

        service.setEnabled(true)

        #expect(service.enabledCalls == [true])
        #expect(service.status == .enabled)
        #expect(
            !LaunchAtLoginOffer.shouldOffer(
                status: service.status,
                completedSessions: 1,
                alreadyOffered: false
            )
        )
    }
}
