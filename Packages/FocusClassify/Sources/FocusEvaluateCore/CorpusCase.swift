import FocusClassify
import FocusCore
import Foundation

/// The priority a case is judged against.
public struct CorpusPriority: Sendable, Equatable, Hashable {
    public let intent: String
    public let doneWhen: String?
    /// `FocusSchemaV3.PriorityTask.revision`. An edited priority is a different priority.
    public let revision: Int
}

/// One context-pack item, in the four kinds `ContextItemKind` knows.
public struct CorpusContextItem: Sendable, Equatable, Hashable {
    public let kind: ContextItemKind
    public let value: String
}

/// One rule, on **two independent axes** exactly as `ScopedRuleValue` carries them (R-72).
///
/// There is no `scope` field. The earlier draft's single `scope` plus an invented `scopedTo`
/// could not represent a session rule's subject kind at all, because the shipped `RuleScope`
/// makes `.session` mutually exclusive with `app`/`domain`/`titleToken` — which is the finding
/// that rewrote R-72 and the reason this schema has two fields where a reader might expect one.
public struct CorpusRule: Sendable, Equatable, Hashable {
    public let authority: RuleAuthority
    public let subjectKind: RuleSubjectKind
    public let subject: String
    public let verdict: PriorityRuleVerdict
}

/// A persisted row carrying `scopeRaw == "session"`, planted to prove the builder **skips** it
/// (R-72.3).
///
/// Such a row has no subject kind: nothing in it says whether its subject is a bundle
/// identifier, an origin or a title token, and the shipped `SwiftDataRuleStoreTests` plants one
/// of each in the same suite. The engine will not infer one — inferring *"this looks like a
/// bundle identifier"* from the shape of a string is exactly the magic this epic's third
/// binding condition forbids — so the row reaches no rung, is counted in `skippedRuleCount`,
/// and is **never** treated as a contradicting rule.
public struct CorpusLegacyRow: Sendable, Equatable, Hashable {
    public let subject: String
    public let verdict: PriorityRuleVerdict
}

/// What was on screen. `origin` and `titleTokens` are exercised here and **empty in every
/// shipping code path in e04** (F-03 is baseline-only); e07 turns them on by supplying a
/// capability probe, and nothing in this type changes when it does.
public struct CorpusEvidence: Sendable, Equatable, Hashable {
    public let bundleIdentifier: String?
    public let origin: String?
    public let titleTokens: [String]
}

/// Whether the engine was authorised to interrupt, and if not, why not.
public enum CorpusEligibility: Sendable, Equatable, Hashable {
    case mandated
    case suppressed(SuppressionReason)

    /// `"mandated"` or `"suppressed:<SuppressionReason.rawValue>"`.
    public var encoded: String {
        switch self {
        case .mandated: "mandated"
        case .suppressed(let reason): "suppressed:\(reason.rawValue)"
        }
    }

    public static func decode(_ raw: String, path: String) throws -> CorpusEligibility {
        if raw == "mandated" { return .mandated }
        let parts = raw.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2, parts[0] == "suppressed",
              let reason = SuppressionReason.allCases.first(where: { $0.rawValue == parts[1] })
        else {
            throw CorpusDecodingError(
                path: path,
                reason: "'\(raw)' is neither 'mandated' nor 'suppressed:<reason>' from "
                    + SuppressionReason.allCases.map(\.rawValue).joined(separator: ", ")
            )
        }
        return .suppressed(reason)
    }
}

/// **The whole expectation, not the verdict alone.**
///
/// Asserting the verdict by itself would let a case pass for the wrong reason: a case that
/// reaches the right answer by the wrong rung stops catching its bug the next time somebody
/// touches the ladder, and that is exactly how a golden corpus rots into decoration. So every
/// case commits its rung, its band, its eligibility and the *set* of clause kinds as well.
public struct CorpusExpectation: Sendable, Equatable, Hashable {
    public let verdict: Verdict
    public let source: VerdictSource
    public let stage: CascadeStage
    /// `nil` when the verdict is `uncertain`: declining to decide has no evidence to band, and
    /// recording `.low` there would imply a weak *decision* rather than the absence of one.
    public let band: EvidenceBand?
    public let eligibility: CorpusEligibility
    /// Order-independent: an explanation is a set of reasons, not a script.
    public let clauses: Set<ExplanationClauseKind>
    public let uncertaintyReason: UncertaintyReason?
}

/// One committed case (R-66, Appendix A.5).
///
/// Every field is decoded strictly: an unknown key, an unparseable enumeration or a missing
/// expectation fails the *load* rather than defaulting, because a corpus that silently accepts
/// a malformed case is a corpus that silently stops testing something.
public struct CorpusCase: Sendable, Equatable {
    /// `gc-NNNN`, unique and stable **forever**. A renumbered corpus is a corpus whose history
    /// is gone, and several of these ids are named as mutation witnesses in
    /// `RelevancePolicy.manifest` — a case renamed is a witness lost.
    public let id: String
    /// **Non-empty, enforced.** A fixture nobody can explain is a fixture nobody can maintain,
    /// and the first person to "fix" it will delete the bug it was catching.
    public let note: String
    /// Adversarial family names, for the per-family coverage floors.
    public let families: [String]
    /// A family member that *should* resolve, proving the engine discriminates rather than
    /// merely being timid. Excluded from the adversarial uncertainty denominator, so a control
    /// cannot dilute the rate the gate reads.
    public let isNegativeControl: Bool
    public let priority: CorpusPriority?
    public let contextPack: [CorpusContextItem]
    public let rules: [CorpusRule]
    public let legacySessionScopedRows: [CorpusLegacyRow]
    public let expectSkippedRuleCount: Int
    public let evidence: CorpusEvidence
    /// The revision the evidence was captured against, when it differs from the snapshot's —
    /// family 10's whole mechanism, and the corpus half of F-53's cache-key contract.
    public let evidenceRevision: Int?
    public let dwellSeconds: Int
    public let sessionPhase: SessionPhase
    /// Passed to the engine when present, so a fixture can hold the status still while it
    /// varies everything else. Absent means "whatever the engine itself concludes".
    public let focusStatus: FocusStatus?
    public let isUserIdle: Bool
    public let expect: CorpusExpectation
    /// How many `NormalisedToken`s the whole explanation may carry.
    ///
    /// The clause *kinds* alone cannot express `maximumExplanationTokens`: a four-token overlap
    /// and a three-token overlap produce the same single `tokenOverlap` clause, so a corpus that
    /// asserted only kinds would leave that constant with no witness at all — and R-74.1 says a
    /// B constant with no witness fails the suite. This field is what gives it one.
    public let expectExplanationTokens: Int?

