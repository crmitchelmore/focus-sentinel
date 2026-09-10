import Foundation
import Testing

@testable import FocusCore

/// **What one delivery costs, folded over every rung the ladder has** (focus-uru).
///
/// ## The seam, and the four times it was crossed
///
/// *"Did this speak to anybody?"* has one derivation — `InterventionEvent.spendsTheInterruptionCap`,
/// reached through `InterruptionCharge`'s failable initialiser — and a delivery costs a person
/// three things: a row in the day's caps, a unit of the shared budget, and **the gap the app keeps
/// before it says the next thing**. Four rounds gave the first two to the derivation and left the
/// third beside it:
///
/// | round | what was charged for a rung nobody was spoken to by |
/// |---|---|
/// | focus-ndh | `dailyAccusationCap` |
/// | focus-d6r | `dailyInterruptionCap`, one line above it |
/// | focus-2yy | the cap gate refusing the rung that spends neither |
/// | **focus-uru** | **`RelevancePolicy.mandateCooldown`, one line below the charge** |
///
/// Both production lanes had the same two lines:
///
///     if let charge = InterruptionCharge(event, priorityID: …) { charges.append(charge) }
///     fatigue = FatigueController.reduce(fatigue, event: .delivered(.accusation), now: now)
///
/// The question is asked on the first line and not asked on the second. `FatigueEvent.delivered`
/// now takes the **charge**, so there is nothing to spell for a rung that spoke to nobody and the
/// pair cannot be half-applied.
///
/// ## What this suite folds
///
/// One row per `LadderRung.Kind`, plus the question, and each row asserts the three costs move
/// together: the charge exists, the cooldown is armed, and the next sentence is held back. A rung
/// whose charge is `nil` must move none of them.
///
/// ## The vacuity guard
///
/// This would still be green if:
///
/// * **every rung were uncharged** — the app would then cost a person nothing and say nothing
///   about the day. `bothAnswersAreReached` is the guard.
/// * **the two production lanes stopped calling this seam at all.** These are pure-function
///   drives. `NudgeFloorTests.aGlyphLandingDoesNotDelayTheRungThatSpeaks` is the host lane's own
///   proof, driven through the shipping composition root, and `SequenceReplayTests`' committed
///   transcripts are the replay lane's.
/// * **`InterruptionCharge(_ kind:)` were called directly with a rung's kind.** The failable
///   initialiser is the derivation; the total one exists for the question, which always speaks.
///   `theTotalInitialiserIsOnlyEverRightForAQuestion` below is the guard, and it is why the rows
///   below build an event and derive rather than construct.
@Suite("A delivery costs the same three things or none of them")
struct DeliveryCostSeamTests {
    static let subject = "com.chrismitchelmore.FocusDecoy"
    static let landed = Duration.seconds(10_000)

    struct Row: Sendable {
        let kind: InterruptionKind
        /// The rung it landed on, or `nil` for a question.
        let rung: LadderRung.Kind?
        /// The surface it actually reached, so the event is one the loop could really have written.
        let surface: NudgeSurface
        /// **Whether this delivery costs the person anything** — a literal, not
        /// `spendsTheInterruptionCap` read back.
        let costs: Bool
        let argument: String
    }

    /// **One row per rung, plus the question.** A rung missing here fails
    /// `theTableCoversEveryRung`.
    static let rows: [Row] = [
        Row(
            kind: .accusation,
            rung: .ambient,
            surface: .menuBar,
            costs: false,
            argument: """
                The glyph is a state, not a sentence. It accuses nobody, it holds no slot, R-87 \
                keeps it on through a snooze, and F-63's backoff retains it — so it cannot be one \
                of the eight interruptions a person is spared, and it cannot be the thing the app \
                waits ten minutes after.
                """
        ),
        Row(
            kind: .accusation,
            rung: .panel,
            surface: .panel,
            costs: true,
            argument: """
                The rung that carries a sentence, a subject and the whole correction economy. It \
                spends an accusation, a shared unit, and the gap before the next one.
                """
        ),
        Row(
            kind: .query,
            rung: nil,
            surface: .panel,
            costs: true,
            argument: """
                A person asked ten questions has been interrupted ten times. A question carries no \
                rung and always speaks, so there is no cell here that could go the other way.
                """
        )
    ]

    static func event(_ row: Row) -> InterventionEvent {
        InterventionEvent(
            kind: row.kind,
            rung: row.rung,
            subject: Self.subject,
            surface: row.surface,
            disposition: .delivered
        )
    }

    // MARK: - The witness

