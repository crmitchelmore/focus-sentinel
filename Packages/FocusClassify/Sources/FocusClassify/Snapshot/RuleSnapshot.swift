import FocusCore
import FocusRules
import Foundation

/// The active priority, as much of it as a judgement needs.
///
/// `revision` is `FocusSchemaV3.PriorityTask.revision` — already shipped, and already
/// documented in the schema as existing *"because the verdict cache e04 adds keys on it"*. It
/// is what makes an edited priority invalidate every judgement about the old wording (R-63).
public struct PriorityInput: Sendable, Equatable, Hashable, Codable {
    public let id: UUID
    public let revision: Int
    /// The priority as the person wrote it.
    public let intent: String
    /// Their own "done when" phrasing, if they gave one. Tokenised together with the intent,
    /// because "sent to Dana" is as much a description of the work as "write the proposal".
    public let doneWhen: String?

    public init(id: UUID, revision: Int, intent: String, doneWhen: String? = nil) {
        self.id = id
        self.revision = revision
        self.intent = intent
        self.doneWhen = doneWhen
    }

    /// The prose the normaliser and the sentence embedding both see.
    public var prose: String {
        guard let doneWhen, !doneWhen.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return intent }
        return "\(intent) \(doneWhen)"
    }
}

/// One stored rule row, plus the single fact the value type cannot carry.
///
/// `FocusRules.RelevanceRuleValue` has **no `task` field** — the task association lives only on
/// the persisted `FocusSchemaV3.RelevanceRule.task`, so the value the engine consumes cannot
/// tell a task rule from a global one on its own (R-72's withdrawal, verified against the tree
/// at `73c1a1f`). The host reads `task != nil` when it projects the row and passes it here, and
/// that is the whole of the authority derivation: **two authorities from one optional, and the
/// third owned in memory by `SessionRuleBox`, because it was never persistable in the first
/// place.**
public struct StoredRuleRow: Sendable, Equatable, Hashable {
    public let rule: RelevanceRuleValue
    /// `FocusSchemaV3.RelevanceRule.task != nil`, read by whoever projected the row.
    public let isTaskScoped: Bool

    public init(rule: RelevanceRuleValue, isTaskScoped: Bool) {
        self.rule = rule
        self.isTaskScoped = isTaskScoped
    }
}

/// Everything a classification needs, pre-fetched, immutable and cheap to copy.
///
/// `RuleStore` is `async throws` and `SwiftDataRuleStore` is `@MainActor` — its own doc comment
/// worries that *"rule reads happen on the main actor path during classification and must not
/// block it"*. e04 resolves that by **never reading the store during classification at all**
/// (R-65). The snapshot is rebuilt by the host when, and only when, the active priority
/// changes, its revision changes, a rule is written, or a context item is added or removed —
/// all four of which already emit through `PriorityActing`.
///
/// Three things fall out of that and all three are worth the type:
///
/// * **Replay is exact.** A corpus case *is* a snapshot plus an input: no store to stand up, no
///   `ModelContainer`, no actor hop, and therefore a fixture that asserts a byte-identical
///   transcript.
/// * **Latency is a constant.** P-116 measured the priority-side sentence vector at 1.75 ms.
///   Paid once per priority revision here, never per activation.
/// * **The policy travels with the judgement.** `policyDigest` is stamped in at build time, so
///   a snapshot built by one policy version cannot be silently evaluated by another — the
///   engine compares them and refuses.
public struct RuleSnapshot: Sendable, Equatable {
    public let priorityID: UUID?
    /// `0` when there is no priority. Compared against the revision the evidence was captured
    /// for; a mismatch is `uncertain(.staleSnapshot)`, never a guess about the old wording.
    public let priorityRevision: Int
    /// The priority's normalised prose tokens. Computed **once per revision**.
    public let priorityTokens: ProseTokenSet
    /// The priority-side sentence vector, computed once per revision (P-116). `nil` when there
    /// is no priority, when it is not judgeable English, or when this OS has no embedding —
    /// three different facts with the same conservative consequence: no similarity signal.
    public let prioritySentence: SentenceVector?
    /// What the recogniser made of the priority.
    public let priorityLanguage: LanguageReading?
    /// Every rule the cascade may consult, each carrying its own authority and subject kind.
    ///
    /// **One array, not three.** Three parallel arrays would encode the authority order a
    /// second time — in the order somebody wrote the fields — and R-54's whole ruling is that
    /// `CascadePrecedence` is the only place a rung order is written down. Sorted by
    /// `(authority.rank, subjectKind.rank, createdAt, id)`, which is a total order, so a
    /// snapshot is `Equatable` in the way replay needs.
    public let rules: [ScopedRuleValue]
    /// Stored rows this build declined to promote to a rung — today, only legacy
    /// `scopeRaw == "session"` rows (R-72.3).
    ///
    /// **Never zero-suppressed: a skipped row is visible.** The Privacy pane surfaces it beside
    /// the shipped `unreadableRuleCount()`, under the doctrine that store comment already
    /// states: *"the drop is visible rather than silent."*
    public let skippedRuleCount: Int
    public let contextPack: [ContextItemValue]
    /// `RelevancePolicy.digest` at the moment this was built.
    public let policyDigest: UInt64
    public let stamp: EngineStamp

