import FocusCore
import FocusUI
import Foundation
import SwiftData
import Testing

@testable import FocusHost

/// **The twelve cells of opening at login, driven through the real composition root** (F-138,
/// D-12, e10 plan §7.3).
///
/// `LaunchAtLoginHostTests` beside this file holds the wiring — that accepting registers, that
/// declining is recorded, that the switch is read and not remembered. What it does not hold is a
/// **fold**: it drives four states out of twelve, and the eight it leaves are where the likeliest
/// real-world defect lives. The plan's hostile criteria say so directly:
///
/// * **H7.1** — the fold is written and `requiresApproval` is unreachable because the double never
///   returns it. A green suite of that shape still permits an app that shows nothing at all when
///   macOS asks the person to approve the login item, which is the single most likely state a
///   person will actually meet. So this suite asserts the **reached-cell count is twelve** and
///   that every cell it reached was reached through the composition root, not computed beside it.
/// * **H7.2** — the offer appears at first launch. Every cell records whether the recording double
///   was asked to register, and the fold asserts the total is zero: nothing in this suite, and
///   nothing in any lane of this programme, calls `SMAppService.register()`.
/// * **H7.3** — the four statuses map to fewer than four distinct sentences. Two statuses sharing a
///   drawing is a lie about one of them, so the drawings are compared as a set.
///
/// **Nothing here registers anything.** `LaunchAtLoginDouble` stands in for `SMAppService` in every
/// cell; `CompositionRootWireTests.root(clock:)` defaults to one, so a suite cannot reach the real
/// service by forgetting to inject.
@Suite("Opening at login, all twelve cells", .serialized)
@MainActor
struct LaunchAtLoginFoldTests {
    /// What the composition root really did for one cell, read back out of it.
    struct Observed: Equatable {
        var offersToRegister: Bool
        var drawing: String
        var registrationIsPossible: Bool
        var registerCalls: Int
    }

    /// Drive one cell through the root and read the three facts the criterion names.
    ///
    /// The session history is made by **finishing real sessions**, never by writing a flag: D-12's
    /// rule is that the predicate reads the store's count of completed sessions, and a flag would
    /// be true on a Mac whose store was wiped and false on one where the session completed after
    /// the flag was written.
    static func observe(_ cell: LaunchAtLoginCell) -> Observed {
        let service = LaunchAtLoginDouble(status: cell.status)
        let root = CompositionRootWireTests.root(clock: FixedMonotonicClock(), loginItem: service)
        defer { CompositionRootWireTests.tearDown(root) }
        root.joinHosts()

        for _ in 0 ..< cell.completedSessions {
            root.sessionActions.startSession(kind: .openEnded, plannedSeconds: nil, deadlineAt: nil)
            root.sessionActions.completeSession()
        }
        // Completing a session already refreshes the offer; asked for again so that a cell with no
        // session at all is read after the same call the others were, rather than at whatever the
        // launch happened to leave behind.
        root.refreshLaunchAtLoginOffer()

        let launch = root.settingsConnection().launchAtLogin
        return Observed(
            offersToRegister: root.cockpitState.showsLaunchAtLoginOffer,
            drawing: launch.drawing,
            registrationIsPossible: launch.isAdjustable,
            registerCalls: service.enabledCalls.count
        )
    }

    /// **The answer this suite expects, written out rather than asked of the code under test.**
    ///
    /// `LaunchAtLoginCell` computes its three answers through `LaunchAtLoginOffer.shouldOffer` and
    /// `LaunchAtLogin`, which are the very things this suite exists to hold. Comparing the root's
    /// behaviour to them proves the *wiring* and nothing about the rule: delete the status guard
    /// from `shouldOffer` and both sides move together, and the suite stays green — measured, and
    /// the reason this table exists. Here the three answers are spelled out from D-12's sentences.
    static func expected(_ cell: LaunchAtLoginCell) -> Observed {
        let offers = cell.status == .notRegistered && cell.completedSessions >= 1
        let on = cell.status == .enabled || cell.status == .requiresApproval
        let adjustable = cell.status == .enabled || cell.status == .notRegistered
        let footnote: String
        switch cell.status {
        case .requiresApproval: footnote = "approval"
        case .notFound: footnote = "unavailable"
        case .enabled, .notRegistered: footnote = "none"
        }
        return Observed(
            offersToRegister: offers,
            drawing: "on=\(on) adjustable=\(adjustable) footnote=\(footnote)",
            registrationIsPossible: adjustable,
            registerCalls: 0
        )
    }