    /// **The charge, the cooldown and the next sentence move together or not at all.**
    @Test("a delivery that costs nothing arms no cooldown and delays no sentence")
    func theThreeCostsMoveTogether() {
        for row in Self.rows {
            let charge = InterruptionCharge(Self.event(row))
            #expect(
                (charge != nil) == row.costs,
                """
                \(row.rung?.rawValue ?? row.kind.rawValue): the charge derived from a delivered \
                row is \(charge == nil ? "nil" : "a charge") and this table says it \
                \(row.costs ? "costs" : "costs nothing"). \(row.argument)
                """
            )

            // The state after the delivery, folded exactly as both production lanes now fold it:
            // the charge is the event, so there is nothing to fold when there is no charge.
            var state = FatigueState.fresh
            if let charge {
                state = FatigueController.reduce(state, event: .delivered(charge), now: Self.landed)
            }
            #expect(
                (state.lastAccusationAt != nil) == (row.costs && row.kind == .accusation),
                """
                \(row.rung?.rawValue ?? row.kind.rawValue): the accusation cooldown was \
                \(state.lastAccusationAt == nil ? "not armed" : "armed") by a delivery this table \
                says \(row.costs ? "costs" : "costs nothing"). \(row.argument)
                """
            )
            #expect(
                (state.lastQueryAt != nil) == (row.costs && row.kind == .query),
                "\(row.kind.rawValue): the query cooldown moved for the wrong kind"
            )

            // **And the consequence a person meets**: whether the next sentence is held back.
            // Read one second after the landing, which is inside every cooldown this app has.
            let next = FatigueController.decide(
                kind: row.kind,
                subject: Self.subject,
                rung: row.kind == .accusation ? .panel : nil,
                budget: .empty,
                fatigue: state,
                now: Self.landed + .seconds(1)
            )
            #expect(
                next.isPermitted == !row.costs,
                """
                \(row.rung?.rawValue ?? row.kind.rawValue): a delivery this table says \
                \(row.costs ? "costs" : "costs nothing") left the next sentence \
                \(next.isPermitted ? "free" : String(describing: next.refusal)). \(row.argument)
                """
            )
        }
    }

    /// **A rung that costs nothing does not delay the rung above it either.**
    ///
    /// The half of this that is not about the person's day: `escalationDwell` is 300 s and
    /// `mandateCooldown` is 600 s, so a glyph landing that armed the accusation cooldown held the
    /// ladder's own escalation back for twice as long as the ladder asked for — an app that had
    /// marked somebody and could not follow it up for ten minutes.
    @Test("a glyph landing leaves the ladder free to escalate on its own dwell")
    func theGlyphDoesNotOutrankTheLaddersOwnDwell() throws {
        let glyph = try #require(Self.rows.first { $0.rung == .ambient })
        #expect(InterruptionCharge(Self.event(glyph)) == nil)

        // Nothing was folded, because there was nothing to fold.
        let state = FatigueState.fresh
        let atTheDwell = Self.landed + RelevancePolicy.escalationDwell + .seconds(1)
        #expect(atTheDwell < Self.landed + RelevancePolicy.mandateCooldown, "the two spans are equal")
        #expect(
            FatigueController.decide(
                kind: .accusation,
                subject: Self.subject,
                rung: .panel,
                budget: .empty,
                fatigue: state,
                now: atTheDwell
            ) == .permitted,
            "the rung that speaks was held past the ladder's own dwell by a rung that spoke to nobody"
        )
    }

    // MARK: - Totality

    /// **Every rung has a row**, folded over `LadderRung.Kind.allCases`, plus the question. A
    /// third rung — focus-5ab's deferred recommitment rung — must state what it costs before it
    /// can be delivered.
    @Test("the table covers every rung and both kinds")
    func theTableCoversEveryRung() {
        let coveredRungs = Set(Self.rows.compactMap(\.rung))
        for rung in LadderRung.Kind.allCases {
            #expect(
                coveredRungs.contains(rung),
                "the \(rung.rawValue) rung can be delivered and has no row saying what it costs"
            )
        }
        let coveredKinds = Set(Self.rows.map(\.kind))
        for kind in InterruptionKind.allCases {
            #expect(coveredKinds.contains(kind), "\(kind.rawValue) has no row")
        }
        #expect(Self.rows.count == LadderRung.Kind.allCases.count + 1, "a row drives nothing new")
    }

    /// **`InterruptionCharge(_ kind:)` is total and the derivation is not**, which is the whole
    /// design: a charge can always be *stated* — the question path states one, because a question
    /// always speaks — and it can only be *derived* from a delivery that spoke to somebody.
    ///
    /// Asserted here so the rows above are read as experiments rather than restatements: each one
    /// builds an event and derives, which is the shape both production lanes use.
    @Test("the total initialiser and the derivation disagree exactly where the glyph is")
    func theTotalInitialiserIsOnlyEverRightForAQuestion() {
        for row in Self.rows {
            let stated = InterruptionCharge(row.kind)
            let derived = InterruptionCharge(Self.event(row))
            #expect(
                (stated == derived) == row.costs,
                """
                \(row.rung?.rawValue ?? row.kind.rawValue): stating the charge and deriving it \
                \(stated == derived ? "agree" : "disagree"), and this table says the delivery \
                \(row.costs ? "costs" : "costs nothing"). Stating one for the glyph is how the \
                seam is crossed by hand.
                """
            )
        }
    }

    // MARK: - The vacuity guard, made executable

    /// **Both answers are reached.** If every delivery cost nothing the assertions above would all
    /// hold and the app would keep no caps at all; if every delivery cost something they would
    /// hold too and the glyph would be back to spending a person's day.
    @Test("some deliveries cost the person something and some cost nothing")
    func bothAnswersAreReached() {
        #expect(Self.rows.contains { $0.costs }, "nothing this app does costs anybody anything")
        #expect(
            Self.rows.contains { !$0.costs },
            "every delivery costs something, so the glyph is spending a person's day again"
        )
        #expect(
            Self.rows.filter { !$0.costs }.map(\.rung) == [.ambient],
            "exactly one rung costs nothing, and it is the one that says nothing"
        )
    }
}
