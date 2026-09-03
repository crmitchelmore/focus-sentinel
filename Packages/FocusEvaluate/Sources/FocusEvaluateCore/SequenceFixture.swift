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
    /// F-35's gate, as a fixture switch. During a presentation the panel is suppressed and the
    /// ambient rung is **deferred** — the app is mute, not quietly escalating (R-81).
    public let isPresenting: Bool
    /// Whether the system menu bar is on screen. P-131 measured that it is **not** during a
    /// full-screen space while our own status item stays *listed*, which is why this is a
    /// separate reading and not inferred from `isPresenting`.
    public let menuBarVisible: Bool
    public let expect: SequenceExpectation
    /// What the person did after the app spoke, and what became of the world (T143d).
    public let then: SequenceAction

    public var subject: String? { bundleIdentifier ?? origin }
}

/// **What happened after the app spoke** — the half of a nudge fixture a classification fixture
/// never needed.
///
/// A drift machine can be replayed from activations alone; a nudge loop cannot. Whether the next
/// question comes depends on whether the last one was *answered*, whether the last rung was
/// *ignored*, whether the learned rule still exists, and whether the process was restarted — and
/// every one of those is a thing a person did rather than a thing the machine observed. So a
/// fixture states them, and the replay performs them through the same transitions the host does.
public struct SequenceAction: Sendable, Equatable {
    /// The answer to the question currently on screen.
    public let answer: QueryAnswer?
    /// What became of the accusation rung currently on screen.
    public let accusationOutcome: InterventionOutcome?
    /// **Finding 3's sequence.** Remove the learned rule an earlier answer wrote, for this
    /// subject. The subject classifies `uncertain` again and the app still says nothing, because
    /// gate 11 reads the immutable receipt and never the rule (R-78).
    public let deleteLearnedRule: String?
    /// A relaunch. Receipts and the day's caps survive; every session-lived thing does not.
    public let relaunch: Bool
    /// A day boundary in the person's own calendar. The budget empties; the receipts stay,
    /// because a question answered yesterday is still answered.
    public let newDay: Bool

    public static let none = SequenceAction(
        answer: nil,
        accusationOutcome: nil,
        deleteLearnedRule: nil,
        relaunch: false,
        newDay: false
    )

    public var isEmpty: Bool { self == .none }

    static func decode(_ object: StrictObject?) throws -> SequenceAction {
        guard let object else { return .none }
        let action = SequenceAction(
            answer: try object.optionalEnumeration("answer", QueryAnswer.self),
            accusationOutcome: try object.optionalEnumeration(
                "accusationOutcome", InterventionOutcome.self
            ),
            deleteLearnedRule: try object.optionalString("deleteLearnedRule"),
            relaunch: try object.optionalBool("relaunch", default: false),
            newDay: try object.optionalBool("newDay", default: false)
        )
        try object.finish()
        return action
    }
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
    /// **What the nudge loop must do with this step**, when the fixture is about the nudge.
    ///
    /// Optional, because the eighteen fixtures e04 committed are about the classification and
    /// have no business acquiring a claim they were not written to make. Every step's decision is
    /// recorded in the transcript regardless, so a change anywhere is still visible in the digest.
    public let nudge: NudgeExpectation?
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
    /// How many **questions** the whole replay must deliver. `nil` on a fixture that is not about
    /// the nudge, so e04's eighteen keep asserting exactly what they were written to assert.
    public let expectQueries: Int?
    /// How many **accusation rungs** the whole replay must deliver. A mandate is not a delivery:
    /// a rung nobody could see is deferred, and `expectMandates` counts what the engine authorised
    /// while this counts what a person was actually shown (R-81).
    public let expectAccusations: Int?

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

        let steps = try Self.decodeSteps(try object.objects("steps"))

        let expectMandates = try object.int("expectMandates")
        let expectQueries = try object.optionalInt("expectQueries")
        let expectAccusations = try object.optionalInt("expectAccusations")
        try object.finish()

        guard !steps.isEmpty else {
            throw CorpusDecodingError(path: id, reason: "has no steps")
        }
        return SequenceFixture(
            id: id,
            note: note,
            priority: priority,
            contextPack: contextPack,
            rules: rules,
            steps: steps,
            expectMandates: expectMandates,
            expectQueries: expectQueries,
            expectAccusations: expectAccusations
        )
    }

    public static let driftNames = ["aligned", "grace", "sustained", "cooldown"]

    /// Decode a `steps` array.
    ///
    /// Shared with `DayFixture`, which is a sequence per priority rather than a second fixture
    /// format: two step schemas would be two things to keep in step, and the day lane's whole
    /// claim is that it measures the *same* decision the sequence lane does.
    static func decodeSteps(_ objects: [StrictObject]) throws -> [SequenceStep] {
        var steps: [SequenceStep] = []
        for step in objects {
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
                accumulatedSeconds: try expectObject.optionalInt("accumulatedSeconds"),
                nudge: try expectObject.optionalString("nudge").map {
                    try NudgeExpectation.decode($0, path: "\(expectObject.path).nudge")
                }
            )
            try expectObject.finish()

            guard Self.driftNames.contains(expect.drift) else {
                throw CorpusDecodingError(
                    path: "\(expectObject.path).drift",
                    reason: "'\(expect.drift)' is not one of "
                        + Self.driftNames.joined(separator: ", ")
                )
            }

            let advance = try step.int("advanceSeconds")
            guard advance >= 0 else {
                throw CorpusDecodingError(
                    path: "\(step.path).advanceSeconds",
                    reason: "advances the clock backwards, which MonotonicClock forbids"
                )
            }

            steps.append(
                SequenceStep(
                    advanceSeconds: advance,
                    bundleIdentifier: try step.optionalString("bundleID"),
                    origin: try step.optionalString("origin"),
                    titleTokens: try step.optionalStrings("titleTokens"),
                    dwellSeconds: try step.optionalInt("dwellSeconds"),
                    isUserIdle: try step.optionalBool("isUserIdle", default: false),
                    sessionPhase: try step.optionalEnumeration("sessionPhase", SessionPhase.self)
                        ?? .focus,
                    isPresenting: try step.optionalBool("isPresenting", default: false),
                    menuBarVisible: try step.optionalBool("menuBarVisible", default: true),
                    expect: expect,
                    then: try SequenceAction.decode(try step.optionalObject("then"))
                )
            )
            try step.finish()
        }
        return steps
    }

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
                    isPresenting: false,
                    menuBarVisible: true,
                    // A recording asserts nothing. The transcript is what a person reads and
                    // then chooses to commit.
                    expect: SequenceExpectation(
                        verdict: .uncertain,
                        drift: "aligned",
                        stage: nil,
                        band: nil,
                        eligibility: nil,
                        clauses: nil,
                        accumulatedSeconds: nil,
                        nudge: nil
                    ),
                    then: .none
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
            expectMandates: 0,
            expectQueries: nil,
            expectAccusations: nil
        )
    }
}
