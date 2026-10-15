import Foundation
import SwiftData

/// **Everything the app holds about a person, in one file they can take away** (F-110, focus-ix9).
///
/// ## What this is, and what the registry beside it is
///
/// `Config/export-field-classification.txt` classifies every column this store keeps, and
/// `scripts/check-export-fields.sh` fails the build on a column nobody classified. That registry
/// landed *before* any exporter existed, so that the first one would arrive into an enforcing
/// gate — and it is deliberately independent of this file. **The two have to be able to
/// disagree, and the disagreement has to be what fails.** So nothing here reads the registry:
/// this type declares its own field list, `StoreExportFieldsTests` reads both, and a column this
/// exporter emits that the registry calls `EXCLUDED` is a red test rather than a silent leak.
///
/// ## What is in it
///
/// The person's own data: the commitments they wrote, what they attached to them, the rules they
/// taught the app, the sessions they ran, what the app observed while they ran, what the app said
/// about it and every question it asked them. **Not their settings** — those are a separate
/// document with its own version stamp (`SettingsDocument`), because a settings file is something
/// you carry to another Mac and a data file is something you keep.
///
/// ## What is never in it, and why the list is short
///
/// Four columns, and every one of them is a fact about *this Mac* rather than about the person:
/// `ContextItem.bookmark` (a security-scoped handle — a capability, not data),
/// `FocusSessionRecord.bootIdentity` and `uptimeAnchorSeconds` (a machine fingerprint), and
/// `ActivityEvent.displayID` (a CoreGraphics display number). Relationships are absent because
/// the identifier on the other side is the fact.
///
/// The list is short because the store cannot hold the things an export usually has to strip. A
/// window title, a URL beyond a normalised origin, a document name, a file path the app observed
/// — none of them has a column to sit in (R-41, standing conditions 1 and 3). The poison test
/// asserts that rather than assuming it: it writes a title-shaped sentinel into **every `String`
/// column of every entity**, through the raw `@Model` classes and past every facade, and requires
/// that no excluded column's sentinel appears in any byte of the output.
///
/// ## Determinism
///
/// Sorted keys, ISO-8601 instants, oldest first, matching `ActivityEventStore.exportJSON`'s
/// existing contract — so two exports of an unchanged store are byte-identical apart from the
/// manifest's `generatedAt`, and a diff of two exports shows what changed rather than how the
/// encoder felt.
public enum StoreExport {
    /// The document format's own version. Bumped when a field is added, removed or re-meant.
    public static let formatVersion = 1
    public static let formatName = "focus-sentinel.data"

    /// **What the file says it contains, in the file.**
    ///
    /// A scope you have to guess at is not ownership. The field list is emitted rather than
    /// documented elsewhere, so the file explains itself on any machine and a diff of two
    /// exports shows a schema change as a change in the manifest.
    public struct Manifest: Codable, Sendable, Equatable {
        public let format: String
        public let version: Int
        public let generatedAt: Date
        public let schemaVersion: Int
        public let fields: [String: [String]]
    }

    public struct Document: Codable, Sendable, Equatable {
        public let manifest: Manifest
        public let priorities: [Priority]
        public let contextItems: [ContextItem]
        public let rules: [Rule]
        public let sessions: [Session]
        public let sessionTransitions: [SessionTransition]
        public let activityEvents: [ActivityEvent]
        public let interventions: [Intervention]
        public let questions: [Question]
    }

    // MARK: - The rows
    //
    // One `Codable` struct per entity, whose property names ARE the exported field names. There
    // is no member of a type that could hold captured content on any of them, which is the same
    // argument `ActivityEventStore.ExportedEvent` makes and for the same reason.

    public struct Priority: Codable, Sendable, Equatable {
        public let id: String
        public let intent: String
        public let doneWhen: String?
        public let createdAt: Date
        public let completedAt: Date?
        public let revision: Int
        public let timeboxSeconds: Int?
        public let startedAt: Date?
        public let shipped: String?
        public let restartPoint: String?
        public let lastActivatedAt: Date?
    }

