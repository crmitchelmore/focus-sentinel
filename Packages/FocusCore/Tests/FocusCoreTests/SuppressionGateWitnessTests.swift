import Foundation
import Testing

@testable import FocusCore

/// **Every gate that can silence this app, driven against a rung that speaks and a rung that does
/// not** (focus-0y6, focus-uru).
///
/// ## Why a closed set went three rounds without being swept
///
/// `NudgeSuppressionReason` has been `CaseIterable` since it was written, and nothing folded over
/// it. So the ruling *"a gate about interrupting somebody does not apply to a rung that
/// interrupts nobody"* was made three times — gate 7 when the stack was written, gate 5 of the
/// fatigue controller in focus-2yy, and three more here — and each time it was made by reading
/// the gates in prose and fixing the ones the reader noticed. focus-2yy's commit message
/// enumerates *"gates 1, 2 and 3 … gate 5"*; focus-0y6's triage walked twelve gates and ruled on
/// each. **Both skipped gate 4.**
///
/// The sibling that has no open defects is `InterruptionLimit`, and the difference is not the
/// type: it is that `InterruptionCapWitnessTests` folds over its `allCases` with one row per
/// case. This is that suite's shape for this vocabulary.
///
/// ## What each row drives, and both halves of it
///
/// One row per gate. Each row closes **that gate alone** in an otherwise-permitting world and
/// asks the shipping `SuppressionStack.evaluate(…)` three times:
///
/// * as a **question**, which is always a sentence — every gate applies, so the answer is always
///   this gate's own suppression. This is the row's non-vacuity: a knob that closed nothing would
///   answer `.permitted` here and the row would go red saying which gate it failed to close.
/// * as the **panel rung**, which speaks — suppressed, unless `appliesTo` says the gate is a
///   question's alone.
/// * as the **ambient rung**, which says nothing to anybody — and this is the column the three
///   repairs kept getting wrong. Its expected value is a **literal in the table**, never
///   `reason.subject.ruling(for:)` read back: a row that asked the implementation what it does
///   would agree with any implementation, which is the *"proof written to the known failure"*
///   shape the charter's repair doctrine counts at 31% of this backlog.
///
/// ## The vacuity guard
///
/// This suite would still be green if:
///
/// * **every gate were classified `.anythingToBeLegibleAbout`** — i.e. if the rule were switched
///   off entirely and the ambient rung refused by all twelve gates — provided every row's
///   `ambient` literal were edited to match. `theRuleIsNotAConstantFunction` below is the guard:
///   all three rulings must be reached by some row, so a classification that had collapsed into a
///   constant is red even with a consistently edited table.
/// * **the ambient rung never reached a surface at all.** This suite drives the stack, which is a
///   pure function; it proves the *decision*, not that a person sees a mark. `NudgeFloorTests`
///   owns that half, through the shipping composition root and the real status item, and
///   `theGlyphSurvivesACallAQuietHourAndAnOpenQuestion` there is this suite's live twin.
/// * **a thirteenth gate were added and left out of `SuppressionStack.evaluate`'s own list** — a
///   gate declared and never asked suppresses nothing, so no row could see it.
///   `theStackAsksEveryGateItDeclares` is the guard for that one, and it is what makes the
///   completeness check below more than a count.
@Suite("Every suppression gate, against a rung that speaks and one that does not")
struct SuppressionGateWitnessTests {
    struct Row: Sendable {
        /// The gate, as R-84 names it.
        let reason: NudgeSuppressionReason
        /// Closes **this gate alone**, in a world where every other gate is open.
        let close: @Sendable (inout SuppressionStackTests.Knobs) -> Void
        /// **What this gate does to the ambient rung** — a literal, deliberately. A row that read
        /// the classification back could never go red.
        let ambient: SilenceRuling
        /// Why that is the right answer for this gate. Read by a person; the assertions check the
        /// rest.
        let argument: String
    }

