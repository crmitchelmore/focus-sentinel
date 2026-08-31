import Foundation
import SwiftData
import Testing

@testable import FocusCore

/// **Every cap that can silence this app, with a driven mutation witness** (focus-d6r, R-74.1).
///
/// ## Why the caps had none
///
/// R-74.1's rule is that *a constant is not committed until a fixture would fail if it moved*, and
/// `MutationWitnessTests` keeps it for `RelevancePolicy`. `InterventionPolicy`'s caps had the
/// other half of the mechanism and not this one: `InterventionPolicyTests` asserts a committed
/// digest, which fails when a number moves and says nothing about whether the number does
/// anything, and the manifest names corpus witnesses for two of the five. So four of the day's
/// five limits could be raised or lowered with nothing but the digest going red — a red that
/// tells a maintainer only that they edited the file they were editing.
///
/// The proofs that did exist each drove exactly the constant their own bead named.
/// `sixPerceptibleGlyphLandingsSpendNoAccusation` drove `dailyAccusationCap` and no proof
/// anywhere drove `dailyInterruptionCap` — which is precisely the cap that was broken, and the
/// reason it stayed broken through the round written to end this defect class.
///
/// ## How a mutation is performed, and why it is performed on the input
///
/// `MutationWitnessTests` states the argument and it holds here: the policy is an enum of
/// `static let`s, deliberately immutable and digested, so the mutation is performed on the
/// **input**. Each cap enters the budget through exactly one comparison of the form
/// `count ⋈ constant`, so moving the constant by δ and holding the count still is
/// indistinguishable, at that comparison, from moving the count by −δ and holding the constant
/// still.
///
/// What makes that an experiment rather than a restatement is `committed`: the count each row
/// drives is a **literal**, not the constant. A row asserts the literal against the manifest, and
/// then drives a real day of rows through the shipping `InterventionLog` to `committed - 1` and to
/// `committed`, requiring the limit to be open at the first and to be the named binding one at the
/// second. Move the constant in either direction and the flip stops happening where the literal
/// says it does, and this suite goes red **by name**, saying which cap the app has stopped
/// enforcing where it says it does.
///
/// ## Why the table is total
///
/// It is keyed by `InterruptionLimit`, which is `CaseIterable` and is the closed set of answers to
/// *"which cap is the one that bit?"*. A sixth cap that can make this app go quiet has to add a
/// case there or a person cannot be told why it went quiet — which is that type's whole stated
/// job — and the completeness assertion below then fails until it has a row here.
@Suite("Every cap has a mutation witness")
struct InterruptionCapWitnessTests {
    /// Which day this row builds, and what it asks of it.
    struct Row {
        /// The cap, as the surface names it to a person.
        let limit: InterruptionLimit
        /// The `InterventionPolicy` constant it is, exactly. Must be in the manifest.
        let constant: String
        /// **The committed count at which this cap bites.** A literal, deliberately: a row that
        /// read the constant would move with it and could never go red.
        let committed: Int
        /// The kind whose permission this row reads.
        let kind: InterruptionKind
        /// How many of the day's `n` sentences are questions asked under *another* commitment.
        /// The rest are split by `accusationShare`.
        let shape: Shape
        /// Why this shape isolates this cap from the other four. Read by a person; the
        /// assertions check the rest.
        let argument: String

        enum Shape {
            /// `n` questions, all under the commitment the budget is summed for.
            case queriesHere
            /// `n` questions, all under other commitments.
            case queriesElsewhere
            /// `n` accusations.
            case accusations
            /// `n` sentences, alternating accusation and question-here, **accusations first**.
            ///
            /// The order is load-bearing at the reserve's boundary: questions first would put
            /// four of them under one commitment by the seventh sentence, and `dailyQueryCap`
            /// would then be what refuses the eighth — so the row would drive the per-priority
            /// cap while claiming to drive the reserve.
            case mixed
        }
    }