    public struct ContextItem: Codable, Sendable, Equatable {
        public let id: String
        public let priorityID: String?
        public let kindRaw: String
        public let value: String
        public let displayName: String
        public let addedAt: Date
    }

    public struct Rule: Codable, Sendable, Equatable {
        public let id: String
        public let priorityID: String?
        public let scopeRaw: String
        public let subject: String
        public let verdictRaw: String
        public let createdAt: Date
    }

    public struct Session: Codable, Sendable, Equatable {
        public let id: String
        public let taskID: String?
        public let startedAt: Date
        public let endedAt: Date?
        public let phaseRaw: String
        public let phaseChangedAt: Date?
        public let resumeToRaw: String?
        public let kindRaw: String
        public let plannedSeconds: Int?
        public let deadlineAt: Date?
        public let pauseCausesRaw: String?
        public let interruptionReasonRaw: String?
        public let restartPointNote: String?
        public let lastActiveBundleID: String?
    }

    public struct SessionTransition: Codable, Sendable, Equatable {
        public let id: String
        public let sessionID: String?
        public let at: Date
        public let fromRaw: String
        public let toRaw: String
        public let eventRaw: String
        public let reasonRaw: String?
        public let outcomeRaw: String
    }

    /// The observation rows, re-projected here rather than through
    /// `ActivityEventStore.exported(_:)`.
    ///
    /// That function is the **live evidence lane's** export and it emits `displayID`, which this
    /// registry classifies `EXCLUDED`: a CoreGraphics display number is a fact about this Mac's
    /// hardware arrangement. A file a person takes to another machine must not carry it, and a
    /// debug dump a developer reads on the machine that produced it may. Two consumers, two
    /// projections, and the difference is stated here rather than discovered later.
    ///
    /// The detail column is re-derived through `NormalisedDetail.inspect`, exactly as the debug
    /// export does: a stored value this build cannot interpret contributes **nothing**, not the
    /// raw string and not a placeholder.
    public struct ActivityEvent: Codable, Sendable, Equatable {
        public let id: String
        public let at: Date
        public let kindRaw: String?
        public let bundleID: String?
        public let tokens: [String]?
        public let measurement: String?
        public let measurementValue: Int?
        public let sessionID: String?
        public let dwellSeconds: Double?
    }

    public struct Intervention: Codable, Sendable, Equatable {
        public let id: String
        public let at: Date
        public let localDayKey: String
        public let kindRaw: String
        public let rungRaw: String?
        public let subject: String
        public let subjectKindRaw: String
        public let priorityID: String?
        public let surfaceRaw: String
        public let dispositionRaw: String
        public let outcomeRaw: String?
        public let originatingAnswerRaw: String?
        public let explanationKindsRaw: String?
    }

    public struct Question: Codable, Sendable, Equatable {
        public let id: String
        public let priorityID: String
        public let subjectKindRaw: String
        public let subject: String
        public let reasonRaw: String
        public let askedAt: Date
        public let outcomeRaw: String
        public let answeredAt: Date?
    }

