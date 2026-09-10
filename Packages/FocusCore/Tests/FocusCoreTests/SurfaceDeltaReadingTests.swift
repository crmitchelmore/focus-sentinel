import Foundation
import Testing

@testable import FocusCore

/// **The four rows of R-89's delta table, folded rather than walked** (focus-2uy.3).
///
/// The defect was that the table had four rows and the code had three: "the front was never read"
/// fell into "the front did not move", so a run that measured nothing published its delta as
/// measured, and three assertions then failed on a pair of nulls — the gate naming the panel for
/// whoever happened to be using the Mac.
///
/// A defect of that shape is not fixed by a test that drives the reported scenario. It is fixed by
/// a fold: every cell of `{read, unread} × {read, unread} × {same front, moved to us, moved
/// elsewhere}` is evaluated here, and the verdict for each is derived from the cell rather than
/// listed, so a fifth row added to the situation has nowhere to hide.
@Suite("A delta between two readings that were never taken is not a delta")
struct SurfaceDeltaReadingTests {
    static let us = "com.example.FocusSentinel"
    static let somebodyElse = "com.example.Browser"

    /// Which way the front went, as a closed set. The third value of the cross product.
    enum Movement: String, CaseIterable {
        case stayedPut
        case movedToUs
        case movedElsewhere

        /// The pair of identifiers this movement produces, when both ends were read.
        var fronts: (before: String, after: String) {
            switch self {
            case .stayedPut: (SurfaceDeltaReadingTests.somebodyElse, SurfaceDeltaReadingTests.somebodyElse)
            case .movedToUs: (SurfaceDeltaReadingTests.somebodyElse, SurfaceDeltaReadingTests.us)
            case .movedElsewhere: (SurfaceDeltaReadingTests.us, SurfaceDeltaReadingTests.somebodyElse)
            }
        }
    }

    /// One cell of the cross product, and the outcome the table says it has.
    struct Cell {
        let readBefore: Bool
        let readAfter: Bool
        let movement: Movement

        var outcome: ProbeOutcome {
            SurfaceDeltaReading.evaluate(
                frontWasReadBefore: readBefore,
                frontWasReadAfter: readAfter,
                // An unread end carries no identifier, which is exactly how `FocusReadings`
                // serialises it: `null`, never `""`.
                frontBefore: readBefore ? movement.fronts.before : nil,
                frontAfter: readAfter ? movement.fronts.after : nil,
                ourIdentifier: us
            )
        }

        /// **Derived from the cell, never listed beside it.** An expectation written out per cell
        /// is a second copy of the rule, and two copies of a rule is the shape that produced the
        /// bead this file exists for.
        var expected: ProbeOutcome {
            guard readBefore, readAfter else { return .notTaken(.frontmostApplicationUnavailable) }
            return movement == .movedElsewhere
                ? .notTaken(.frontMovedToAnotherApplication)
                : .holds
        }
    }

    static let everyCell: [Cell] = [true, false].flatMap { readBefore in
        [true, false].flatMap { readAfter in
            Movement.allCases.map { Cell(readBefore: readBefore, readAfter: readAfter, movement: $0) }
        }
    }

    /// The fold. Twelve cells, every one of them evaluated.
    @Test("every cell of the cross product reads as the table says")
    func everyCellReadsAsTheTableSays() {
        for cell in Self.everyCell {
            #expect(
                cell.outcome == cell.expected,
                """
                read(\(cell.readBefore), \(cell.readAfter)) \(cell.movement.rawValue): \
                got \(cell.outcome.summary)
                """
            )
        }
    }

    /// **The completeness check, and it is self-referential** (repair doctrine, clause 2).
    ///
    /// The space is `{read, unread}² × Movement.allCases`, so its size is derived from the
    /// vocabulary rather than written down: adding a fourth `Movement` grows the space, the fold
    /// above covers the new cells, and this refuses to pass unless the count moved with it.
    ///
    /// And it is non-vacuous in both directions: at least one cell must reach each of the three
    /// outcomes the table can produce, so a `evaluate` that answered `.holds` for everything — the
    /// exact mutation this bead's defect was — fails here as well as above.
    @Test("the fold covers the whole space, and the whole space is not one answer")
    func theFoldCoversTheWholeSpace() {
        #expect(Self.everyCell.count == 2 * 2 * Movement.allCases.count)
        #expect(Self.everyCell.count == 12)

        let outcomes = Self.everyCell.map(\.outcome)
        #expect(outcomes.contains(.holds), "no cell could be judged")
        #expect(
            outcomes.contains(.notTaken(.frontmostApplicationUnavailable)),
            "no cell reported the front as unread — the row this bead is about"
        )
        #expect(
            outcomes.contains(.notTaken(.frontMovedToAnotherApplication)),
            "no cell reported the world moving under the probe"
        )
    }

    /// **The row the defect lived in**, stated as itself so a reader of the log sees it by name.
    ///
    /// Both ends `nil` is the measurement gate run lens6-1 actually took. Before the repair this
    /// answered "taken", because "did it move" was false for two absences.
    @Test("two unread ends are NOT TAKEN, never 'the front did not move'")
    func twoUnreadEndsAreNotTaken() {
        let outcome = SurfaceDeltaReading.evaluate(
            frontWasReadBefore: false,
            frontWasReadAfter: false,
            frontBefore: nil,
            frontAfter: nil,
            ourIdentifier: Self.us
        )
        #expect(!outcome.wasTaken)
        #expect(outcome.obstacle == .frontmostApplicationUnavailable)
        #expect(!outcome.isBroken, "an unmade reading was reported as the defect")
    }

    /// **What this proof would still be green for** (repair doctrine, clause 3).
    ///
    /// It says nothing whatever about whether the panel *took* the front. `.holds` means only
    /// "these two readings may be compared"; a panel that activated the application, became key
    /// and installed a key window produces `movedToUs`, which reads `.holds` here and is caught by
    /// `changedNothing` in the self-check and by the `focus-steal` stage from outside the process.
    /// So this file passing is not evidence of R-89, and asserting it here would be asserting that
    /// a table of preconditions is a proof of the thing it is a precondition for.
    @Test("a front that moved onto us is judgeable, and judged elsewhere")
    func aFrontThatMovedOntoUsIsJudgeableAndJudgedElsewhere() {
        let outcome = SurfaceDeltaReading.evaluate(
            frontWasReadBefore: true,
            frontWasReadAfter: true,
            frontBefore: Self.somebodyElse,
            frontAfter: Self.us,
            ourIdentifier: Self.us
        )
        #expect(outcome == .holds, "the one row that is a real R-89 failure was excused as unmeasured")
    }
}