    /// The file this case was loaded from, filled in by the loader. Not a JSON field.
    public let file: String

    // MARK: - Decoding

    public static func decode(_ object: StrictObject, file: String) throws -> CorpusCase {
        let id = try object.nonEmptyString("id")
        let note = try object.nonEmptyString("note")
        let families = try object.optionalStrings("families")
        let isNegativeControl = try object.optionalBool("negativeControl", default: false)

        var priority: CorpusPriority?
        if let priorityObject = try object.optionalObject("priority") {
            priority = CorpusPriority(
                intent: try priorityObject.string("intent"),
                doneWhen: try priorityObject.optionalString("doneWhen"),
                revision: try priorityObject.int("revision")
            )
            try priorityObject.finish()
        }

        var contextPack: [CorpusContextItem] = []
        for item in try object.optionalObjects("contextPack") {
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
        for rule in try object.optionalObjects("rules") {
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

        var legacy: [CorpusLegacyRow] = []
        for row in try object.optionalObjects("legacySessionScopedRows") {
            legacy.append(
                CorpusLegacyRow(
                    subject: try row.string("subject"),
                    verdict: try row.enumeration("verdict", PriorityRuleVerdict.self)
                )
            )
            try row.finish()
        }

        let evidenceObject = try object.object("evidence")
        let evidence = CorpusEvidence(
            bundleIdentifier: try evidenceObject.optionalString("bundleID"),
            origin: try evidenceObject.optionalString("origin"),
            titleTokens: try evidenceObject.optionalStrings("titleTokens")
        )
        try evidenceObject.finish()

        let expectObject = try object.object("expect")
        let eligibilityRaw = try expectObject.string("eligibility")
        let expect = CorpusExpectation(
            verdict: try expectObject.enumeration("verdict", Verdict.self),
            source: try expectObject.enumeration("source", VerdictSource.self),
            stage: try expectObject.enumeration("stage", CascadeStage.self),
            band: try expectObject.optionalEnumeration("band", EvidenceBand.self),
            eligibility: try CorpusEligibility.decode(
                eligibilityRaw, path: "\(expectObject.path).eligibility"
            ),
            clauses: Set(
                try expectObject.strings("clauses").map { raw in
                    guard let kind = ExplanationClauseKind(rawValue: raw) else {
                        throw CorpusDecodingError(
                            path: "\(expectObject.path).clauses",
                            reason: "'\(raw)' is not an explanation clause kind"
                        )
                    }
                    return kind
                }
            ),
            uncertaintyReason: try expectObject.optionalEnumeration(
                "uncertaintyReason", UncertaintyReason.self
            )
        )
        try expectObject.finish()

        let expectSkipped = try object.optionalInt("expectSkippedRuleCount") ?? legacy.count
        let expectExplanationTokens = try object.optionalInt("expectExplanationTokens")
        let evidenceRevision = try object.optionalInt("evidenceRevision")
        let dwellSeconds = try object.int("dwellSeconds")
        // `SessionPhase.allCases` rather than `SessionPhase.decode`, deliberately: `decode`
        // maps an unrecognised string onto `.complete`, which is the right answer for a stored
        // row written by a later build and the wrong one for a fixture. A typo in a corpus case
        // must fail the load, not quietly move the case into a phase that suppresses
        // everything. R-45's ban is on `init(rawValue:)`, which this does not use.
        let sessionPhase = try object.enumeration("sessionPhase", SessionPhase.self)
        let focusStatus = try object.optionalEnumeration("focusStatus", FocusStatus.self)
        let isUserIdle = try object.bool("isUserIdle")

        try object.finish()

        guard dwellSeconds >= 0 else {
            throw CorpusDecodingError(
                path: "\(object.path).dwellSeconds", reason: "is negative"
            )
        }
        guard expect.band == nil || expect.verdict != .uncertain else {
            throw CorpusDecodingError(
                path: "\(object.path).expect.band",
                reason: "an uncertain verdict has no evidence to band, so this must be null"
            )
        }
        guard expect.verdict == .uncertain || expect.uncertaintyReason == nil else {
            throw CorpusDecodingError(
                path: "\(object.path).expect.uncertaintyReason",
                reason: "only an uncertain verdict names a reason for declining"
            )
        }

        return CorpusCase(
            id: id,
            note: note,
            families: families,
            isNegativeControl: isNegativeControl,
            priority: priority,
            contextPack: contextPack,
            rules: rules,
            legacySessionScopedRows: legacy,
            expectSkippedRuleCount: expectSkipped,
            evidence: evidence,
            evidenceRevision: evidenceRevision,
            dwellSeconds: dwellSeconds,
            sessionPhase: sessionPhase,
            focusStatus: focusStatus,
            isUserIdle: isUserIdle,
            expect: expect,
            expectExplanationTokens: expectExplanationTokens,
            file: file
        )
    }
}
