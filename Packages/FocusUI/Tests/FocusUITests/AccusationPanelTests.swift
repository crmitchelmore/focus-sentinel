import FocusCore
import Foundation
import SwiftUI
import Testing

@testable import FocusUI

/// The fixtures the accusation panel is drawn from.
///
/// Named rather than inline, so the snapshot names and the structural assertions are about the
/// same values and a reader of a failing baseline can find what produced it.
enum AccusationFixture {
    /// **The subject, with both halves** (focus-ebv). `safari.identifier` is what a rule, a
    /// snooze and a receipt are keyed on; `safari.displayName` is the only half a sentence may
    /// draw. Every fixture in the nudge suites is built through this, so a test that asserted on
    /// a raw identifier is asserting about the key rather than about what a person reads.
    static let safari = NudgeSubject.named("com.apple.Safari", runningName: "Safari")!

    /// Rung 2, with everything on offer: a named subject and a stored return anchor, which is
    /// the state the whole correction economy is reachable from.
    static func rungTwo(voice: NudgeVoice = .standard) -> AccusationPresentation {
        AccusationPresentation(
            rung: .panel,
            voice: voice,
            task: "Write the Q3 proposal",
            subject: Self.safari,
            dwelled: .seconds(720),
            returnTarget: "Pages"
        )
    }

    /// Drift across several applications. There is no single subject, so the body line and the
    /// two rule-writing actions are withdrawn rather than filled in with a guess.
    static let mixed = AccusationPresentation(
        rung: .panel,
        voice: .standard,
        task: "Write the Q3 proposal",
        subject: nil,
        dwelled: .seconds(900),
        returnTarget: "Pages"
    )

    /// No stored return anchor: "Back to …" is not offered at all (R-88).
    static let noReturnTarget = AccusationPresentation(
        rung: .panel,
        voice: .standard,
        task: "Write the Q3 proposal",
        subject: safari,
        dwelled: .seconds(600),
        returnTarget: nil
    )

    /// A running snooze, drawn as a visible countdown (R-87).
    static let snoozed = AccusationPresentation(
        rung: .panel,
        voice: .standard,
        task: "Write the Q3 proposal",
        subject: safari,
        dwelled: .seconds(600),
        returnTarget: "Pages",
        snoozeRemaining: .seconds(305)
    )
}

/// **The panel a person can answer back to** (R-86, D-07).
@Suite("The accusation panel carries the whole economy")
@MainActor
struct AccusationPanelTests {
    // MARK: - The economy is complete, and it is complete by construction

    /// Every action except the dismissal has a place in the panel, exactly once.
    ///
    /// `dismiss` is the exception on purpose: it is Escape and the close affordance, and a
    /// button labelled "ignore me" in a row of six would be a panel arguing with itself. The
    /// assertion is a **partition** rather than a subset, so an action added to
    /// `CorrectionAction` in a later epic fails this test rather than quietly never being shown.
    @Test("the display order is every correction action except the dismissal, each once")
    func displayOrderIsAPartition() {
        let ordered = AccusationPresentation.actionOrder

        #expect(Set(ordered).count == ordered.count)
        #expect(Set(ordered) == Set(CorrectionAction.allCases).subtracting([.dismiss]))
        #expect(!ordered.contains(.dismiss))
    }

    @Test("every offered action carries a deck line, and only the dismissal does not")
    func everyOfferedActionHasCopy() {
        for action in AccusationPresentation.actionOrder {
            #expect(action.copyKey != nil)
        }
        #expect(CorrectionAction.dismiss.copyKey == nil)
    }

    @Test("with a subject and a return anchor the whole economy is on offer")
    func fullEconomy() {
        let offered = AccusationFixture.rungTwo().offeredActions
        #expect(offered == AccusationPresentation.actionOrder)
        #expect(offered.contains(.thisIsRelevant))
        #expect(offered.contains(.notThisTime))
        #expect(offered.contains(.snooze))
        #expect(offered.contains(.changePriority))
        #expect(offered.contains(.pause))
        #expect(offered.contains(.returnToTask))
    }

    // MARK: - What is withdrawn, and why

