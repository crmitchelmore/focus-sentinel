import Foundation
import Testing

@testable import FocusCore

/// **Every reason the fatigue controller has for going quiet, driven against a rung that speaks
/// and a rung that does not** (focus-uru).
///
/// ## The vocabulary that had no way to be folded
///
/// Three vocabularies answer *"why did the app go quiet?"*. `InterruptionLimit` is `CaseIterable`
/// and `InterruptionCapWitnessTests` folds one row per case over it; it has no open defects.
/// `NudgeSuppressionReason` is `CaseIterable` and nothing folded over it; it had three.
/// `FatigueRefusal` carries payloads, so it was not `CaseIterable` at all, nothing could fold over
/// it, and gate 4 — the one this suite exists for — sat between two gates that had each been
/// given the ambient exemption and never got one:
///
///     rung=ambient, gap=60s → refused(cooldown(remaining: 540s))
///
/// The one channel that is supposed to survive everything, muted for `mandateCooldown` at a time
/// by a cooldown belonging to the rung that speaks. Two rounds swept this closed set by reading
/// the gates in prose and **both missed the same one**. `FatigueRefusal.Kind` is the shape that
/// makes reading unnecessary.
///
/// ## What each row drives, and both halves of it
///
/// One row per `FatigueRefusal.Kind`. Each row states a world — a day's spend, a session's
/// fatigue, a snooze book, a set of corrected subjects — and drives the shipping
/// `FatigueController.decide(…)` three times:
///
/// 1. **the baseline**, on a fresh world: it must be `.permitted`, or the row's world is not what
///    refuses and the row proves nothing;
/// 2. **the rung that speaks** — the panel for an accusation, `nil` for a question: it must be
///    refused with **this exact refusal, payload included**, so a row cannot pass by producing
///    some other silence;
/// 3. **the ambient rung**, whose expected answer is a **literal in the table** rather than
///    `kind.subject.ruling(…)` read back. A row that asked the implementation what it does would
///    agree with any implementation — the *"proof written to the known failure"* shape the
///    charter counts at 31% of this backlog.
///
/// ## The vacuity guard
///
/// This suite would still be green if:
///
/// * **every refusal were classified `.anythingToBeLegibleAbout`** — the state the code was in
///   for gate 4 — provided every row's `ambient` literal were edited to match.
///   `theRuleIsNotAConstantFunction` is the guard: both answers must be reached, and the row that
///   reaches `refused` must be `corrected`, which is the one refusal the glyph has to obey.
/// * **the fatigue controller never reached a surface.** These are pure-function drives. The
///   consequences a person meets are `NudgeFloorTests.theGlyphSurvivesADaySpentToTheCap` (the
///   caps), `theGlyphSurvivesACallAQuietHourAndAnOpenQuestion` (the stack's three) and
///   `theGlyphSurvivesItsOwnCooldown` (this round's gate 4), each through the shipping
///   composition root and the real status item.
/// * **a seventh refusal were added and never produced by `candidates(…)`.** A refusal declared
///   and never constructed refuses nobody. `everyRefusalIsOneTheControllerCanProduce` is the
///   guard, and it is what makes the completeness check below more than a count of rows.
@Suite("Every fatigue refusal, against a rung that speaks and one that does not")
struct FatigueRefusalWitnessTests {
    static let decoy = "com.chrismitchelmore.FocusDecoy"
    /// The moment every row is decided at.
    static let now = Duration.seconds(10_000)

    /// A day and a session, as the controller reads them.
    struct World: Sendable {
        var kind: InterruptionKind = .accusation
        var subject: String? = FatigueRefusalWitnessTests.decoy
        var budget: InterruptionBudget = .empty
        var fatigue: FatigueState = .fresh
        var snoozes: SnoozeBook = .none
        var corrected: Set<String> = []

        func decide(rung: LadderRung.Kind?) -> FatigueDecision {
            FatigueController.decide(
                kind: kind,
                subject: subject,
                rung: rung,
                budget: budget,
                fatigue: fatigue,
                snoozes: snoozes,
                correctedSubjects: corrected,
                now: FatigueRefusalWitnessTests.now
            )
        }

