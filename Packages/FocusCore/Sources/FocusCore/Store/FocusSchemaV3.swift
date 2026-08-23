import Foundation
import SwiftData

/// Schema version 3 of the Focus Sentinel store.
///
/// The `@Model` classes are nested **inside** the versioned schema, exactly as v1's and v2's
/// are: that is what makes a version bump a rename of a namespace rather than a rewrite of
/// every call site. `FocusSchemaV1` and `FocusSchemaV2` stay in the repository unchanged and
/// untouched — they are the migration sources and the committed fixtures' schemas, and a
/// migration source you have edited proves nothing.
///
/// ## What changed against v2
///
/// e03 gives the app eyes and a session runtime, and both need somewhere to live:
///
/// * `FocusSessionRecord` grows the whole session runtime — the phase-change timestamp, the
///   phase to resume into, the session kind and its timebox, the **restoration anchor**
///   (`uptimeAnchorSeconds` + `bootIdentity`), the pause-cause set, and the interruption
///   capture — plus a cascading `transitions` log.
/// * `SessionTransitionRecord` is new: one row per **accepted** transition, and one per
///   cause-set change. Rejected transitions write nothing at all, which is what keeps the
///   timeline a record of what happened rather than of what was attempted.
/// * `ActivityEvent` gains `sessionID`, `dwellSeconds` and `displayID`. `detail` is
///   unchanged and still a `String?`; what may be *put* in it is narrowed by
///   `NormalisedDetail`, which has no `String` initialiser, and by a lint.
/// * `SensitiveAppEntry` is new: the bundle-identifier list the sensitivity gate consults.
///   It is data, it is seeded conservatively, and every row is user-removable.
/// * `CapabilityRecord` is new, including `educationShownAt` — the persisted half of F-127's
///   never-re-prompt policy. e03 never prompts at all, so it is declared **now** precisely so
///   that the epic which does adds a behaviour and not a migration.
/// * `AppSettingsRecord` gains five sensing settings, every one with a property default.
///
/// **Every addition is either optional or carries a property default**, which e02's probe
/// P-51 measured to be exactly the condition for a *lightweight* migration stage. Nothing is
/// removed and nothing is renamed, so `FocusMigrationPlan`'s v2 → v3 stage carries no code.
///
/// Enum-backed fields remain `String` raw values (e01's R-05): reordering a Swift enum can
/// never silently reinterpret a persisted row.
public enum FocusSchemaV3: VersionedSchema {
    public static var versionIdentifier: Schema.Version {
        Schema.Version(3, 0, 0)
    }

    public static var models: [any PersistentModel.Type] {
        [
            PriorityTask.self,
            ActivePriority.self,
            ContextItem.self,
            FocusSessionRecord.self,
            SessionTransitionRecord.self,
            ActivityEvent.self,
            RelevanceRule.self,
            SensitiveAppEntry.self,
            CapabilityRecord.self,
            AppSettingsRecord.self
        ]
    }

    /// `keyCode 49` is the Space bar. The default quick-capture shortcut is ⌃⌥⌘Space.
    ///
    /// ⌘Space is deliberately *not* the default: probe P-55 measured that
    /// `RegisterEventHotKey` will happily take Spotlight's combination and report success,
    /// so the app must not be able to steal a system shortcut by shipping one as its default.
    public static let defaultHotKeyKeyCode = 49

    /// `control | option | command`, as `NSEvent.ModifierFlags` raw values
    /// (`1 << 18 | 1 << 19 | 1 << 20`).
    ///
    /// The integer is stored rather than a symbolic value because `FocusCore` may not import
    /// AppKit; `FocusSensing`'s registrar translates it to the Carbon mask it needs.
    public static let defaultHotKeyModifierFlags = (1 << 18) | (1 << 19) | (1 << 20)

    /// The idle threshold, in seconds, above which the user is treated as away (R-36).
    public static let defaultIdleThresholdSeconds = 180