    /// **The exporter's own field list**, entity by entity, as the manifest publishes it.
    ///
    /// Written out rather than derived from the `Codable` types by reflection, because reflection
    /// over a struct with no instance is not available and an empty-instance fold would need a
    /// second set of literals anyway. `StoreExportFieldsTests` folds it against the classification
    /// registry in both directions, which is the check that matters: every name here is a column
    /// the registry does not exclude, and every column the registry does not exclude is either
    /// here or named in the test's own stated-omission list.
    public static let fields: [String: [String]] = [
        "priorities": [
            "completedAt", "createdAt", "doneWhen", "id", "intent", "lastActivatedAt",
            "restartPoint", "revision", "shipped", "startedAt", "timeboxSeconds"
        ],
        "contextItems": ["addedAt", "displayName", "id", "kindRaw", "priorityID", "value"],
        "rules": ["createdAt", "id", "priorityID", "scopeRaw", "subject", "verdictRaw"],
        "sessions": [
            "deadlineAt", "endedAt", "id", "interruptionReasonRaw", "kindRaw",
            "lastActiveBundleID", "pauseCausesRaw", "phaseChangedAt", "phaseRaw",
            "plannedSeconds", "restartPointNote", "resumeToRaw", "startedAt", "taskID"
        ],
        "sessionTransitions": [
            "at", "eventRaw", "fromRaw", "id", "outcomeRaw", "reasonRaw", "sessionID", "toRaw"
        ],
        "activityEvents": [
            "at", "bundleID", "dwellSeconds", "id", "kindRaw", "measurement", "measurementValue",
            "sessionID", "tokens"
        ],
        "interventions": [
            "at", "dispositionRaw", "explanationKindsRaw", "id", "kindRaw", "localDayKey",
            "originatingAnswerRaw", "outcomeRaw", "priorityID", "rungRaw", "subject",
            "subjectKindRaw", "surfaceRaw"
        ],
        "questions": [
            "answeredAt", "askedAt", "id", "outcomeRaw", "priorityID", "reasonRaw", "subject",
            "subjectKindRaw"
        ]
    ]