    public init(
        priorityID: UUID?,
        priorityRevision: Int,
        priorityTokens: ProseTokenSet,
        prioritySentence: SentenceVector?,
        priorityLanguage: LanguageReading?,
        rules: [ScopedRuleValue],
        skippedRuleCount: Int,
        contextPack: [ContextItemValue],
        policyDigest: UInt64,
        stamp: EngineStamp
    ) {
        self.priorityID = priorityID
        self.priorityRevision = priorityRevision
        self.priorityTokens = priorityTokens
        self.prioritySentence = prioritySentence
        self.priorityLanguage = priorityLanguage
        self.rules = rules
        self.skippedRuleCount = skippedRuleCount
        self.contextPack = contextPack
        self.policyDigest = policyDigest
        self.stamp = stamp
    }

    /// Whether there is anything to be off-task *from*.
    public var hasActivePriority: Bool { priorityID != nil && !priorityTokens.tokens.isEmpty }

    /// Whether the snapshot was built under the policy this build is running.
    ///
    /// A snapshot that failed this is not a snapshot to reason from: the thresholds that
    /// produced its priority tokens are not the ones about to be applied to them.
    public var matchesRunningPolicy: Bool { policyDigest == RelevancePolicy.digest }

    /// Whether this snapshot describes the priority revision the evidence was captured for.
    public func describes(revision: Int) -> Bool { revision == priorityRevision }

    /// The context items that can constitute a **negative basis** (R-56.1): an identity the
    /// engine could have found the observed subject absent from.
    ///
    /// A `keyword` is excluded because it can only ever match *positively*, so its absence is
    /// the same absence the overlap stage already declined to conclude from. A `file` is
    /// excluded for that reason plus a practical one: at zero grants the engine cannot see
    /// which file is open, so a file item can neither match nor fail to match an observation.
    public var negativeBasisItems: [ContextItemValue] {
        contextPack.filter { RelevancePolicy.negativeBasisKinds.contains($0.kind) }
    }

    /// Whether the priority supplies enough of a basis for an *absence* to mean anything.
    public var hasNegativeBasis: Bool {
        negativeBasisItems.count >= RelevancePolicy.minimumNegativeBasisItems
    }

    /// Whether the priority is judgeable at all — R-56.1's first condition.
    public var hasJudgeablePriority: Bool {
        priorityTokens.tokens.count >= RelevancePolicy.minimumPriorityContentTokens
    }

    /// Every rule at one authority, in narrowness order. What the cascade walks at rungs 0–2.
    public func rules(at authority: RuleAuthority) -> [ScopedRuleValue] {
        rules.filter { $0.authority == authority }
    }

    /// The empty snapshot: no priority, no rules, no context. Classifying against it can only
    /// ever produce `uncertain`, which is the correct answer for a build that has been told
    /// nothing.
    public static func empty(stamp: EngineStamp = .current) -> RuleSnapshot {
        RuleSnapshot(
            priorityID: nil,
            priorityRevision: 0,
            priorityTokens: .empty,
            prioritySentence: nil,
            priorityLanguage: nil,
            rules: [],
            skippedRuleCount: 0,
            contextPack: [],
            policyDigest: RelevancePolicy.digest,
            stamp: stamp
        )
    }
}