    /// **One row per `NudgeSuppressionReason`.** A case missing here fails
    /// `theTableCoversEveryGate`.
    static let rows: [Row] = [
        Row(
            reason: .noActivePriority,
            close: { $0.hasActivePriority = false },
            ambient: .silences,
            argument: """
                There is nothing to be off task from, so there is nothing true for the glyph to \
                say. A mark under no commitment would be the app inventing a subject.
                """
        ),
        Row(
            reason: .sensingPaused,
            close: { $0.sensingPaused = true },
            ambient: .silences,
            argument: """
                F-119 detaches every observer. The app does not know what is on screen, and a \
                mark it could not have earned is a guess drawn as a fact.
                """
        ),
        Row(
            reason: .sensitiveApplication,
            close: { $0.sensitivity = SuppressionStackTests.blocked },
            ambient: .silences,
            argument: """
                F-118: the app must say nothing at all about what is on screen. "We did not \
                look" must never become a mark, which is the same rule that makes noEvidence \
                unaskable.
                """
        ),
        Row(
            reason: .sessionPhaseForbids,
            close: { $0.phase = .onBreak },
            ambient: .silences,
            argument: """
                On a break there is no drift for the item to be legible about. F-99's \
                permitsIntervention is .focus alone and the glyph has nothing to mark.
                """
        ),
        Row(
            reason: .userIdle,
            close: { $0.idleSeconds = 600 },
            ambient: .silences,
            argument: """
                Nobody is at the keyboard, so nobody is looking at the menu bar either. The one \
                "legibility" gate whose argument is about the reader rather than the subject.
                """
        ),
        Row(
            reason: .mediaInUse,
            close: { $0.media = MediaActivity(microphoneRunning: true) },
            ambient: .passes,
            argument: """
                F-36's own sentence names a panel — "a panel over a call is a panel everybody \
                else can see". The glyph is not a window: it is the status item that was already \
                there, changing colour, naming nobody. And unlike gate 7 the menu bar is still on \
                screen, so this is an exemption rather than a deferral.
                """
        ),
        Row(
            reason: .presentationActive,
            close: { $0.presentation = SuppressionStackTests.presenting },
            ambient: .defers(.menuBarHidden),
            argument: """
                P-131 measured the menu-bar layer's owners collapsing during a full-screen space. \
                The rung was wanted and could not be delivered, so R-81 makes it a deferral: it \
                must not advance the ladder, spend a cap or start the escalation clock.
                """
        ),
        Row(
            reason: .quietHours,
            close: { $0.quietHours = SuppressionStackTests.allDayQuietHours },
            ambient: .passes,
            argument: """
                R-85. Somebody who sets quiet hours is asking the app not to SAY anything between \
                two times — the request a snooze makes, and R-87 already ruled on a snooze: the \
                glyph goes on telling the truth, because a person who asked for quiet did not ask \
                for a lie.
                """
        ),
        Row(
            reason: .interruptionInFlight,
            close: { $0.interruptionInFlight = true },
            ambient: .passes,
            argument: """
                An occupancy rule, and NudgeSurface.menuBar.holdsTheInterruptionSlot is false: \
                the glyph was refused by a rule it is explicitly excluded from. One open question \
                took the status item with it for as long as it stayed on the screen.
                """
        ),
        Row(
            reason: .budgetExhausted,
            close: { $0.budgetPermits = false },
            ambient: .silences,
            argument: """
                The one gate that deliberately does NOT classify: its detail vocabulary, \
                FatigueRefusal, classifies case by case, and one of those cases — corrected — is \
                a legibility refusal the glyph must obey. Passing the ambient rung here would \
                pass it over a correction the person just made. FatigueRefusalWitnessTests drives \
                the six.
                """
        ),
        Row(
            reason: .alreadyAsked,
            close: { $0.hasAsked = true },
            ambient: .passes,
            argument: """
                A question is a sentence, and this gate is a question's alone — appliesTo says \
                [.query]. The ambient column is unreachable in the shipping loop for that reason, \
                and it is `passes` rather than `silences` so that a future accusation-side \
                never-twice rule would inherit the right answer instead of the tidy one.
                """
        ),
        Row(
            reason: .verdictDoesNotAuthorise,
            close: { $0.verdictAuthorises = false },
            ambient: .silences,
            argument: """
                The verdict authorises no intervention of this kind, so there is nothing for the \
                item to be legible about. The last gate, and the one whose detail lives in \
                InterventionEligibility rather than in the enum.
                """
        )
    ]

