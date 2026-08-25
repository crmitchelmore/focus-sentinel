import FocusCore
import Foundation

/// One stretch of a working day spent under **one commitment**.
///
/// A day is segmented by priority rather than by hour, because the priority is the thing every
/// other value in the nudge loop is scoped to: the ledger key carries it (R-78), the per-priority
/// cap counts against it (R-83), and a new commitment legitimately re-opens every question that
/// was ever answered under the old one. Making the priority the segment boundary is what stops a
/// fixture quietly changing a commitment mid-stream and leaving a reader to work out when.
public struct DaySegment: Sendable, Equatable {
    public let priority: CorpusPriority?
    public let contextPack: [CorpusContextItem]
    public let rules: [CorpusRule]
    public let steps: [SequenceStep]
}

/// **A full working day, replayed** (T143c, R-94a).
///
/// A per-judgement rate can look excellent while a day still contains twelve questions, and a bad
/// day is what a person quits over. So `queriesPerFocusDay` and `interruptionsPerFocusDayMax` are
/// measured *here* — on a day with priority changes, breaks, a pause, a presentation, an idle span
/// and a relaunch — rather than being inferred from a corpus of independent single-shot claims.
///
/// Reported as the **maximum** across the committed days, never the mean: a metric that averages a
/// bad day away is a metric that ships a bad day.
public struct DayFixture: Sendable, Equatable {
    public let id: String
    public let note: String
    public let segments: [DaySegment]
    /// Questions the whole day must deliver.
    public let expectQueries: Int
    /// Accusation rungs the whole day must deliver. Not mandates — a rung nobody could see is
    /// deferred, and this counts what a person was actually shown (R-81).
    public let expectAccusations: Int
    /// Both together — the number a person feels, and the one `dailyInterruptionCap` bounds.
    public let expectInterruptions: Int

    // MARK: - Decoding

    public static func decode(_ object: StrictObject) throws -> DayFixture {
        let id = try object.nonEmptyString("id")
        let note = try object.nonEmptyString("note")

        var segments: [DaySegment] = []
        for segment in try object.objects("segments") {
            var priority: CorpusPriority?
            if let priorityObject = try segment.optionalObject("priority") {
                priority = CorpusPriority(
                    intent: try priorityObject.string("intent"),
                    doneWhen: try priorityObject.optionalString("doneWhen"),
                    revision: try priorityObject.int("revision")
                )
                try priorityObject.finish()
            }

            var contextPack: [CorpusContextItem] = []
            for item in try segment.optionalObjects("contextPack") {
                let kindRaw = try item.string("kind")
                let kind = ContextItemKind(rawValue: kindRaw)
                guard kind.isKnown else {
                    throw CorpusDecodingError(
                        path: "\(item.path).kind",
                        reason: "'\(kindRaw)' is not one of "
                            + ContextItemKind.known.map(\.rawValue).joined(separator: ", ")
                    )
                }
                contextPack.append(CorpusContextItem(kind: kind, value: try item.string("value")))
                try item.finish()
            }

            var rules: [CorpusRule] = []
            for rule in try segment.optionalObjects("rules") {
                rules.append(
                    CorpusRule(
                        authority: try rule.enumeration("authority", RuleAuthority.self),
                        subjectKind: try rule.enumeration("subjectKind", RuleSubjectKind.self),
                        subject: try rule.string("subject"),
                        verdict: try rule.enumeration("verdict", PriorityRuleVerdict.self)
                    )
                )
                try rule.finish()
            }

            let steps = try SequenceFixture.decodeSteps(try segment.objects("steps"))
            try segment.finish()

            guard !steps.isEmpty else {
                throw CorpusDecodingError(path: id, reason: "has a segment with no steps")
            }
            segments.append(
                DaySegment(
                    priority: priority, contextPack: contextPack, rules: rules, steps: steps
                )
            )
        }

        let expectQueries = try object.int("expectQueries")
        let expectAccusations = try object.int("expectAccusations")
        let expectInterruptions = try object.int("expectInterruptions")
        try object.finish()

        guard !segments.isEmpty else {
            throw CorpusDecodingError(path: id, reason: "has no segments")
        }
        guard expectInterruptions == expectQueries + expectAccusations else {
            throw CorpusDecodingError(
                path: "\(id).expectInterruptions",
                reason: "is \(expectInterruptions) but the day claims \(expectQueries) question(s) "
                    + "and \(expectAccusations) rung(s) — a person asked ten questions has been "
                    + "interrupted ten times, so the three numbers are one claim and must agree"
            )
        }
        guard expectInterruptions <= InterventionPolicy.dailyInterruptionCap else {
            throw CorpusDecodingError(
                path: "\(id).expectInterruptions",
                reason: "claims \(expectInterruptions) interruptions, above the committed "
                    + "dailyInterruptionCap of \(InterventionPolicy.dailyInterruptionCap) — a day "
                    + "fixture may not commit a day the shipped caps forbid"
            )
        }

        return DayFixture(
            id: id,
            note: note,
            segments: segments,
            expectQueries: expectQueries,
            expectAccusations: expectAccusations,
            expectInterruptions: expectInterruptions
        )
    }
}
