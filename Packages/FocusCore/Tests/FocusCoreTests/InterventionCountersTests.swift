import Foundation
import Testing

@testable import FocusCore

/// Counters, and nothing else — and the absence that is the point (R-93, F-107, D-01).
@Suite("Intervention counters")
struct InterventionCountersTests {
    static let decoy = "com.chrismitchelmore.FocusDecoy"
    static let decoy2 = "com.chrismitchelmore.FocusDecoy2"

    // MARK: - The vocabularies

    @Test("there are three dispositions, and the middle one is the deferral")
    func threeDispositions() {
        #expect(InterventionDisposition.allCases.count == 3)
        #expect(
            Set(InterventionDisposition.allCases) == [.delivered, .deferred, .suppressed]
        )
    }

    /// R-79's eight outcomes, by name, in one place — so the persisted column, the counters and
    /// e09's timeline read the same vocabulary rather than three that could drift.
    @Test("there are eight outcomes and every one of them is something a person did")
    func eightOutcomes() {
        #expect(InterventionOutcome.allCases.count == 8)
        #expect(
            Set(InterventionOutcome.allCases) == [
                .dismissed, .corrected, .snoozed, .returned, .pausedSession, .priorityChanged,
                .answered, .ignored
            ]
        )
    }

    /// **The absence that is the ruling.** There is no "effectiveness", no "helped", no
    /// "streak", no score — not as a case, not as a field, and nowhere for one to be added
    /// without a reviewer seeing it. The Court downgraded F-107 to instrumentation and D-01
    /// forbids a score to defend.
    @Test("no counter claims an intervention helped")
    func noCausalClaimAnywhere() {
        let causal = ["effectiv", "helped", "success", "streak", "score", "improv", "compliance"]
        var names = InterventionOutcome.allCases.map(\.rawValue)
            + InterventionDisposition.allCases.map(\.rawValue)
        names += Mirror(reflecting: InterventionCounters.empty).children.compactMap(\.label)
        names += Mirror(
            reflecting: InterventionEvent(
                kind: .query, subject: Self.decoy2, disposition: .delivered
            )
        ).children.compactMap(\.label)

        for name in names {
            for word in causal {
                #expect(
                    !name.lowercased().contains(word),
                    "\(name) reads as a claim that an intervention worked"
                )
            }
        }
    }

    @Test("a correction de-escalates and a dismissal does not")
    func outcomesDeEscalate() {
        for outcome in InterventionOutcome.allCases {
            switch outcome {
            case .dismissed, .ignored:
                #expect(!outcome.deEscalates)
                #expect(outcome.isUnanswered)
            case .corrected, .snoozed, .returned, .pausedSession, .priorityChanged, .answered:
                #expect(outcome.deEscalates)
                #expect(!outcome.isUnanswered)
            }
        }
    }

    // MARK: - Only a delivery spends

    /// **R-81, as arithmetic.** A deferred rung and a suppressed one are both counted — so the
    /// numbers are visible rather than inferred — and neither spends a cap.
    @Test("only a delivered event spends a cap, and the other two are still counted")
    func onlyDeliverySpends() {
        let delivered = InterventionEvent(
            kind: .accusation, rung: .panel, subject: Self.decoy, surface: .panel,
            disposition: .delivered
        )
        let deferred = InterventionEvent(
            kind: .accusation, rung: .ambient, subject: Self.decoy,
            disposition: .deferred, deferralReason: .menuBarHidden
        )
        let suppressed = InterventionEvent(
            kind: .query, subject: Self.decoy2, disposition: .suppressed,
            suppressionReason: .alreadyAsked, queryReason: .noNegativeBasis
        )

        #expect(delivered.spendsBudget)
        #expect(!deferred.spendsBudget)
        #expect(!suppressed.spendsBudget)

        let counters = InterventionCounters.empty
            .recording(delivered)
            .recording(deferred)
            .recording(suppressed)

        #expect(counters.total == 3)
        #expect(counters.count(.delivered) == 1)
        #expect(counters.count(.deferred) == 1)
        #expect(counters.count(.suppressed) == 1)
        #expect(counters.delivered == 1)

        // Per kind: two accusation events, one of which was delivered.
        #expect(counters.count(.accusation) == 2)
        #expect(counters.delivered(.accusation) == 1)
        #expect(counters.count(.query) == 1)
        #expect(counters.delivered(.query) == 0, "a suppressed question spent a cap")
    }

    @Test("an event is counted in every column it belongs to and no column it does not")
    func columnsAreExact() {
        let counters = InterventionCounters.empty.recording(
            InterventionEvent(
                kind: .query,
                subject: Self.decoy2,
                surface: .panel,
                disposition: .delivered,
                outcome: .answered,
                queryReason: .mixedUseApplication,
                originatingAnswer: .yesAddIt
            )
        )

        #expect(counters.byKind == [.query: 1])
        #expect(counters.bySurface == [.panel: 1])
        #expect(counters.byDisposition == [.delivered: 1])
        #expect(counters.byOutcome == [.answered: 1])
        #expect(counters.byQueryReason == [.mixedUseApplication: 1])

        // A question has no rung, no deferral reason and no suppression reason, and none of
        // those columns is invented for it.
        #expect(counters.byRung.isEmpty, "a question was counted on a ladder rung")
        #expect(counters.byDeferralReason.isEmpty)
        #expect(counters.bySuppressionReason.isEmpty)
    }

    @Test("the three ladder rungs are counted separately")
    func rungsAreCountedSeparately() {
        var counters = InterventionCounters.empty
        for kind in LadderRung.Kind.allCases {
            counters.record(
                InterventionEvent(
                    kind: .accusation, rung: kind, subject: Self.decoy,
                    surface: kind == .ambient ? .menuBar : .panel, disposition: .delivered
                )
            )
        }
        #expect(counters.byRung == [.ambient: 1, .panel: 1, .recommitment: 1])
        #expect(counters.bySurface == [.menuBar: 1, .panel: 2])
        #expect(counters.delivered(.accusation) == 3)
    }

    // MARK: - The reported share

    /// Reported and **ungated**: a rising share means the presentation gate is over-firing,
    /// which is a signal for e08 rather than a failure.
    @Test("the deferred share is zero on an empty day and a real ratio afterwards")
    func deferredShare() {
        #expect(InterventionCounters.empty.deferredRungShare == 0)
        #expect(InterventionCounters.empty.total == 0)

        var counters = InterventionCounters.empty
        for _ in 0..<3 {
            counters.record(
                InterventionEvent(
                    kind: .accusation, rung: .panel, subject: Self.decoy, surface: .panel,
                    disposition: .delivered
                )
            )
        }
        counters.record(
            InterventionEvent(
                kind: .accusation, rung: .ambient, subject: Self.decoy,
                disposition: .deferred, deferralReason: .presentationActive
            )
        )
        #expect(counters.total == 4)
        #expect(counters.deferredRungShare == 0.25)
        #expect(counters.byDeferralReason == [.presentationActive: 1])
    }

    /// The field that keeps R-78's distinction visible in the data: a later `unrelated` verdict
    /// sourced from a rule the person wrote by answering "No" is a **user-authored** verdict,
    /// not a query that escalated.
    @Test("a record can name the answer that wrote the rule its verdict rests on")
    func originatingAnswerIsRecorded() {
        let event = InterventionEvent(
            kind: .accusation, rung: .ambient, subject: Self.decoy2, surface: .menuBar,
            disposition: .delivered, outcome: .dismissed, originatingAnswer: .no
        )
        #expect(event.originatingAnswer == .no)
        #expect(event.kind == .accusation)
        #expect(event.queryReason == nil, "an accusation carried a question's reason")

        // And an accusation that nobody's answer produced simply carries none.
        let unattributed = InterventionEvent(
            kind: .accusation, rung: .panel, subject: Self.decoy, surface: .panel,
            disposition: .delivered
        )
        #expect(unattributed.originatingAnswer == nil)
    }

    @Test("the vocabularies round-trip through Codable on their raw values")
    func codableRoundTrip() throws {
        for disposition in InterventionDisposition.allCases {
            let data = try JSONEncoder().encode(disposition)
            #expect(
                try JSONDecoder().decode(InterventionDisposition.self, from: data) == disposition
            )
        }
        for outcome in InterventionOutcome.allCases {
            let data = try JSONEncoder().encode(outcome)
            #expect(try JSONDecoder().decode(InterventionOutcome.self, from: data) == outcome)
        }
    }
}