    /// **One row per `InterruptionLimit`.** A case missing from this table fails
    /// `theTableCoversEveryCapThatCanBite` below, which is what makes it total rather than a
    /// selection.
    static let rows: [Row] = [
        Row(
            limit: .dailyQueryCap,
            constant: "dailyQueryCap",
            committed: 4,
            kind: .query,
            shape: .queriesHere,
            argument: """
                Four questions under one commitment. Below the all-priorities cap of five and \
                below the reserve at seven, so the per-priority cap is the only one that can \
                bite — which is the whole point of it being a separate constant.
                """
        ),
        Row(
            limit: .dailyQueryCapAllPriorities,
            constant: "dailyQueryCapAllPriorities",
            committed: 5,
            kind: .query,
            shape: .queriesElsewhere,
            argument: """
                Five questions under OTHER commitments, so the per-priority cap counts none of \
                them and cannot be what bites. This is the cap adversarial review added: a cap \
                that is per priority is not a cap on a person's day, and three priorities would \
                otherwise license twelve questions.
                """
        ),
        Row(
            limit: .dailyAccusationCap,
            constant: "dailyAccusationCap",
            committed: 6,
            kind: .accusation,
            shape: .accusations,
            argument: """
                Six accusations, which leaves two of the eight shared units — so the shared cap \
                still has room and the accusation cap is unambiguously the one that bit.
                """
        ),
        Row(
            limit: .dailyInterruptionCap,
            constant: "dailyInterruptionCap",
            committed: 8,
            kind: .accusation,
            shape: .mixed,
            argument: """
                Four accusations and four questions. The accusation cap is not reached — four \
                is under six — so only the shared budget can refuse the ninth. Read on the \
                ACCUSATION, because a question at seven spent is refused by the reserve rather \
                than by this cap, which is the row below.
                """
        ),
        Row(
            limit: .reservedForAccusation,
            constant: "reservedAccusationUnits",
            // Not the constant's own value: the count at which the reserve becomes the thing
            // that refuses a question, which is `dailyInterruptionCap - reservedAccusationUnits`.
            // A witness for a subtraction has to be driven where the subtraction is felt.
            committed: 7,
            kind: .query,
            shape: .mixed,
            argument: """
                Seven of the eight spent, on four accusations and three questions. A unit \
                remains and the question may not have it, because that unit is the accusation's \
                — the one rule in the budget that is not arithmetic. Raising the reserve to two \
                refuses the question at six and the row's lower boundary fails; lowering it to \
                nought permits the question at seven and its upper boundary fails.
                """
        )
    ]

    static let decoy = "com.chrismitchelmore.FocusDecoy"

    @MainActor
    static func makeLog() throws -> (InterventionLog, ModelContainer) {
        let container = try FocusStore.makeContainer(kind: .inMemory)
        let log = InterventionLog(
            context: container.mainContext,
            dateProvider: FixedDate(),
            calendar: Calendar(identifier: .gregorian)
        )
        return (log, container)
    }

    /// A wall clock that does not move, so a day driven here is one day.
    struct FixedDate: DateProvider {
        let now = Date(timeIntervalSince1970: 1_767_225_600)
    }

    /// **A day of `count` delivered sentences of this row's shape, written to a real store.**
    ///
    /// Rows rather than a hand-built value: the caps are summed from persisted
    /// `InterventionRecord`s, and a witness that skipped the store would not notice a cap that
    /// stopped being read off the rows it is supposed to be read off.
    @MainActor
    static func day(
        _ shape: Row.Shape,
        count: Int,
        log: InterventionLog,
        priorityID: UUID
    ) throws {
        for index in 0..<count {
            let isQuery: Bool
            let underThisPriority: Bool
            switch shape {
            case .queriesHere: (isQuery, underThisPriority) = (true, true)
            case .queriesElsewhere: (isQuery, underThisPriority) = (true, false)
            case .accusations: (isQuery, underThisPriority) = (false, true)
            case .mixed: (isQuery, underThisPriority) = (!index.isMultiple(of: 2), true)
            }
            try log.record(
                InterventionEvent(
                    kind: isQuery ? .query : .accusation,
                    // The PANEL rung, never the ambient one: a glyph landing accuses nobody and
                    // spends neither cap (focus-ndh, focus-d6r), so a witness built on ambient
                    // rungs would drive no cap at all — which is exactly what the two committed
                    // corpus sequences for these caps were doing.
                    rung: isQuery ? nil : .panel,
                    subject: Self.decoy,
                    surface: .panel,
                    disposition: .delivered
                ),
                priorityID: underThisPriority ? priorityID : UUID()
            )
        }
    }