    /// The corroboration tick, in seconds (R-38).
    ///
    /// Two of e03's signals — Space membership and presentation state — have no reliable
    /// notification: probe P-92 measured `activeSpaceDidChangeNotification` never firing
    /// across four full-screen cycles. The tick is what makes re-evaluation a contract
    /// instead of a hope, and five seconds is affordable because a window-list read costs
    /// 0.296 ms at the median (P-76).
    public static let defaultCorroborationTickSeconds = 5

    /// The single highest-priority thing the user is trying to do.
    ///
    /// There is no `isActive` column. The active priority is whichever task the one
    /// `ActivePriority` row points at, and `isActive` is a projection of that pointer.
    /// Two sources of truth for "which task am I doing" is the bug this shape prevents.
    ///
    /// `revision` is bumped whenever `intent` or `doneWhen` changes, because the verdict
    /// cache e04 adds keys on it: when the user edits their priority, every cached judgement
    /// about the old wording must become stale.
    @Model
    public final class PriorityTask {
        public var id: UUID
        /// What the user wrote, in their own words.
        public var intent: String
        /// The user's own completion criterion, if they gave one.
        public var doneWhen: String?
        public var createdAt: Date
        public var completedAt: Date?
        /// Bumped whenever `intent` or `doneWhen` changes.
        public var revision: Int
        /// The optional timebox, in seconds. `nil` is "no timebox", which is a real answer.
        public var timeboxSeconds: Int?
        /// When the timebox started running. Wall clock, deliberately: a timebox is a promise
        /// about the clock on the wall, so a Mac that slept for an hour has spent that hour.
        public var startedAt: Date?
        /// F-22's first reflection field: what shipped. Optional, and completion never waits
        /// for it.
        public var shipped: String?
        /// F-22's second reflection field: where to restart.
        public var restartPoint: String?
        /// When this task was last made the active priority. F-15's history orders by it.
        public var lastActivatedAt: Date?

        @Relationship(deleteRule: .cascade, inverse: \ContextItem.task)
        public var contextItems: [ContextItem] = []

        @Relationship(deleteRule: .cascade, inverse: \RelevanceRule.task)
        public var rules: [RelevanceRule] = []

        @Relationship(deleteRule: .cascade, inverse: \ActivePriority.task)
        public var activePointer: ActivePriority?

        /// Whether this is the active priority — a projection of the pointer, never a column.
        public var isActive: Bool { activePointer != nil }

        public init(
            id: UUID = UUID(),
            intent: String,
            doneWhen: String? = nil,
            createdAt: Date,
            completedAt: Date? = nil,
            revision: Int = 1,
            timeboxSeconds: Int? = nil,
            startedAt: Date? = nil,
            shipped: String? = nil,
            restartPoint: String? = nil,
            lastActivatedAt: Date? = nil
        ) {
            self.id = id
            self.intent = intent
            self.doneWhen = doneWhen
            self.createdAt = createdAt
            self.completedAt = completedAt
            self.revision = revision
            self.timeboxSeconds = timeboxSeconds
            self.startedAt = startedAt
            self.shipped = shipped
            self.restartPoint = restartPoint
            self.lastActivatedAt = lastActivatedAt
        }
    }

    /// The single-active-priority invariant, enforced by the store rather than by a code path
    /// someone could forget.
    ///
    /// `slot` is always `"active"` and is unique, so the database cannot hold two of these. A
    /// second activation therefore *replaces*, never queues — and because the row that gets
    /// replaced is a pointer, nothing the user wrote is ever what the constraint destroys.
    ///
    /// The application must never insert a second row to provoke that replacement:
    /// `PriorityStore.activate(_:)` re-points the existing row. Inserting a colliding row whose
    /// target already owns one is a **process fatal error** in SwiftData
    /// ("This relationship already has a value but it's not the target"), and re-activating the
    /// current priority is an ordinary thing for a person to do.
    @Model
    public final class ActivePriority {
        @Attribute(.unique) public var slot: String
        public var task: PriorityTask?
        public var activatedAt: Date