    /// The outcome a ruling predicts for a given gate.
    static func outcome(_ ruling: SilenceRuling, _ reason: NudgeSuppressionReason)
        -> SuppressionOutcome {
        switch ruling {
        case .silences: .suppressed(reason)
        case .defers(let deferral): .deferred(deferral)
        case .passes: .permitted
        }
    }

    static func evaluate(
        _ row: Row,
        kind: InterruptionKind,
        rung: LadderRung.Kind?
    ) -> SuppressionOutcome {
        var knobs = SuppressionStackTests.Knobs()
        knobs.kind = kind
        knobs.rung = rung
        row.close(&knobs)
        return knobs.evaluate()
    }

    // MARK: - The witness

    /// **Both halves, one row per gate: the rung that should be refused is, and the rung that
    /// should not be, is not.**
    @Test("every gate refuses a rung that speaks and rules explicitly on one that does not")
    func everyGateIsDrivenAgainstBothRungs() {
        for row in Self.rows {
            // A question. Every gate applies to a sentence, so this is also the row's proof that
            // its knob closes the gate it claims to.
            #expect(
                Self.evaluate(row, kind: .query, rung: nil) == .suppressed(row.reason),
                """
                \(row.reason.rawValue): closing this gate did not suppress a QUESTION, which \
                every gate applies to — so this row drives nothing. \(row.argument)
                """
            )

            // The panel rung, which speaks. Suppressed, unless the gate is a question's alone.
            let panel = Self.evaluate(row, kind: .accusation, rung: .panel)
            let expectedPanel: SuppressionOutcome = row.reason.appliesTo.contains(.accusation)
                ? .suppressed(row.reason)
                : .permitted
            #expect(
                panel == expectedPanel,
                """
                \(row.reason.rawValue): the PANEL rung — which speaks, holds the slot and spends \
                the caps — answered \(String(describing: panel)) rather than \
                \(String(describing: expectedPanel)). \(row.argument)
                """
            )