    /// R-88: a "back to work" button with nowhere to go is a button that lies.
    @Test("with no stored return anchor the return action is not offered at all")
    func returnWithdrawnWithNoAnchor() {
        let offered = AccusationFixture.noReturnTarget.offeredActions
        #expect(!offered.contains(.returnToTask))
        // …and everything else is still there. Withdrawing one action must not withdraw the
        // economy: a panel with nothing on it is the anti-pattern, not the fix.
        #expect(offered.contains(.thisIsRelevant))
        #expect(offered.contains(.pause))
        #expect(AccusationFixture.noReturnTarget.primaryAction == .thisIsRelevant)
    }

    /// Mixed drift names nobody, so a rule about "several unrelated apps" would be a rule about
    /// something the person never pointed at.
    @Test("mixed drift withdraws exactly the actions that would write a rule about a subject")
    func mixedWithdrawsScopedActions() {
        let presentation = AccusationFixture.mixed
        let offered = presentation.offeredActions

        #expect(!presentation.hasScope)
        for action in CorrectionAction.allCases where action.requiresScope {
            #expect(!offered.contains(action))
        }
        for action in AccusationPresentation.actionOrder where !action.requiresScope {
            if action == .returnToTask { continue }
            #expect(offered.contains(action))
        }
        #expect(offered.contains(.returnToTask))
    }

    @Test("the primary action is the way back to work whenever there is one")
    func primaryActionIsTheWayBack() {
        #expect(AccusationFixture.rungTwo().primaryAction == .returnToTask)
        #expect(AccusationFixture.mixed.primaryAction == .returnToTask)
    }

    // MARK: - The snooze spans are the policy's, not the view's

    @Test("the snooze spans offered are InterventionPolicy's own three")
    func snoozeSpansComeFromThePolicy() {
        #expect(AccusationFixture.rungTwo().snoozeDurations == InterventionPolicy.snoozeDurations)
        #expect(InterventionPolicy.snoozeDurations.count == 3)
    }

    @Test("a running snooze is drawn as a countdown in the fixed mm:ss form")
    func snoozeCountdownForm() {
        #expect(NudgeCopy.countdown(.seconds(305)) == "05:05")
        #expect(NudgeCopy.countdown(.seconds(900)) == "15:00")
        // Width is what P-133 is about: every four-digit countdown is the same number of
        // characters, so the field cannot move the items beside it.
        #expect(NudgeCopy.countdown(.seconds(59)).count == NudgeCopy.countdown(.seconds(3_599)).count)
        // A lifted snooze is zero, never a negative countdown.
        #expect(NudgeCopy.countdown(.seconds(-30)) == "00:00")
    }

    // MARK: - What VoiceOver hears (F-144)

    @Test(
        "the announcement is the panel's own words, and omits the body it does not draw",
        .enabled(if: LocalizationLane.catalogsAreCompiled)
    )
    func announcementMatchesTheDrawnCopy() {
        let announced = AccusationFixture.rungTwo().announcement()
        #expect(announced.contains("Write the Q3 proposal"))
        // **The name, and the ABSENCE of the key** (focus-ebv). This asserted
        // `announced.contains("com.apple.Safari")` — so what VoiceOver spoke was the storage
        // key, and the suite that exists to check the spoken words was pinning it there. What a
        // person hears is what the panel draws, and the panel draws a name.
        #expect(announced.contains(AccusationFixture.safari.displayName))
        #expect(!announced.contains(AccusationFixture.safari.identifier))

        // Mixed drift draws no body line, so it announces none: a spoken sentence naming a
        // subject the panel does not show would be the app inventing evidence out loud. Both
        // halves are checked, because "names nobody" must not mean "names nobody by name".
        let mixed = AccusationFixture.mixed.announcement()
        #expect(mixed.contains("Write the Q3 proposal"))
        #expect(!mixed.contains(AccusationFixture.safari.displayName))
        #expect(!mixed.contains(AccusationFixture.safari.identifier))
    }