        public init(
            slot: String = ActivePriority.singletonSlot,
            task: PriorityTask?,
            activatedAt: Date
        ) {
            self.slot = slot
            self.task = task
            self.activatedAt = activatedAt
        }

        public static let singletonSlot = "active"
    }

    /// One item in a task's context pack.
    ///
    /// Four kinds and no fifth: an application, a normalised web origin, a keyword, or a file.
    /// `kindRaw` is a string so that a build which does not know a stored kind renders it as
    /// an inert chip rather than dropping the row or crashing on it.
    ///
    /// `value` for a file is the path **at the time of adding**, kept for display only; the
    /// durable handle is `bookmark`, a `.withSecurityScope` bookmark. A path is not a file.
    @Model
    public final class ContextItem {
        public var id: UUID
        /// `ContextItemKind` raw value.
        public var kindRaw: String
        /// The normalised subject: a bundle identifier, a `scheme://host[:port]` origin, a
        /// lowercased keyword, or a file path recorded when the item was added.
        public var value: String
        /// What the chip shows: an application's display name, a host, the keyword, or a file
        /// name.
        public var displayName: String
        /// A security-scoped bookmark, for file items only.
        public var bookmark: Data?
        public var addedAt: Date
        public var task: PriorityTask?

        public init(
            id: UUID = UUID(),
            kindRaw: String,
            value: String,
            displayName: String,
            bookmark: Data? = nil,
            addedAt: Date,
            task: PriorityTask? = nil
        ) {
            self.id = id
            self.kindRaw = kindRaw
            self.value = value
            self.displayName = displayName
            self.bookmark = bookmark
            self.addedAt = addedAt
            self.task = task
        }
    }

    /// One stretch of focused work — and, from v3, the whole persisted session runtime.
    ///
    /// ## `startedAt` is never rewritten
    ///
    /// Not on restore, not on resume, not ever. Every elapsed figure the user sees is derived
    /// from it and from an injected wall clock, and there is **no timer object anywhere in
    /// this programme** — which is the strongest available form of the Court's binding
    /// condition that a restored session must never blindly restart its timer.
    ///
    /// ## Why there are two clocks and a boot identity
    ///
    /// `uptimeAnchorSeconds` is seconds since boot at the last phase change, taken from
    /// `mach_continuous_time()` through the `UptimeClock` seam. Measured (P-106): two separate
    /// process launches two seconds apart read `741532.264` and `741534.294` — a delta
    /// matching the wall delta to 0.1 ms — while `kern.boottime` read byte-identically in
    /// both. So the anchor is comparable across processes **on one boot** and meaningless
    /// after a reboot, and `bootIdentity` is the grant-free string that says which of the two
    /// you are in.
    ///
    /// It is deliberately **not** a `ContinuousClock.Instant`: that type has no public numeric
    /// conversion at all (P-105, `Double(ContinuousClock().now)` does not compile), and e01's
    /// `SystemMonotonicClock` takes its origin in `init`, so its elapsed is process-relative
    /// and could never span two launches.
    ///
    /// The anchor keeps counting across system sleep, so a four-hour sleep advances the wall
    /// clock and the anchor **together** and raises no anomaly. What makes them diverge is a
    /// wall-clock correction or a reboot, which is exactly what the reconciler reports.
    @Model
    public final class FocusSessionRecord {
        public var id: UUID
        /// The priority this session was about, if there was one.
        public var taskID: UUID?
        public var startedAt: Date
        public var endedAt: Date?
        /// `SessionPhase` raw value. Decoded through `SessionPhase.decode(_:)`, which carries
        /// the v1/v2 aliases (`running` → `focus`, `ended` → `complete`).
        public var phaseRaw: String
        /// When the phase last changed. Wall clock, because it is what a person reading a
        /// timeline tomorrow needs it to mean.
        public var phaseChangedAt: Date?
        /// `ResumablePhase` raw value: the phase a resume returns to. Set at the **first**
        /// pause and never overwritten by a later cause.
        public var resumeToRaw: String?
        /// `SessionKind` raw value: `openEnded`, `countdown` or `deadline`.
        public var kindRaw: String = "openEnded"
        /// The countdown's length, for a `countdown` session.
        public var plannedSeconds: Int?
        /// The wall-clock deadline, for a `deadline` session.
        public var deadlineAt: Date?
        /// Seconds since boot at the last phase change. See the type note above.
        public var uptimeAnchorSeconds: Double?
        /// `"<kern.boottime.sec>.<usec>"`. Non-empty exactly when `uptimeAnchorSeconds` is.
        public var bootIdentity: String?
        /// The `PauseReason` set the session is paused for, sorted and comma-joined.
        ///
        /// A string rather than a table because it is a small closed vocabulary that is only
        /// ever read as a whole; sorted so the encoding is deterministic; and `nil` or empty
        /// for every non-paused phase, which is the persisted half of the invariant that the
        /// cause set is non-empty **if and only if** the phase is `paused`.
        public var pauseCausesRaw: String?
        /// `InterruptionReason` raw value, for an interrupted session.
        public var interruptionReasonRaw: String?
        /// The user's own note about where to pick this up again. Their words, optional, and
        /// completion never waits for it.
        public var restartPointNote: String?
        /// The bundle identifier of whatever was frontmost when the session was interrupted.
        /// A bundle identifier and nothing else — never a window title, never a document.
        public var lastActiveBundleID: String?

