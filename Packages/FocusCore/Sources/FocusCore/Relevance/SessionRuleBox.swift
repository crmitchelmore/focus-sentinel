import Foundation

/// The **only** owner of the session authority (R-72.2).
///
/// ## Why this is a box and not a table
///
/// `RuleAuthority` has three levels and the shipped schema can express exactly two of them.
/// `FocusSchemaV3.RelevanceRule.task` is an optional, which gives *task* and *global*; the
/// third — a rule that lives until this focus session ends — has no persisted home, and giving
/// it one would be a mistake rather than an omission. **A session rule that survived a relaunch
/// would be a session rule that outlived its session**, and the cheapest way to guarantee that
/// cannot happen is to give it no persistence to reach.
///
/// So: in memory, `@MainActor`, and deliberately conforming to **no** storage protocol. It
/// cannot conform to `FocusRules.RuleStore` even by accident, because `FocusCore` may not
/// import `FocusRules` at all (the R-14 matrix, enforced by lint) — a stronger guarantee than
/// the absence of a conformance somebody could add later.
///
/// The shipped `RuleScope.session` case is **not** this. That case is mutually exclusive with
/// `app`/`domain`/`titleToken`, so a row carrying it has no subject kind at all, and
/// `RuleSnapshotBuilder` skips and counts such rows rather than inferring one (R-72.3). Lint
/// R-70n stops the ambiguous shape being revived: the next person who needs a session rule must
/// reach for this box, not for that enum case.
///
/// ## The lifetime contract, and which halves are structural
///
/// | it dies when | how |
/// |---|---|
/// | the session ends, or a different one begins | `clear(sessionID:)`, from the session host's transition handler |
/// | the priority changes | **structurally** — the key carries the priority, so a rule written under one is invisible under another |
/// | the process exits | **structurally** — there is nothing persisted to come back |
///
/// Two of the three need no hook at all, which is the point: a lifetime enforced by a call
/// somebody has to remember is a lifetime that will one day be forgotten.
///
/// ## Nothing in e04 writes to it
///
/// e05 owns the one-click *"not now"* affordance that creates a session rule; e04 supplies the
/// shape it will write into, exercises it from the corpus, and clears it from the host. That is
/// deliberate — the correction economy needs a surface to be corrected *from*, and this epic
/// has no nudge to correct.
@MainActor
public final class SessionRuleBox {
    /// What a session rule is scoped to: this session **and** this priority.
    ///
    /// The priority is part of the key rather than something a hook has to clear, because
    /// "until the priority changes" is then a property of lookup rather than of housekeeping.
    /// `nil` is a real key: a session with no active priority can still carry a rule, and it
    /// must not be visible once one is set.
    public struct Key: Sendable, Equatable, Hashable {
        public let sessionID: UUID
        public let priorityID: UUID?

        public init(sessionID: UUID, priorityID: UUID?) {
            self.sessionID = sessionID
            self.priorityID = priorityID
        }
    }

    private var storage: [Key: [ScopedRuleValue]] = [:]

    public init() {}

    /// Every session rule that applies right now, in the snapshot's total order.
    ///
    /// Sorted here rather than at insertion so that the array a snapshot holds is `==` between
    /// two builds of the same box — which is what replay needs.
    public func rules(forSession sessionID: UUID, priorityID: UUID?) -> [ScopedRuleValue] {
        (storage[Key(sessionID: sessionID, priorityID: priorityID)] ?? [])
            .sorted(by: ScopedRuleValue.precedes)
    }

    /// Add a rule, or replace the one that already claims the same subject.
    ///
    /// The rule's authority is **forced** to `.session` rather than trusted: this box is the
    /// definition of that authority, and a value arriving with another one would be a rule
    /// claiming a lifetime the box cannot give it.
    public func insert(
        _ rule: ScopedRuleValue,
        forSession sessionID: UUID,
        priorityID: UUID?
    ) {
        let key = Key(sessionID: sessionID, priorityID: priorityID)
        let scoped = ScopedRuleValue(
            id: rule.id,
            authority: .session,
            subjectKind: rule.subjectKind,
            subject: rule.subject,
            verdict: rule.verdict,
            createdAt: rule.createdAt
        )
        var existing = storage[key] ?? []
        existing.removeAll { $0.subjectKind == scoped.subjectKind && $0.subject == scoped.subject }
        existing.append(scoped)
        storage[key] = existing
    }

    /// Forget every rule this session carried, under **every** priority it held.
    ///
    /// Called from the session host's transition handler, which already fires on every phase
    /// change — so the rule dies the moment the session it belonged to does, rather than the
    /// next time something happens to look.
    public func clear(sessionID: UUID) {
        storage.removeAll { $0.key.sessionID == sessionID }
    }

    /// Forget everything. The self-check's reset, and the answer to "the process is going away"
    /// for anyone who would rather say it than rely on it.
    public func clearAll() {
        storage.removeAll()
    }

    public var isEmpty: Bool { storage.allSatisfy { $0.value.isEmpty } }

    /// How many rules the box holds in total. Surfaced by the self-check, so "a fresh box is
    /// empty" is an observation rather than an assumption.
    public var count: Int { storage.values.reduce(0) { $0 + $1.count } }
}

private extension Dictionary {
    /// `removeAll(where:)` for a dictionary, which the standard library does not supply.
    mutating func removeAll(where shouldRemove: (Element) -> Bool) {
        for element in self where shouldRemove(element) {
            removeValue(forKey: element.key)
        }
    }
}