    /// The accusation never says "you are distracted" — and the check that it does not is
    /// `check-forbidden.sh`'s R-96f, on the **query** deck. What is asserted here is the other
    /// half of the same contract: the accusation panel draws accusation lines and nothing else.
    @Test("the panel draws no line from a query key")
    func drawsNoQueryLine() {
        for action in AccusationPresentation.actionOrder {
            #expect(action.copyKey?.isQueryLine == false)
        }
        #expect(NudgeCopyKey.accusationPanelTitle.isQueryLine == false)
        #expect(NudgeCopyKey.accusationPanelBody.isQueryLine == false)
    }

    // MARK: - The clicks

    @Test("every button reports its own action, and the snooze reports its span")
    func clicksReportThemselves() {
        var seen: [(CorrectionAction, Duration?)] = []
        let view = AccusationPanelView(presentation: AccusationFixture.rungTwo()) { action, span in
            seen.append((action, span))
        }
        // The callback is the view's whole contract with the host: it decides nothing and
        // writes nothing, which is what keeps `CorrectionAction.outcome(scope:at:)` the single
        // place a click becomes a write (R-86).
        view.onAction(.thisIsRelevant, nil)
        view.onAction(.snooze, .seconds(600))
        view.onAction(.dismiss, nil)

        #expect(seen.count == 3)
        #expect(seen[0].0 == .thisIsRelevant)
        #expect(seen[0].1 == nil)
        #expect(seen[1].0 == .snooze)
        #expect(seen[1].1 == .seconds(600))
        #expect(seen[2].0 == .dismiss)
    }
}

/// The rendered panel, against its committed baselines.
///
/// Gated on the localisation lane for the reason every other snapshot suite is: SwiftPM copies
/// String Catalogs rather than compiling them, so under `swift test` every line would render as
/// its own key and the baselines would be pictures of key names.
@Suite(
    "Accusation panel snapshots",
    .enabled(if: LocalizationLane.catalogsAreCompiled)
)
@MainActor
struct AccusationPanelSnapshotTests {
    static let panelWidth: CGFloat = 380

    /// **All five decks.** A deck with a missing or wrong line is an untranslated nudge shipped
    /// to somebody at their most sensitive moment, and `silentVisual` carries the full line set
    /// as well as its routing behaviour precisely so it can be checked like the rest.
    @Test(
        "every deck draws the rung-2 panel the same shape",
        arguments: NudgeVoice.allCases, ["light", "dark"]
    )
    func everyDeck(voice: NudgeVoice, variant: String) throws {
        try SnapshotHarness.assertSnapshot(
            AccusationPanelView(presentation: AccusationFixture.rungTwo(voice: voice)),
            component: "accusationPanel.\(voice.rawValue)",
            variant: variant,
            width: Self.panelWidth
        )
    }

    /// Increased contrast and reduced transparency, at both text sizes. A panel that truncated
    /// an action at the accessibility size would be a panel that stopped offering it.
    @Test(
        "the panel survives the appearance variants at both text sizes",
        arguments: ["increasedContrast", "reduceTransparency"], SnapshotTypeSize.allCases
    )
    func appearanceVariants(variant: String, size: SnapshotTypeSize) throws {
        try SnapshotHarness.assertSnapshot(
            AccusationPanelView(presentation: AccusationFixture.rungTwo()),
            component: "accusationPanel",
            variant: variant,
            textScale: size.textScale,
            width: Self.panelWidth
        )
    }

    @Test("the default deck survives the largest text size in light and dark",
          arguments: ["light", "dark"])
    func largeText(variant: String) throws {
        try SnapshotHarness.assertSnapshot(
            AccusationPanelView(presentation: AccusationFixture.rungTwo()),
            component: "accusationPanel",
            variant: variant,
            textScale: .accessibilityLarge,
            width: Self.panelWidth
        )
    }

    @Test("the three states that change what the panel offers", arguments: ["light", "dark"])
    func statefulVariants(variant: String) throws {
        let cases: [(String, AccusationPresentation)] = [
            ("mixed", AccusationFixture.mixed),
            ("noReturnTarget", AccusationFixture.noReturnTarget),
            ("snoozed", AccusationFixture.snoozed)
        ]
        for (name, presentation) in cases {
            try SnapshotHarness.assertSnapshot(
                AccusationPanelView(presentation: presentation),
                component: "accusationPanel.\(name)",
                variant: variant,
                width: Self.panelWidth
            )
        }
    }

}
