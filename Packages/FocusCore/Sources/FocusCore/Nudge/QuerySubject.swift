import Foundation

/// **What a question is about**, and the reason a question can never be about "something".
///
/// U-1 licenses the app to ask when it cannot tell. It does not license it to ask an
/// unanswerable question, and *"is something part of your task?"* is unanswerable. So the
/// subject of a query is a single named thing or there is no query at all:
///
/// * there is **no `mixed` case**, deliberately. `DriftState` has one — drift really can
///   accumulate across several unrelated applications, and an accusation reports that
///   honestly as "several unrelated apps" (e04's `InterventionMandate.isMixed`). A question
///   has no such form, so `QueryEligibility` withholds with `.noSingleSubject` rather than
///   inventing a name (R-76);
/// * there is **no public initialiser**. The memberwise one is `fileprivate` and this file
///   holds exactly one function that calls it, so a subject cannot be conjured at a call
///   site that has no judgement in front of it.
///
/// ## Where the identifier is allowed to come from
///
/// Two places, both of which the judgement itself used, and the value records which one it
/// was so that the choice is auditable rather than assumed:
///
/// | provenance | what it is |
/// |---|---|
/// | `.explanationClause` | a subject the explanation *names* — a seed default or the mixed-use seed fallback. This is the narrowest, best-evidenced answer and is preferred whenever it exists |
/// | `.judgedActivation` | the bundle identifier or normalised origin the classification was **about**. The `noNegativeBasis` route to `uncertain` — 32 of the corpus's 72 uncertain verdicts (P-138) — produces an explanation with no subject clause at all, because there was no rule, no seed and no context item to name; what there *was* is the application in front of the person, which is precisely what the judgement was made about |
///
/// There is no third source. A correction therefore cannot name a subject the judgement did
/// not use — which is R-86's rule, stated as a property of this type rather than as a comment
/// on the call site — and P-140's finding is honoured exactly: an activation carrying **no**
/// bundle identifier (`gc-0011`, `gc-0139`) yields `nil` here and is unaskable.
public struct QuerySubject: Sendable, Equatable, Hashable {
    /// Which of the two permitted sources the identifier came from.
    public enum Provenance: String, Sendable, CaseIterable, Codable, Hashable {
        /// A subject the explanation itself names.
        case explanationClause
        /// The subject the classification was made about.
        case judgedActivation
    }

    /// How narrow the rule an answer writes will be. `.app` at baseline; e07's origin signal
    /// makes `.domain` reachable without changing this type, the query, the ledger or the
    /// metric.
    public let kind: RuleSubjectKind
    /// The bundle identifier or normalised `scheme://host[:port]` origin. Never empty.
    public let identifier: String
    /// Which of the two permitted sources supplied `identifier`.
    public let provenance: Provenance

    /// **Fileprivate on purpose.** `derive(judgedSubject:explanation:)` below is the only
    /// caller in the programme.
    fileprivate init(kind: RuleSubjectKind, identifier: String, provenance: Provenance) {
        self.kind = kind
        self.identifier = identifier
        self.provenance = provenance
    }

    /// The one route to a subject.
    ///
    /// - Parameters:
    ///   - judgedSubject: the bundle identifier or normalised origin the classification was
    ///     about, exactly as the evidence carried it. `nil` when the activation had none —
    ///     e03's P-83 measured six unbundled processes in ninety-two — in which case there is
    ///     nothing to write a rule *about* and the answer is `nil`.
    ///   - explanation: the judgement's own reasoning. Consulted first, because a subject the
    ///     explanation names is a subject the engine demonstrably used.
    /// - Returns: the subject, or `nil` when there is no single nameable one.
    public static func derive(
        judgedSubject: String?,
        explanation: Explanation
    ) -> QuerySubject? {
        if let named = explanationSubject(explanation) {
            return QuerySubject(
                kind: kind(of: named),
                identifier: named,
                provenance: .explanationClause
            )
        }
        guard let judged = nameable(judgedSubject) else { return nil }
        return QuerySubject(
            kind: kind(of: judged),
            identifier: judged,
            provenance: .judgedActivation
        )
    }

    /// The first subject an explanation *names*, in clause order.
    ///
    /// Only the two clauses that carry a subject the engine reached a conclusion **about** are
    /// read. `contextItem` and `userRule` are deliberately not: a subject named by one of those
    /// has already been decided, so a question about it would be the app failing to read its
    /// own notes — the defect `nudge.queryOnDecidableCount == 0` gates at exactly zero.
    private static func explanationSubject(_ explanation: Explanation) -> String? {
        for clause in explanation.clauses {
            switch clause {
            case .seedFallbackMixedUse(let subject):
                if let value = nameable(subject.value) { return value }
            case .seedDefault(_, let subject):
                if let value = nameable(subject.value) { return value }
            case .userRule, .contextItem, .tokenOverlap, .similarityCorroborated,
                 .sustainedDwell, .returnedToAnchor, .mixedSubjects, .conflictingRules,
                 .insufficientEvidence, .languageNotSupported, .noNegativeBasis:
                continue
            }
        }
        return nil
    }

    /// A candidate that is actually nameable to a person, or `nil`.
    ///
    /// Empty and whitespace-only are the two shapes an absent identifier arrives in — e04's
    /// `InterventionMandate` carries `""` for a mixed subject — and neither is something a
    /// question could be about.
    private static func nameable(_ candidate: String?) -> String? {
        guard let candidate else { return nil }
        let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// `.domain` for a normalised origin, `.app` for everything else.
    ///
    /// `OriginNormalizer` emits `scheme://host[:port]` and nothing else does, so the separator
    /// is a reliable discriminator. `NormalisedToken` cannot hold one — it rejects `:` and `/`
    /// — so a subject taken from an explanation clause is always `.app`-shaped, which is the
    /// honest baseline until e07 gives the engine an origin to reason with.
    ///
    /// The test itself lives on `NudgeSubject`, which has to make the same distinction to decide
    /// whether a display name is *looked up* or *derived* (focus-ebv). Two copies of a
    /// discriminator are two things to keep in step; this is one, called from both.
    private static func kind(of identifier: String) -> RuleSubjectKind {
        NudgeSubject.isOrigin(identifier) ? .domain : .app
    }
}

extension QuerySubject: CustomStringConvertible {
    public var description: String { identifier }
}
