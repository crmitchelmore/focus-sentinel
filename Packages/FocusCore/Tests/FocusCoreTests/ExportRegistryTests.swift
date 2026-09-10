import Foundation
import Testing

@testable import FocusCore

/// **The exporter and the classification registry, folded against each other** (F-110, focus-ix9).
///
/// `Config/export-field-classification.txt` classifies every column the store keeps, and
/// `scripts/check-export-fields.sh` fails the build on a column nobody classified. That registry
/// is deliberately **independent** of the exporter — a lint that read the exporter's own field
/// list to decide what to require would be the exporter marking its own homework. This is where
/// the two are made to agree, and where a disagreement is what fails.
///
/// It reads the committed file rather than a copy, for the reason the migration fixtures open the
/// committed store: a copy is a second source of truth, and the whole point of the registry is
/// that there is one.
@Suite("Export registry")
struct ExportRegistryTests {
    /// One classified column.
    struct Row: Hashable {
        let entity: String
        let column: String
        let classification: String
    }

    /// The registry, parsed. Located from `#filePath` because the repository root is where it
    /// lives and no bundle carries it.
    static let rows: [Row] = {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // FocusCoreTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // FocusCore
            .deletingLastPathComponent()  // Packages
            .deletingLastPathComponent()  // <repo root>
            .appending(path: "Config/export-field-classification.txt", directoryHint: .notDirectory)
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return text.split(separator: "\n").compactMap { line in
            guard !line.hasPrefix("#") else { return nil }
            let parts = line.split(separator: "|", maxSplits: 3).map {
                $0.trimmingCharacters(in: .whitespaces)
            }
            guard parts.count == 4 else { return nil }
            return Row(entity: parts[0], column: parts[1], classification: parts[2])
        }
    }()

    /// The exporter names its rows after the collection they appear in; the registry names them
    /// after the entity. One table, written once, and both sides are asserted against it.
    static let entityForCollection: [String: String] = [
        "priorities": "PriorityTask",
        "contextItems": "ContextItem",
        "rules": "RelevanceRule",
        "sessions": "FocusSessionRecord",
        "sessionTransitions": "SessionTransitionRecord",
        "activityEvents": "ActivityEvent",
        "interventions": "InterventionRecord",
        "questions": "AskedQuestion"
    ]

    /// **Fields the exporter emits that are not the column of their own entity**, with the
    /// column each one actually is.
    ///
    /// Keyed by `<collection>.<field>` rather than by field name, because the same name is a real
    /// column on one entity and a derivation on another: `InterventionRecord.priorityID` is a
    /// column, and a context item's `priorityID` is `PriorityTask.id` reached through the
    /// relationship the registry excludes — *"a relationship; the priority's identifier is the
    /// fact"*, which is this, written as code.
    ///
    /// Written down rather than special-cased silently, so a field invented later has nowhere to
    /// hide.
    static let derived: [String: String] = [
        "contextItems.priorityID": "PriorityTask.id",
        "rules.priorityID": "PriorityTask.id",
        "sessionTransitions.sessionID": "FocusSessionRecord.id",
        // The activity detail is **re-derived**, never copied: a stored value this build cannot
        // interpret contributes nothing at all.
        "activityEvents.tokens": "ActivityEvent.detail",
        "activityEvents.measurement": "ActivityEvent.detail",
        "activityEvents.measurementValue": "ActivityEvent.detail"
    ]

    /// The column one promised field rides, entity-qualified.
    static func column(of field: String, in collection: String) -> String {
        if let derived = derived["\(collection).\(field)"] { return derived }
        let entity = entityForCollection[collection] ?? collection
        return "\(entity).\(field)"
    }

    /// **Columns the registry allows and this exporter does not emit**, with the reason.
    ///
    /// A stated omission list, not a suppression: each row here is a claim somebody made, and the
    /// tests below fail both when a column is omitted without one and when an omission stops
    /// describing the code.
    static let statedOmissions: Set<Row> = [
        // Which priority is active *right now* is a fact about this moment on this Mac, not
        // history; `PriorityTask.lastActivatedAt` is the exportable form of the same thing.
        Row(entity: "ActivePriority", column: "activatedAt", classification: "MEASURE"),
        // Permission state: what *this* Mac can do, read from this Mac. It is not the person's
        // data and it means nothing anywhere else.
        Row(entity: "CapabilityRecord", column: "id", classification: "KEY"),
        Row(entity: "CapabilityRecord", column: "capabilityRaw", classification: "TOKEN"),
        Row(entity: "CapabilityRecord", column: "stateRaw", classification: "TOKEN"),
        Row(entity: "CapabilityRecord", column: "observedAt", classification: "MEASURE"),
        Row(entity: "CapabilityRecord", column: "educationShownAt", classification: "MEASURE"),
        // The exclusion lists travel in the *settings* document, which is the file you carry to
        // another Mac. They are a preference, not a record of a day.
        Row(entity: "SensitiveAppEntry", column: "id", classification: "KEY"),
        Row(entity: "SensitiveAppEntry", column: "bundleID", classification: "KEY"),
        Row(entity: "SensitiveAppEntry", column: "kindRaw", classification: "TOKEN"),
        Row(entity: "SensitiveAppEntry", column: "isBuiltIn", classification: "MEASURE"),
        Row(entity: "SensitiveAppEntry", column: "addedAt", classification: "MEASURE")
    ]