        @Relationship(deleteRule: .cascade, inverse: \SessionTransitionRecord.session)
        public var transitions: [SessionTransitionRecord] = []

        public init(
            id: UUID = UUID(),
            taskID: UUID? = nil,
            startedAt: Date,
            endedAt: Date? = nil,
            phaseRaw: String,
            phaseChangedAt: Date? = nil,
            resumeToRaw: String? = nil,
            kindRaw: String = "openEnded",
            plannedSeconds: Int? = nil,
            deadlineAt: Date? = nil,
            uptimeAnchorSeconds: Double? = nil,
            bootIdentity: String? = nil,
            pauseCausesRaw: String? = nil,
            interruptionReasonRaw: String? = nil,
            restartPointNote: String? = nil,
            lastActiveBundleID: String? = nil
        ) {
            self.id = id
            self.taskID = taskID
            self.startedAt = startedAt
            self.endedAt = endedAt
            self.phaseRaw = phaseRaw
            self.phaseChangedAt = phaseChangedAt
            self.resumeToRaw = resumeToRaw
            self.kindRaw = kindRaw
            self.plannedSeconds = plannedSeconds
            self.deadlineAt = deadlineAt
            self.uptimeAnchorSeconds = uptimeAnchorSeconds
            self.bootIdentity = bootIdentity
            self.pauseCausesRaw = pauseCausesRaw
            self.interruptionReasonRaw = interruptionReasonRaw
            self.restartPointNote = restartPointNote
            self.lastActiveBundleID = lastActiveBundleID
        }
    }

    /// One **accepted** session transition. New in v3.
    ///
    /// Rejected transitions write nothing at all: a timeline that records what the caller
    /// attempted rather than what happened is a timeline that lies to the person reading it.
    ///
    /// `outcomeRaw` distinguishes the three accepted outcomes. `accepted` is an ordinary
    /// phase change. `causeAdded` and `causeRemoved` are the pause-cause outcomes, where the
    /// cause set changed but the phase did not — those rows carry `fromRaw == toRaw` and no
    /// phase-change timestamp moves, and they exist because a session paused for two reasons
    /// needs both cleared and the user is entitled to see why.
    @Model
    public final class SessionTransitionRecord {
        public var id: UUID
        public var at: Date
        /// `SessionPhase` raw value before the event.
        public var fromRaw: String
        /// `SessionPhase` raw value after it. Equal to `fromRaw` for a cause-set outcome.
        public var toRaw: String
        /// The `SessionEvent` kind's raw value.
        public var eventRaw: String
        /// The event's own reason or cause, if it carried one: a `PauseReason`,
        /// `BreakReason`, `DetourReason` or `InterruptionReason` raw value.
        public var reasonRaw: String?
        /// `accepted`, `causeAdded` or `causeRemoved`.
        public var outcomeRaw: String = "accepted"
        public var session: FocusSessionRecord?