    /// **The fold.** Every cell of `LoginItemStatus.allCases × {0, 1, 3}`, each asserting the three
    /// things the criterion names, and the reached count asserted against the vocabulary's own
    /// product rather than against twelve written down here.
    @Test("every cell of the launch-at-login fold is reached, and answers as the rule says")
    func theTwelveCells() throws {
        var reached: [String: Observed] = [:]

        for cell in LaunchAtLoginFold.cells {
            let observed = Self.observe(cell)
            let expected = Self.expected(cell)
            reached[cell.name] = observed

            // (a) whether the offer is shown.
            #expect(
                observed.offersToRegister == expected.offersToRegister,
                """
                \(cell.name): the cockpit \(observed.offersToRegister ? "offered" : "did not offer") \
                to open at login where D-12 says \(expected.offersToRegister)
                """
            )
            // (b) exactly what is drawn.
            #expect(
                observed.drawing == expected.drawing,
                "\(cell.name): the pane drew \(observed.drawing) where D-12 says \(expected.drawing)"
            )
            // (c) whether registration is possible.
            #expect(
                observed.registrationIsPossible == expected.registrationIsPossible,
                """
                \(cell.name): the switch was \(observed.registrationIsPossible ? "movable" : "fixed") \
                where D-12 says \(expected.registrationIsPossible)
                """
            )
            // …and the cell type's own three answers agree with the sentences, so the fold the
            // self-check publishes is the fold this suite drove.
            #expect(cell.offersToRegister == expected.offersToRegister, "\(cell.name): (a)")
            #expect(cell.drawing == expected.drawing, "\(cell.name): (b)")
            #expect(cell.registrationIsPossible == expected.registrationIsPossible, "\(cell.name): (c)")
        }

        #expect(
            reached.count == LaunchAtLoginFold.cellCount,
            """
            the fold reached \(reached.count) of \(LaunchAtLoginFold.cellCount) cells — a cell no \
            input can produce is a cell this suite does not test (H7.1)
            """
        )
        // Every status really occurred. The count above is satisfied by twelve cells that are all
        // the same status if the double ignored what it was built with.
        #expect(
            Set(LoginItemStatus.allCases.map(\.rawValue))
                == Set(reached.keys.map { String($0.split(separator: "@")[0]) }),
            "the fold reached every service state, including requiresApproval (H7.1)"
        )
    }

    /// **H7.2, and the rule the whole seam exists for.** `register()` writes into the person's
    /// Login Items; a suite that called it would change the machine it is measuring, and it would
    /// keep changing it across reboots.
    @Test("no cell of the fold registers anything")
    func theFoldRegistersNothing() {
        let calls = LaunchAtLoginFold.cells.reduce(0) { $0 + Self.observe($1).registerCalls }
        #expect(calls == 0, "the fold asked the service to register \(calls) time(s)")
    }

    /// **H7.2's other half: never on a first launch.** A cold root with no session finished offers
    /// nothing, whatever the service says — including the state in which the app is already
    /// registered, where an offer would be the app failing to know its own state.
    @Test("no service state makes the offer before a session has been finished")
    func nothingIsOfferedColdColdCold() {
        for status in LoginItemStatus.allCases {
            let observed = Self.observe(LaunchAtLoginCell(status: status, completedSessions: 0))
            #expect(!observed.offersToRegister, "a cold launch offered to open at login (\(status))")
            #expect(observed.registerCalls == 0)
        }
    }

    /// **H7.3.** Four statuses, four drawings. Written as a set comparison rather than four
    /// inequalities so that a fifth status added to the vocabulary is covered the day it exists.
    @Test("the four service states draw four distinct things")
    func fourStatesFourDrawings() {
        let drawings = Set(LoginItemStatus.allCases.map { LaunchAtLogin(status: $0).drawing })
        #expect(
            drawings.count == LoginItemStatus.allCases.count,
            """
            \(LoginItemStatus.allCases.count) service states draw \(drawings.count) distinct \
            things: \(drawings.sorted())
            """
        )
        #expect(drawings.count == LaunchAtLoginFold.distinctDrawings)
    }

    /// The footnote is a value, and each value draws a sentence of its own. Asserting that the
    /// *values* differ is not asserting that a person is told something different, so the resolved
    /// sentences are compared as well.
    ///
    /// That the sentences come from the catalog at all — rather than echoing their own keys because
    /// the catalog was copied and not compiled — is `StringCatalogTests`' assertion over every key,
    /// in the lane where the catalog is compiled. This one is about the two being two.
    @Test("each footnote draws a sentence of its own")
    func eachFootnoteIsASentence() {
        let sentences = [
            ShellStrings.string(.settingsLaunchAtLoginApproval),
            ShellStrings.string(.settingsLaunchAtLoginUnavailable)
        ]
        for sentence in sentences {
            #expect(!sentence.isEmpty)
        }
        #expect(Set(sentences).count == LaunchAtLogin.Footnote.allCases.count)
    }
}