    /// The whole document, built from one context.
    @MainActor
    public static func document(in context: ModelContext, generatedAt: Date) throws -> Document {
        func fetch<T: PersistentModel>(
            _ type: T.Type,
            sortedBy sort: [SortDescriptor<T>]
        ) throws -> [T] {
            try context.countedFetch(FetchDescriptor<T>(sortBy: sort))
        }

        let priorities = try fetch(
            FocusSchemaV3.PriorityTask.self,
            sortedBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        let contextItems = try fetch(
            FocusSchemaV3.ContextItem.self,
            sortedBy: [SortDescriptor(\.addedAt, order: .forward)]
        )
        let rules = try fetch(
            FocusSchemaV3.RelevanceRule.self,
            sortedBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        let sessions = try fetch(
            FocusSchemaV3.FocusSessionRecord.self,
            sortedBy: [SortDescriptor(\.startedAt, order: .forward)]
        )
        let transitions = try fetch(
            FocusSchemaV3.SessionTransitionRecord.self,
            sortedBy: [SortDescriptor(\.at, order: .forward)]
        )
        let events = try fetch(
            FocusSchemaV3.ActivityEvent.self,
            sortedBy: [SortDescriptor(\.at, order: .forward)]
        )
        let interventions = try fetch(
            FocusSchemaV7.InterventionRecord.self,
            sortedBy: [SortDescriptor(\.at, order: .forward)]
        )
        let questions = try fetch(
            FocusSchemaV4.AskedQuestion.self,
            sortedBy: [SortDescriptor(\.askedAt, order: .forward)]
        )

        return Document(
            manifest: Manifest(
                format: formatName,
                version: formatVersion,
                generatedAt: generatedAt,
                schemaVersion: FocusStore.schema.version.major,
                fields: fields
            ),
            priorities: priorities.map {
                Priority(
                    id: $0.id.uuidString,
                    intent: $0.intent,
                    doneWhen: $0.doneWhen,
                    createdAt: $0.createdAt,
                    completedAt: $0.completedAt,
                    revision: $0.revision,
                    timeboxSeconds: $0.timeboxSeconds,
                    startedAt: $0.startedAt,
                    shipped: $0.shipped,
                    restartPoint: $0.restartPoint,
                    lastActivatedAt: $0.lastActivatedAt
                )
            },
            contextItems: contextItems.map {
                ContextItem(
                    id: $0.id.uuidString,
                    priorityID: $0.task?.id.uuidString,
                    kindRaw: $0.kindRaw,
                    value: $0.value,
                    displayName: $0.displayName,
                    addedAt: $0.addedAt
                )
            },
            rules: rules.map {
                Rule(
                    id: $0.id.uuidString,
                    priorityID: $0.task?.id.uuidString,
                    scopeRaw: $0.scopeRaw,
                    subject: SelectedItem.exportedSubject($0.subject),
                    verdictRaw: $0.verdictRaw,
                    createdAt: $0.createdAt
                )
            },
            sessions: sessions.map {
                Session(
                    id: $0.id.uuidString,
                    taskID: $0.taskID?.uuidString,
                    startedAt: $0.startedAt,
                    endedAt: $0.endedAt,
                    phaseRaw: $0.phaseRaw,
                    phaseChangedAt: $0.phaseChangedAt,
                    resumeToRaw: $0.resumeToRaw,
                    kindRaw: $0.kindRaw,
                    plannedSeconds: $0.plannedSeconds,
                    deadlineAt: $0.deadlineAt,
                    pauseCausesRaw: $0.pauseCausesRaw,
                    interruptionReasonRaw: $0.interruptionReasonRaw,
                    restartPointNote: $0.restartPointNote,
                    lastActiveBundleID: $0.lastActiveBundleID
                )
            },
            sessionTransitions: transitions.map {
                SessionTransition(
                    id: $0.id.uuidString,
                    sessionID: $0.session?.id.uuidString,
                    at: $0.at,
                    fromRaw: $0.fromRaw,
                    toRaw: $0.toRaw,
                    eventRaw: $0.eventRaw,
                    reasonRaw: $0.reasonRaw,
                    outcomeRaw: $0.outcomeRaw
                )
            },
            activityEvents: events.map { event in
                var tokens: [String]?
                var measurement: String?
                var measurementValue: Int?
                switch NormalisedDetail.inspect(event.detail) {
                case .none, .unreadable:
                    break
                case .tokens(let found):
                    tokens = found.map(\.rawValue)
                case .measurement(let kind, let value):
                    measurement = kind.rawValue
                    measurementValue = value
                }
                return ActivityEvent(
                    id: event.id.uuidString,
                    at: event.at,
                    kindRaw: ActivityEventKind.decode(event.kindRaw)?.rawValue,
                    bundleID: event.bundleID,
                    tokens: tokens,
                    measurement: measurement,
                    measurementValue: measurementValue,
                    sessionID: event.sessionID?.uuidString,
                    dwellSeconds: event.dwellSeconds
                )
            },
            interventions: interventions.map {
                Intervention(
                    id: $0.id.uuidString,
                    at: $0.at,
                    localDayKey: $0.localDayKey,
                    kindRaw: $0.kindRaw,
                    rungRaw: $0.rungRaw,
                    subject: SelectedItem.exportedSubject($0.subject),
                    subjectKindRaw: $0.subjectKindRaw,
                    priorityID: $0.priorityID?.uuidString,
                    surfaceRaw: $0.surfaceRaw,
                    dispositionRaw: $0.dispositionRaw,
                    outcomeRaw: $0.outcomeRaw,
                    originatingAnswerRaw: $0.originatingAnswerRaw,
                    explanationKindsRaw: $0.explanationKindsRaw
                )
            },
            questions: questions.map {
                Question(
                    id: $0.id.uuidString,
                    priorityID: $0.priorityID.uuidString,
                    subjectKindRaw: $0.subjectKindRaw,
                    subject: SelectedItem.exportedSubject($0.subject),
                    reasonRaw: $0.reasonRaw,
                    askedAt: $0.askedAt,
                    outcomeRaw: $0.outcomeRaw,
                    answeredAt: $0.answeredAt
                )
            }
        )
    }

    /// The document as bytes. One encoder, stated here, so determinism is a property of this
    /// function rather than of each caller.
    @MainActor
    public static func json(in context: ModelContext, generatedAt: Date) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(document(in: context, generatedAt: generatedAt))
    }
}