        public init(
            id: UUID = UUID(),
            at: Date,
            fromRaw: String,
            toRaw: String,
            eventRaw: String,
            reasonRaw: String? = nil,
            outcomeRaw: String = "accepted",
            session: FocusSessionRecord? = nil
        ) {
            self.id = id
            self.at = at
            self.fromRaw = fromRaw
            self.toRaw = toRaw
            self.eventRaw = eventRaw
            self.reasonRaw = reasonRaw
            self.outcomeRaw = outcomeRaw
            self.session = session
        }
    }

    /// One normalised observation.
    ///
    /// **Normalised evidence only, never raw captured content.** `detail` is a `String?` in
    /// the store because that is what a column is, but nothing in the shipping graph may
    /// assign to it except through `NormalisedDetail`, whose only initialisers take a closed
    /// vocabulary of tokens or a typed measurement. There is no `NormalisedDetail(String)`,
    /// so a window title, a URL, a document name or a file path is not merely forbidden —
    /// it is unrepresentable. A lint catches the one route left.
    @Model
    public final class ActivityEvent {
        public var id: UUID
        public var at: Date
        /// The observation kind's raw value.
        public var kindRaw: String
        public var bundleID: String?
        public var detail: String?
        /// The session this observation belongs to, if there was one.
        public var sessionID: UUID?
        /// How long the previous application had been frontmost, in seconds.
        ///
        /// **Monotonic**, from `MonotonicClock` — a duration inside one process, which is the
        /// one quantity here that is not wall-clock. `at` above is wall-clock, from the
        /// injected `DateProvider`, because it is what a person reads tomorrow.
        public var dwellSeconds: Double?
        /// Which display the observation happened on, as a `CGDirectDisplayID`.
        public var displayID: Int?

        public init(
            id: UUID = UUID(),
            at: Date,
            kindRaw: String,
            bundleID: String? = nil,
            detail: String? = nil,
            sessionID: UUID? = nil,
            dwellSeconds: Double? = nil,
            displayID: Int? = nil
        ) {
            self.id = id
            self.at = at
            self.kindRaw = kindRaw
            self.bundleID = bundleID
            self.detail = detail
            self.sessionID = sessionID
            self.dwellSeconds = dwellSeconds
            self.displayID = displayID
        }
    }

    /// One stored user judgement about a subject.
    ///
    /// A rule is either **global** (`task == nil`, which is what e04's engine reads) or
    /// scoped to exactly one priority, in which case it cascades away with that priority.
    @Model
    public final class RelevanceRule {
        public var id: UUID
        /// `RuleScope` raw value.
        public var scopeRaw: String
        /// Normalised subject: a bundle identifier, a `scheme://host` origin, or a token.
        public var subject: String
        /// `RuleVerdict` raw value.
        public var verdictRaw: String
        public var createdAt: Date
        /// The priority this rule is scoped to, or `nil` for a global rule.
        public var task: PriorityTask?

        public init(
            id: UUID = UUID(),
            scopeRaw: String,
            subject: String,
            verdictRaw: String,
            createdAt: Date,
            task: PriorityTask? = nil
        ) {
            self.id = id
            self.scopeRaw = scopeRaw
            self.subject = subject
            self.verdictRaw = verdictRaw
            self.createdAt = createdAt
            self.task = task
        }
    }

