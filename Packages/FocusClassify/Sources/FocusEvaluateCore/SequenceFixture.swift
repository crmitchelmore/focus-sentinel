import FocusClassify
import FocusCore
import Foundation

/// One observation in a replayed stream.
///
/// `advanceSeconds` moves the injected clock **forward from the previous step**, never to an
/// absolute instant, because that is the shape an activation stream actually has and because a
/// fixture written in deltas survives having a step inserted in the middle of it.
public struct SequenceStep: Sendable, Equatable {
    public let advanceSeconds: Int
    public let bundleIdentifier: String?
    public let origin: String?
    public let titleTokens: [String]
    /// How long this subject has held. Defaults to the time since the subject last changed,
    /// which is what the sensing layer reports; an explicit value is for a fixture that wants
    /// to state the dwell rather than derive it.
    public let dwellSeconds: Int?
    public let isUserIdle: Bool
    public let sessionPhase: SessionPhase
    public let expect: SequenceExpectation

    public var subject: String? { bundleIdentifier ?? origin }
}

/// What the fixture claims about one step.
///
/// The verdict and the drift state are required; everything else is optional, because a
/// fixture is entitled to be about one thing. What is *not* optional is the transcript: every
/// step's whole state is recorded and digested whether or not the fixture asserts on it, so two
/// runs that differ anywhere differ visibly (R-69).
public struct SequenceExpectation: Sendable, Equatable {
    public let verdict: Verdict
    /// `aligned` · `grace` · `sustained` · `cooldown`.
    public let drift: String
    public let stage: CascadeStage?
    public let band: EvidenceBand?
    public let eligibility: CorpusEligibility?
    public let clauses: Set<ExplanationClauseKind>?
    /// The drift accumulator, in seconds. The one number that says whether the machine is
    /// counting the thing the fixture author thought it was counting.
    public let accumulatedSeconds: Int?
}

/// A replayable event stream (R-69, F-158, D-05).
///
/// The Court downgraded F-158 to *"a headless sequence-replay harness: serialise F-40 event
/// streams to JSON fixtures and replay them deterministically with an injected clock"*, on the
/// explicit grounds that F-151's single-shot fixtures **cannot express time**. This is the
/// serialised form.
///
/// There is **no recorder**. The bridge from a real run is `ActivityEventStore.exportJSON`,
/// which already ships, is already deterministic — sorted keys, ISO-8601, oldest first — and
/// already re-checks every `detail` through `NormalisedDetail.inspect`. `init(fromExport:)`
/// converts one to the other, which is the recording route the Court kept without the surface
/// it cut.
public struct SequenceFixture: Sendable, Equatable {
    public let id: String
    public let note: String
    public let priority: CorpusPriority?
    public let contextPack: [CorpusContextItem]
    public let rules: [CorpusRule]
    public let steps: [SequenceStep]
    /// How many mandates the whole replay must issue. The single number a reviewer reads first,
    /// and the one a transcript digest alone would not make legible.
    public let expectMandates: Int

    // MARK: - Decoding