        /// The same world with every reason for silence taken out of it — the row's baseline.
        var fresh: World { World(kind: kind, subject: subject) }

        /// The rung this world's kind is actually offered on. A question has none.
        var speakingRung: LadderRung.Kind? { kind == .query ? nil : .panel }
    }

    struct Row: Sendable {
        let kind: FatigueRefusal.Kind
        /// The state that produces this refusal.
        let world: World
        /// **The exact refusal, payload included.** A row that expected only the case could pass
        /// on a remaining duration of nought, which is a countdown a surface would draw as over.
        let expected: FatigueRefusal
        /// **What this refusal does to the ambient rung** — a literal. `nil` where the refusal
        /// belongs to a question, which is never offered on a rung at all.
        let ambient: FatigueDecision?
        /// Why that is the right answer. Read by a person; the assertions check the rest.
        let argument: String
    }

    /// **One row per `FatigueRefusal.Kind`.** A case missing here fails
    /// `theTableCoversEveryRefusal`.
    static let rows: [Row] = [
        Row(
            kind: .corrected,
            world: World(corrected: [decoy]),
            expected: .corrected(subject: decoy),
            ambient: .refused(.corrected(subject: decoy)),
            argument: """
                The one refusal here whose subject is legibility, and the reason gate 10 of the \
                suppression stack does not classify. The person has just clicked "this is \
                relevant": there is no longer anything to be off task about, so a glyph that went \
                on marking them would be the app arguing with an instruction it was given.
                """
        ),
        Row(
            kind: .snoozed,
            world: World(
                snoozes: SnoozeBook.none.adding(
                    SnoozeState.starting(subject: decoy, for: .seconds(900), now: .seconds(9_940))
                )
            ),
            expected: .snoozed(subject: decoy, remaining: .seconds(840)),
            ambient: .permitted,
            argument: """
                R-87's own sentence: never applied to the ambient rung, because the glyph goes on \
                telling the truth. A person who snoozed a panel asked for quiet, not for a lie.
                """
        ),
        Row(
            kind: .backedOff,
            world: World(
                kind: .query,
                fatigue: FatigueState(queriesSuspendedUntil: .seconds(13_600))
            ),
            expected: .backedOff(until: .seconds(13_600)),
            ambient: nil,
            argument: """
                Questions only — two unanswered questions is the point at which the app is talking \
                to itself. A question carries no rung, so there is no ambient column to rule on: \
                the controller is asked with rung nil and a question always speaks.
                """
        ),
        Row(
            kind: .heldAtAmbient,
            world: World(fatigue: FatigueState(accusationsHeldUntil: .seconds(13_600))),
            expected: .heldAtAmbient(until: .seconds(13_600)),
            ambient: .permitted,
            argument: """
                The exemption is in the case's own name: the hold IS the ladder standing at the \
                rung this rules out refusing. F-63's backoff retains the ambient rung, which is \
                the one channel the person has not objected to.
                """
        ),
        Row(
            kind: .cooldown,
            // Sixty seconds after an accusation, against a 600-second `mandateCooldown`. The
            // bead's own measurement, reproduced as a row.
            world: World(fatigue: FatigueState(lastAccusationAt: .seconds(9_940))),
            expected: .cooldown(remaining: .seconds(540)),
            ambient: .permitted,
            argument: """
                THE GATE THIS ROUND IS ABOUT. A cooldown is a minimum gap between SENTENCES. The \
                glyph makes none, spends neither cap, and costs a person nothing to have been \
                shown twice — so a 600-second gap between accusations has nothing to say about it.
                """
        ),
        Row(
            kind: .cap,
            world: World(
                budget: BudgetDay.spending(accusations: InterventionPolicy.dailyAccusationCap)
            ),
            expected: .cap(.dailyAccusationCap),
            ambient: .permitted,
            argument: """
                focus-2yy's ruling, restated where the other five now live: a rung is refused only \
                by a cap it can spend. The glyph spends neither, by \
                InterventionEvent.spendsTheAccusationCap's own derivation.
                """
        )
    ]