    /// One application the app will not look at more closely than its bundle identifier.
    /// New in v3.
    ///
    /// This table is **data**, not code: the seeded list is conservative, every row is marked
    /// `isBuiltIn` so a reseed can tell its own entries from the user's, and every row is
    /// user-removable with the removal surviving a reseed.
    ///
    /// Nothing is ever inferred from what is on the screen. "Is this banking?" is answered by
    /// a bundle identifier being on a list, and by nothing else.
    ///
    /// `kindRaw` carries two lists in one table: `sensitive` (the auto-pause list) and
    /// `presentationExcluded` (F-35's user override, which seeds **empty**, because seeding it
    /// with guesses would be a claim about applications this programme has not measured).
    @Model
    public final class SensitiveAppEntry {
        public var id: UUID
        public var bundleID: String
        /// `sensitive` or `presentationExcluded`.
        public var kindRaw: String
        /// Whether the app seeded this row. A user's own entry is never reseeded away, and a
        /// built-in the user removed is never resurrected.
        public var isBuiltIn: Bool = false
        public var addedAt: Date

        public init(
            id: UUID = UUID(),
            bundleID: String,
            kindRaw: String,
            isBuiltIn: Bool = false,
            addedAt: Date
        ) {
            self.id = id
            self.bundleID = bundleID
            self.kindRaw = kindRaw
            self.isBuiltIn = isBuiltIn
            self.addedAt = addedAt
        }
    }

    /// The last observed state of one capability. New in v3.
    ///
    /// `educationShownAt` is the persisted half of F-127's never-re-prompt policy. e03 raises
    /// no prompt at all — every prompting API is banned from the shipping graph by lint — so
    /// in this epic the policy is structurally trivially true. The column is declared now
    /// anyway, so that the epic which does own an ask adds a behaviour and **not** a
    /// migration.
    @Model
    public final class CapabilityRecord {
        public var id: UUID
        /// `Capability` raw value.
        public var capabilityRaw: String
        /// `CapabilityState` raw value.
        public var stateRaw: String
        public var observedAt: Date
        /// When the app last explained a denial to the user. Written once, never re-armed.
        public var educationShownAt: Date?

        public init(
            id: UUID = UUID(),
            capabilityRaw: String,
            stateRaw: String,
            observedAt: Date,
            educationShownAt: Date? = nil
        ) {
            self.id = id
            self.capabilityRaw = capabilityRaw
            self.stateRaw = stateRaw
            self.observedAt = observedAt
            self.educationShownAt = educationShownAt
        }
    }

    /// The app's own persisted settings — a single row.
    ///
    /// Every non-optional addition carries a **property default**. That is not a style
    /// choice: probe P-51 measured that a new non-optional attribute with a default migrates
    /// under a lightweight rule, and one without a default does not.
    @Model
    public final class AppSettingsRecord {
        public var id: UUID
        /// `AppearancePreference` raw value.
        public var appearancePreferenceRaw: String
        /// When the schema last wrote this row.
        public var schemaTouchedAt: Date
        /// The `LocalDay` key the daily ritual last ran on, or `nil` if it never has.
        /// A local day, keyed through an injected calendar — never a UTC day.
        public var lastRitualLocalDay: String?
        /// Whether the daily ritual banner is offered at all.
        public var ritualEnabled: Bool = true
        /// The quick-capture hot key's virtual key code. 49 is Space.
        public var hotKeyKeyCode: Int = FocusSchemaV3.defaultHotKeyKeyCode
        /// The quick-capture hot key's modifiers, as `NSEvent.ModifierFlags` raw values.
        public var hotKeyModifierFlags: Int = FocusSchemaV3.defaultHotKeyModifierFlags
        /// F-119's one global pause switch, bound to every surface that shows it. A pause is
        /// not a boolean handlers consult — it detaches every observer — but the *state* it
        /// detaches from is this single stored value.
        public var sensingPaused: Bool = false
        /// Seconds of no hardware input above which the user is treated as away (R-36).
        public var idleThresholdSeconds: Int = FocusSchemaV3.defaultIdleThresholdSeconds
        /// How often the corroboration tick re-evaluates the signals that have no reliable
        /// notification (R-38).
        public var corroborationTickSeconds: Int = FocusSchemaV3.defaultCorroborationTickSeconds
        /// F-169's launcher: **off by default**, and open-only when on.
        public var launchContextOnSessionStart: Bool = false
        /// Whether a running microphone suppresses an intervention.
        public var mediaSuppressionEnabled: Bool = true