    public static func decode(_ object: StrictObject) throws -> SequenceFixture {
        let id = try object.nonEmptyString("id")
        let note = try object.nonEmptyString("note")

        var priority: CorpusPriority?
        var contextPack: [CorpusContextItem] = []
        var rules: [CorpusRule] = []

        if let snapshot = try object.optionalObject("snapshot") {
            if let priorityObject = try snapshot.optionalObject("priority") {
                priority = CorpusPriority(
                    intent: try priorityObject.string("intent"),
                    doneWhen: try priorityObject.optionalString("doneWhen"),
                    revision: try priorityObject.int("revision")
                )
                try priorityObject.finish()
            }
            for item in try snapshot.optionalObjects("contextPack") {
                let kindRaw = try item.string("kind")
                let kind = ContextItemKind(rawValue: kindRaw)
                guard kind.isKnown else {
                    throw CorpusDecodingError(
                        path: "\(item.path).kind", reason: "'\(kindRaw)' is not a context item kind"
                    )
                }
                contextPack.append(
                    CorpusContextItem(kind: kind, value: try item.string("value"))
                )
                try item.finish()
            }
            for rule in try snapshot.optionalObjects("rules") {
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
            try snapshot.finish()
        }

        var steps: [SequenceStep] = []
        for step in try object.objects("steps") {
            let expectObject = try step.object("expect")
            let eligibilityRaw = try expectObject.optionalString("eligibility")
            let clauseNames = try expectObject.optionalStrings("clauses")
            let hasClauses = clauseNames.isEmpty
                ? (try expectObject.optionalBool("assertNoClauses", default: false))
                : true
            let expect = SequenceExpectation(
                verdict: try expectObject.enumeration("verdict", Verdict.self),
                drift: try expectObject.string("drift"),
                stage: try expectObject.optionalEnumeration("stage", CascadeStage.self),
                band: try expectObject.optionalEnumeration("band", EvidenceBand.self),
                eligibility: try eligibilityRaw.map {
                    try CorpusEligibility.decode($0, path: "\(expectObject.path).eligibility")
                },
                clauses: hasClauses
                    ? Set(try clauseNames.map { raw in
                        guard let kind = ExplanationClauseKind(rawValue: raw) else {
                            throw CorpusDecodingError(
                                path: "\(expectObject.path).clauses",
                                reason: "'\(raw)' is not an explanation clause kind"
                            )
                        }
                        return kind
                    })
                    : nil,
                accumulatedSeconds: try expectObject.optionalInt("accumulatedSeconds")
            )
            try expectObject.finish()

            guard Self.driftNames.contains(expect.drift) else {
                throw CorpusDecodingError(
                    path: "\(expectObject.path).drift",
                    reason: "'\(expect.drift)' is not one of "
                        + Self.driftNames.joined(separator: ", ")
                )
            }

            steps.append(
                SequenceStep(
                    advanceSeconds: try step.int("advanceSeconds"),
                    bundleIdentifier: try step.optionalString("bundleID"),
                    origin: try step.optionalString("origin"),
                    titleTokens: try step.optionalStrings("titleTokens"),
                    dwellSeconds: try step.optionalInt("dwellSeconds"),
                    isUserIdle: try step.optionalBool("isUserIdle", default: false),
                    sessionPhase: try step.optionalEnumeration("sessionPhase", SessionPhase.self)
                        ?? .focus,
                    expect: expect
                )
            )
            try step.finish()
        }

        let expectMandates = try object.int("expectMandates")
        try object.finish()

        guard !steps.isEmpty else {
            throw CorpusDecodingError(path: id, reason: "has no steps")
        }
        for step in steps where step.advanceSeconds < 0 {
            throw CorpusDecodingError(
                path: id,
                reason: "advances the clock backwards, which MonotonicClock forbids"
            )
        }

        return SequenceFixture(
            id: id,
            note: note,
            priority: priority,
            contextPack: contextPack,
            rules: rules,
            steps: steps,
            expectMandates: expectMandates
        )
    }

    public static let driftNames = ["aligned", "grace", "sustained", "cooldown"]

    // MARK: - The bridge from a real run (R-69)

    /// Build a fixture from an `ActivityEventStore.exportJSON` payload.
    ///
    /// This is the recording route the Court kept when it cut the recorder UI. The export is
    /// already deterministic and already re-checks every stored `detail` through
    /// `NormalisedDetail.inspect`, so what arrives here is closed-vocabulary tokens, bundle
    /// identifiers, numbers and timestamps — never raw captured content. Only
    /// `frontmostApplicationChanged` rows become steps: the rest of the timeline describes the
    /// session rather than what was on screen.
    ///
    /// The resulting fixture carries **no expectations**: it is a recording, and turning a
    /// recording into a golden fixture means a person reading the transcript and committing what
    /// they agree with. `SequenceReplayHarness.transcript(of:)` prints exactly that.
    public static func decode(
        fromExport data: Data,
        id: String,
        note: String,
        priority: CorpusPriority?,
        contextPack: [CorpusContextItem] = [],
        rules: [CorpusRule] = []
    ) throws -> SequenceFixture {
        let rows: [ActivityEventStore.ExportedEvent]
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            rows = try decoder.decode([ActivityEventStore.ExportedEvent].self, from: data)
        } catch {
            throw CorpusDecodingError(path: id, reason: "is not an exportJSON payload: \(error)")
        }

        let activations = rows
            .filter { $0.kind == ActivityEventKind.frontmostApplicationChanged.rawValue }
            .sorted { $0.at < $1.at }
        guard let first = activations.first else {
            throw CorpusDecodingError(path: id, reason: "carries no frontmost activation")
        }

        var previous = first.at
        var steps: [SequenceStep] = []
        for row in activations {
            let advance = Int(row.at.timeIntervalSince(previous).rounded())
            previous = row.at
            steps.append(
                SequenceStep(
                    advanceSeconds: max(advance, 0),
                    bundleIdentifier: row.bundleID,
                    origin: nil,
                    titleTokens: [],
                    dwellSeconds: row.dwellSeconds.map { Int($0.rounded()) },
                    isUserIdle: false,
                    sessionPhase: .focus,
                    // A recording asserts nothing. The transcript is what a person reads and
                    // then chooses to commit.
                    expect: SequenceExpectation(
                        verdict: .uncertain,
                        drift: "aligned",
                        stage: nil,
                        band: nil,
                        eligibility: nil,
                        clauses: nil,
                        accumulatedSeconds: nil
                    )
                )
            )
        }

        return SequenceFixture(
            id: id,
            note: note,
            priority: priority,
            contextPack: contextPack,
            rules: rules,
            steps: steps,
            expectMandates: 0
        )
    }
}