    @MainActor
    static func budget(
        _ row: Row,
        spending count: Int
    ) throws -> InterruptionBudget {
        let (log, container) = try Self.makeLog()
        defer { withExtendedLifetime(container) {} }
        let priorityID = UUID()
        try Self.day(row.shape, count: count, log: log, priorityID: priorityID)
        return try log.budget(on: log.today, priorityID: priorityID)
    }

    // MARK: - The witness

    /// **Each cap, driven to one below its committed count and to it.**
    @MainActor
    @Test("every cap is open one sentence below its committed count and is the binding one at it")
    func everyCapBitesExactlyWhereItIsCommittedTo() throws {
        for row in Self.rows {
            let below = try Self.budget(row, spending: row.committed - 1)
            #expect(
                below.permits(row.kind),
                """
                \(row.constant): a \(row.kind.rawValue) was refused after \
                \(row.committed - 1) sentence(s), one below the committed count — bound by \
                \(String(describing: below.bindingLimit(for: row.kind))). \(row.argument)
                """
            )

            let at = try Self.budget(row, spending: row.committed)
            #expect(
                !at.permits(row.kind),
                """
                \(row.constant): a \(row.kind.rawValue) was still permitted after \
                \(row.committed) sentence(s) — the cap does not bite where it is committed to. \
                \(row.argument)
                """
            )
            #expect(
                at.bindingLimit(for: row.kind) == row.limit,
                """
                \(row.constant): the app went quiet at \(row.committed) sentence(s) and told the \
                person it was \(String(describing: at.bindingLimit(for: row.kind))) rather than \
                \(row.limit.rawValue). \(row.argument)
                """
            )
        }
    }

    /// **The reserve's own half: the accusation may spend what the question may not.**
    ///
    /// Read on the same day the `reservedForAccusation` row drives, because "the question is
    /// refused" is only half of that constant's meaning. The other half is that the app can still
    /// say the thing the whole product exists to say, and it is the half focus-d6r is about.
    @MainActor
    @Test("the unit a question may not spend is a unit the accusation still can")
    func theReservedUnitIsTheAccusationsToSpend() throws {
        let row = try #require(Self.rows.first { $0.limit == .reservedForAccusation })
        let budget = try Self.budget(row, spending: row.committed)
        #expect(!budget.permits(.query))
        #expect(
            budget.permits(.accusation),
            "the unit reserved for the accusation could not be spent by an accusation"
        )
        #expect(budget.sharedRemaining == InterventionPolicy.reservedAccusationUnits)
    }

    // MARK: - Totality

    /// **Every cap that can bite has a row**, folded over `InterruptionLimit.allCases` rather than
    /// over a list written here. A sixth cap must add a case there — a person cannot be told why
    /// the app went quiet otherwise — and this fails until it has a witness.
    @Test("the table covers every cap that can bite, and each row names a manifest constant")
    func theTableCoversEveryCapThatCanBite() throws {
        let covered = Set(Self.rows.map(\.limit))
        for limit in InterruptionLimit.allCases {
            #expect(
                covered.contains(limit),
                "\(limit.rawValue) can silence this app and has no mutation witness"
            )
        }
        #expect(covered.count == Self.rows.count, "two rows drive the same cap")

        // And each row's committed literal is the constant's own value, so moving the constant
        // turns this red by name as well as turning the drive above red.
        let manifest = Dictionary(
            uniqueKeysWithValues: InterventionPolicy.manifest.map { ($0.name, $0.encoded) }
        )
        for row in Self.rows {
            let encoded = try #require(
                manifest[row.constant],
                "\(row.constant) is not in InterventionPolicy.manifest"
            )
            let value = try #require(Int(encoded), "\(row.constant) is not a count")
            let expected = row.limit == .reservedForAccusation
                ? InterventionPolicy.dailyInterruptionCap - value
                : value
            #expect(
                row.committed == expected,
                """
                \(row.constant) is \(encoded) and this table drives \(row.committed). The \
                witness and the constant have to be re-recorded together, or the drive below \
                proves the cap bites somewhere it does not.
                """
            )
        }
    }
}