        public init(
            id: UUID = UUID(),
            appearancePreferenceRaw: String,
            schemaTouchedAt: Date,
            lastRitualLocalDay: String? = nil,
            ritualEnabled: Bool = true,
            hotKeyKeyCode: Int = FocusSchemaV3.defaultHotKeyKeyCode,
            hotKeyModifierFlags: Int = FocusSchemaV3.defaultHotKeyModifierFlags,
            sensingPaused: Bool = false,
            idleThresholdSeconds: Int = FocusSchemaV3.defaultIdleThresholdSeconds,
            corroborationTickSeconds: Int = FocusSchemaV3.defaultCorroborationTickSeconds,
            launchContextOnSessionStart: Bool = false,
            mediaSuppressionEnabled: Bool = true
        ) {
            self.id = id
            self.appearancePreferenceRaw = appearancePreferenceRaw
            self.schemaTouchedAt = schemaTouchedAt
            self.lastRitualLocalDay = lastRitualLocalDay
            self.ritualEnabled = ritualEnabled
            self.hotKeyKeyCode = hotKeyKeyCode
            self.hotKeyModifierFlags = hotKeyModifierFlags
            self.sensingPaused = sensingPaused
            self.idleThresholdSeconds = idleThresholdSeconds
            self.corroborationTickSeconds = corroborationTickSeconds
            self.launchContextOnSessionStart = launchContextOnSessionStart
            self.mediaSuppressionEnabled = mediaSuppressionEnabled
        }
    }
}

extension FocusSchemaV3.FocusSessionRecord {
    /// The stored phase, decoded through the one sanctioned decoder.
    ///
    /// `SessionPhase.decode(_:)` is an exhaustive switch over string literals that carries the
    /// v1/v2 aliases (`running` → `focus`, `ended` → `complete`) and answers `.complete` for
    /// anything else — a session this build cannot interpret is over as far as it is
    /// concerned. `SessionPhase(rawValue:)` is banned outright by `check-forbidden.sh`, with
    /// no allowlist and no exempted call site, which is possible only because the sanctioned
    /// decoder does not use one either.
    public var phase: SessionPhase {
        get { SessionPhase.decode(phaseRaw) }
        set { phaseRaw = newValue.rawValue }
    }

    /// The phase a resume returns to, decoded. `nil` means "resume to `.focus`", which is
    /// what the machine does with an absent `resumeTo`.
    public var resumeTo: ResumablePhase? {
        get { ResumablePhase.decode(resumeToRaw) }
        set { resumeToRaw = newValue?.rawValue }
    }

    /// The causes this session is paused for, decoded from the sorted comma-joined column.
    /// Empty for every non-paused phase, which is the persisted half of the invariant.
    public var pauseCauses: Set<PauseReason> {
        get { SessionState.decodePauseCauses(pauseCausesRaw) }
        set {
            pauseCausesRaw = newValue.isEmpty
                ? nil
                : newValue.sorted().map(\.rawValue).joined(separator: ",")
        }
    }
}

extension FocusSchemaV3.AppSettingsRecord {
    /// The stored preference, decoded. Falls back to `matchSystem` if the stored string is
    /// not a value this build knows — a forward-compatible read, never a crash.
    public var appearancePreference: AppearancePreference {
        get { AppearancePreference(rawValue: appearancePreferenceRaw) ?? .matchSystem }
        set { appearancePreferenceRaw = newValue.rawValue }
    }
}