            // The ambient rung, which says nothing to anybody. The column three repairs got
            // wrong, and the literal is the table's, not the implementation's.
            let ambient = Self.evaluate(row, kind: .accusation, rung: .ambient)
            let expectedAmbient = Self.outcome(row.ambient, row.reason)
            #expect(
                ambient == expectedAmbient,
                """
                \(row.reason.rawValue): the AMBIENT rung answered \
                \(String(describing: ambient)) rather than \
                \(String(describing: expectedAmbient)). The glyph is a state, not a sentence: it \
                costs nothing, holds no slot and survives what interruptions are spared. \
                \(row.argument)
                """
            )
        }
    }

    /// **The classification agrees with what the stack actually does**, per gate.
    ///
    /// The row's literal is the specification; this asserts `NudgeSuppressionReason.subject` — the
    /// property every other consumer reads — carries the same ruling, so the rule and the
    /// behaviour cannot part company in the direction the drive above cannot see.
    @Test("each gate's declared subject predicts what the stack does to each rung")
    func theDeclaredSubjectMatchesTheDrive() {
        for row in Self.rows {
            #expect(
                row.reason.subject.ruling(for: .ambient) == row.ambient,
                """
                \(row.reason.rawValue) is declared \
                \(String(describing: row.reason.subject)) and this table drives \
                \(String(describing: row.ambient))
                """
            )
            #expect(
                row.reason.subject.ruling(for: .panel) == .silences,
                "\(row.reason.rawValue) passes over the rung that speaks"
            )
            #expect(
                row.reason.subject.ruling(for: nil) == .silences,
                "\(row.reason.rawValue) passes over a question, which is always a sentence"
            )
        }
    }

    // MARK: - Totality

    /// **Every gate has a row**, folded over `allCases` rather than over a list written here. A
    /// thirteenth gate must add a case there — the stack reports one reason per silence and a
    /// silence with no name cannot be reported — and this fails until it has a witness.
    @Test("the table covers every gate exactly once")
    func theTableCoversEveryGate() {
        let covered = Set(Self.rows.map(\.reason))
        for reason in NudgeSuppressionReason.allCases {
            #expect(
                covered.contains(reason),
                """
                gate \(reason.gateNumber) (\(reason.rawValue)) can silence this app and has no \
                row saying what it does to a rung that says nothing
                """
            )
        }
        #expect(covered.count == Self.rows.count, "two rows drive the same gate")
        #expect(Self.rows.count == NudgeSuppressionReason.allCases.count)
    }

    /// **Every gate the enum declares is one the stack actually asks.**
    ///
    /// The completeness check above is a count of rows; this is what stops a gate being declared,
    /// given a row, and never wired into `evaluate(…)`. Each gate is closed and the stack must
    /// name it — for a question, where no classification can pass it over — so a case the
    /// evaluation forgot answers `.permitted` and this goes red by name.
    @Test("the stack asks every gate the enum declares, in declaration order")
    func theStackAsksEveryGateItDeclares() {
        for reason in NudgeSuppressionReason.allCases {
            let row = Self.rows.first { $0.reason == reason }
            guard let row else { continue }   // theTableCoversEveryGate owns this failure
            #expect(
                Self.evaluate(row, kind: .query, rung: nil).suppressionReason == reason,
                """
                gate \(reason.gateNumber) (\(reason.rawValue)) is declared and the stack never \
                asks it: closing it left the app permitted to speak
                """
            )
        }
    }

    // MARK: - The vacuity guard, made executable

    /// **The rule is not a constant function.**
    ///
    /// If every gate were classified the same way the table above would still be internally
    /// consistent and every assertion would pass — which is precisely the state the code was in
    /// before this round, when the answer was "silence everything" twelve times over. All three
    /// rulings must be reached by some gate, and the ambient column must genuinely disagree with
    /// the panel column somewhere, or the classification is decorative.
    @Test("all three rulings are reached, and the two rungs really do get different answers")
    func theRuleIsNotAConstantFunction() {
        let ambientRulings = Self.rows.map(\.ambient)
        #expect(
            ambientRulings.contains(.silences),
            "no gate stops the glyph, so the app would mark a person it knows nothing about"
        )
        #expect(
            ambientRulings.contains(.passes),
            "no gate passes the glyph over: the rule is switched off"
        )
        #expect(
            ambientRulings.contains(.defers(.menuBarHidden)),
            "no gate defers the glyph, so R-81's undeliverable-is-not-delivered has no instance"
        )

        let disagreeing = Self.rows.filter { $0.ambient != .silences }
        #expect(
            disagreeing.count == 5,
            """
            \(disagreeing.count) of \(Self.rows.count) gates treat the glyph differently from the \
            panel — \(disagreeing.map { $0.reason.rawValue }.joined(separator: ", ")). Five is \
            the committed count: gates 6, 7, 8, 9 and 11. A change here is a change to the ruling \
            and has to be re-recorded, not absorbed.
            """
        )
    }

    /// **A fatigue refusal can never be a deferral**, which is why gate 10 hands the stack a
    /// `Bool` and the stack keeps the third answer for itself.
    @Test("only a gate about a surface being on screen can defer")
    func onlyASurfaceGateDefers() {
        for reason in NudgeSuppressionReason.allCases {
            let defers: Bool
            if case .defers = reason.subject.ruling(for: .ambient) { defers = true } else {
                defers = false
            }
            let claimsTheSurface: Bool
            if case .theSurfaceBeingOnScreen = reason.subject { claimsTheSurface = true } else {
                claimsTheSurface = false
            }
            #expect(
                defers == claimsTheSurface,
                "\(reason.rawValue) defers a rung without claiming the surface is off screen"
            )
        }
        for kind in FatigueRefusal.Kind.allCases {
            if case .theSurfaceBeingOnScreen = kind.subject {
                Issue.record(
                    """
                    \(kind.rawValue) claims a surface is off screen, and FatigueDecision has no \
                    way to say deferred — so gate 10 would report it as a suppression
                    """
                )
            }
        }
    }
}