    // MARK: - The witness

    @Test("every refusal stops the rung that speaks and rules explicitly on the one that does not")
    func everyRefusalIsDrivenAgainstBothRungs() {
        for row in Self.rows {
            let rung = row.world.speakingRung

            // 1 — the baseline. Without this a row whose world arranged nothing would still see a
            // refusal from somewhere and claim credit for it.
            #expect(
                row.world.fresh.decide(rung: rung) == .permitted,
                """
                \(row.kind.rawValue): a fresh day and a fresh session already refuse a \
                \(row.world.kind.rawValue), so this row's world is not what refuses. \
                \(row.argument)
                """
            )

            // 2 — the rung that speaks, and the exact refusal it must produce.
            let speaking = row.world.decide(rung: rung)
            #expect(
                speaking == .refused(row.expected),
                """
                \(row.kind.rawValue): the rung that speaks answered \
                \(String(describing: speaking)) rather than \
                \(String(describing: FatigueDecision.refused(row.expected))). \(row.argument)
                """
            )

            // 3 — the ambient rung, which says nothing to anybody.
            guard let expectedAmbient = row.ambient else { continue }
            let ambient = row.world.decide(rung: .ambient)
            #expect(
                ambient == expectedAmbient,
                """
                \(row.kind.rawValue): the AMBIENT rung answered \(String(describing: ambient)) \
                rather than \(String(describing: expectedAmbient)). The glyph is a state, not a \
                sentence: it costs nothing, holds no slot, and survives what interruptions are \
                spared. \(row.argument)
                """
            )
        }
    }

    /// **The declared subject predicts the drive**, per refusal.
    ///
    /// The row's literal is the specification; this asserts `FatigueRefusal.Kind.subject` — what
    /// `decide(…)` and every other consumer read — carries the same ruling.
    @Test("each refusal's declared subject predicts what the controller does to each rung")
    func theDeclaredSubjectMatchesTheDrive() {
        for row in Self.rows {
            guard let expectedAmbient = row.ambient else {
                #expect(
                    row.kind.subject == .theAppSpeaking,
                    "\(row.kind.rawValue) is a question's refusal and a question is a sentence"
                )
                continue
            }
            #expect(
                row.kind.subject.silences(.ambient) == (expectedAmbient != .permitted),
                """
                \(row.kind.rawValue) is declared \(String(describing: row.kind.subject)) and this \
                table drives \(String(describing: expectedAmbient))
                """
            )
            #expect(
                row.kind.subject.silences(.panel),
                "\(row.kind.rawValue) passes over the rung that speaks"
            )
        }
    }

    // MARK: - Totality

    /// **Every refusal has a row**, folded over `FatigueRefusal.Kind.allCases`. A seventh refusal
    /// must add a case there — a person cannot be told why the app went quiet otherwise — and this
    /// fails until it has a witness.
    @Test("the table covers every refusal exactly once")
    func theTableCoversEveryRefusal() {
        let covered = Set(Self.rows.map(\.kind))
        for kind in FatigueRefusal.Kind.allCases {
            #expect(
                covered.contains(kind),
                "\(kind.rawValue) can silence this app and has no row saying what it does to a rung"
            )
        }
        #expect(covered.count == Self.rows.count, "two rows drive the same refusal")
        #expect(Self.rows.count == FatigueRefusal.Kind.allCases.count)
    }

    /// **Every refusal the enum declares is one `candidates(…)` can actually construct.**
    ///
    /// The completeness check above counts rows; this is what stops a refusal being declared,
    /// given a row, and never produced. Each row's world is asked for its candidate list and this
    /// refusal must be in it — read before the rung is considered, so a case that only the
    /// classification could reach is still caught.
    @Test("the controller can produce every refusal the vocabulary declares")
    func everyRefusalIsOneTheControllerCanProduce() {
        var produced: Set<FatigueRefusal.Kind> = []
        for row in Self.rows {
            let candidates = FatigueController.candidates(
                kind: row.world.kind,
                subject: row.world.subject,
                budget: row.world.budget,
                fatigue: row.world.fatigue,
                snoozes: row.world.snoozes,
                correctedSubjects: row.world.corrected,
                now: Self.now
            )
            produced.formUnion(candidates.map(\.kind))
            #expect(
                candidates.contains(row.expected),
                """
                \(row.kind.rawValue) is declared and this world does not produce it — \
                \(candidates.map { $0.kind.rawValue }.joined(separator: ", "))
                """
            )
        }
        for kind in FatigueRefusal.Kind.allCases {
            #expect(
                produced.contains(kind),
                "\(kind.rawValue) is declared and no world in this table can construct it"
            )
        }
    }

    /// **The order the refusals are checked in is the order a person would give them.**
    ///
    /// Corrected → snoozed → backoff → cooldown → cap. The two the person authored come first,
    /// because the honest answer to "why was it quiet?" is "because you told it to be", and an
    /// arithmetic reason offered ahead of an instruction would be the app taking credit for
    /// restraint the person imposed on it. Driven by stacking every accusation-side world into
    /// one and peeling them off, so the order is a fact about `candidates(…)` rather than a
    /// comment above it.
    @Test("the first refusal reported is the first one that applied")
    func theOrderIsTheOrderAPersonWouldGive() {
        let accusationRows = Self.rows.filter { $0.world.kind == .accusation }
        var everything = World(
            budget: BudgetDay.spending(accusations: InterventionPolicy.dailyAccusationCap),
            fatigue: FatigueState(
                lastAccusationAt: .seconds(9_940),
                accusationsHeldUntil: .seconds(13_600)
            ),
            snoozes: SnoozeBook.none.adding(
                SnoozeState.starting(subject: Self.decoy, for: .seconds(900), now: .seconds(9_940))
            ),
            corrected: [Self.decoy]
        )

        for row in accusationRows {
            #expect(
                everything.decide(rung: .panel) == .refused(row.expected),
                """
                with every reason for silence in force at once the app reported \
                \(String(describing: everything.decide(rung: .panel))) rather than \
                \(row.kind.rawValue), which is the earlier one
                """
            )
            // Peel this one off and the next must surface.
            switch row.kind {
            case .corrected: everything.corrected = []
            case .snoozed: everything.snoozes = .none
            case .heldAtAmbient:
                everything.fatigue = FatigueState(lastAccusationAt: everything.fatigue.lastAccusationAt)
            case .cooldown: everything.fatigue = .fresh
            case .cap: everything.budget = .empty
            case .backedOff: continue
            }
        }
        #expect(everything.decide(rung: .panel) == .permitted, "something silences an empty world")
    }

    // MARK: - The vacuity guard, made executable

    /// **The rule is not a constant function.**
    ///
    /// If every refusal were classified the same way the table above would still be internally
    /// consistent and every assertion would pass — which is the state gate 4 was in. Both answers
    /// must be reached, and the one that stops the glyph must be `corrected`: a classification in
    /// which the glyph survives a correction is not a stricter rule, it is a wrong one.
    @Test("both answers are reached, and the only refusal that stops the glyph is a correction")
    func theRuleIsNotAConstantFunction() {
        let stopping = Self.rows.filter { $0.ambient != nil && $0.ambient != .permitted }
        let passing = Self.rows.filter { $0.ambient == .permitted }

        #expect(
            stopping.map(\.kind) == [.corrected],
            """
            \(stopping.map { $0.kind.rawValue }.joined(separator: ", ")) stop the glyph. Exactly \
            one refusal may: a correction, which means there is nothing left to be legible about. \
            A change here is a change to the ruling and has to be re-recorded, not absorbed.
            """
        )
        #expect(
            passing.count == 4,
            """
            \(passing.count) refusals pass the glyph over — \
            \(passing.map { $0.kind.rawValue }.joined(separator: ", ")). Four is the committed \
            count: snoozed, heldAtAmbient, cooldown and cap.
            """
        )
    }
}