    /// Settings rows, which belong to `SettingsDocument` rather than to the data export. Named by
    /// entity because every column of each is in the same position.
    static let settingsEntities: Set<String> = [
        "AppSettingsRecord", "NudgePreferencesRecord", "PrivacyPreferencesRecord",
        "ShellStateRecord",
        // focus-exdi: the dials a person turned, and the grants they switched on. Settings, and
        // they ride out through the settings document rather than the data export.
        "PolicyTuningRecord", "GrantOptInRecord"
    ]

    /// Every column the exporter reaches, entity-qualified.
    static func exportedColumns() -> Set<String> {
        var exported = Set<String>()
        for (collection, fields) in StoreExport.fields {
            for field in fields { exported.insert(column(of: field, in: collection)) }
        }
        return exported
    }

    @Test("the registry is readable, and is not empty")
    func theRegistryParses() {
        #expect(Self.rows.count >= 100, "the registry parsed \(Self.rows.count) rows")
        #expect(Self.rows.contains { $0.classification == "EXCLUDED" })
        #expect(Self.rows.contains { $0.classification == "OWN" })
    }

    /// **Nothing the registry excludes is exported.** The static half of the poison test: the
    /// bytes are checked in `StoreExportTests`, and this checks the promise the manifest makes.
    @Test("no field the exporter promises is an excluded column")
    func noPromisedFieldIsExcluded() {
        let excluded = Set(
            Self.rows.filter { $0.classification == "EXCLUDED" }
                .map { "\($0.entity).\($0.column)" }
        )
        for (collection, fields) in StoreExport.fields {
            for field in fields {
                let column = Self.column(of: field, in: collection)
                #expect(
                    !excluded.contains(column),
                    "\(collection).\(field) rides \(column), which the registry excludes"
                )
            }
        }
    }

    /// **And every field the exporter promises is a column that exists.** The direction that
    /// catches a manifest naming something the schema has never had.
    @Test("every promised field names a classified column")
    func everyPromisedFieldIsAKnownColumn() {
        let known = Set(Self.rows.map { "\($0.entity).\($0.column)" })
        for (collection, fields) in StoreExport.fields {
            #expect(Self.entityForCollection[collection] != nil, "\(collection) names no entity")
            for field in fields {
                let column = Self.column(of: field, in: collection)
                #expect(
                    known.contains(column),
                    "\(collection).\(field) names \(column), which the registry has not"
                )
            }
        }
    }

    /// **The omission direction**, and the one that goes stale: a column the registry says may be
    /// exported, that this exporter drops without saying so, is a promise quietly narrowed.
    @Test("every exportable column is exported or has a stated reason not to be")
    func everyExportableColumnIsAccountedFor() {
        let exported = Self.exportedColumns()

        for row in Self.rows where row.classification != "EXCLUDED" {
            guard !Self.settingsEntities.contains(row.entity) else { continue }
            let name = "\(row.entity).\(row.column)"
            guard !exported.contains(name) else { continue }
            #expect(
                Self.statedOmissions.contains(row),
                "\(name) is exportable, is not exported, and has no stated reason"
            )
        }
    }

    /// A stated omission that is no longer true — the column exported after all, or gone from the
    /// schema — is a comment that has stopped describing the code.
    @Test("every stated omission is still a real, unexported column")
    func noStatedOmissionIsStale() {
        let exported = Self.exportedColumns()
        for omission in Self.statedOmissions {
            #expect(
                Self.rows.contains(omission),
                "\(omission.entity).\(omission.column) is omitted from a registry it is not in"
            )
            #expect(
                !exported.contains("\(omission.entity).\(omission.column)"),
                "\(omission.entity).\(omission.column) is exported and still called an omission"
            )
        }
    }
}
