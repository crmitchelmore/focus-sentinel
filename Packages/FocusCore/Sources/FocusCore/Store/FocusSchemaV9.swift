import Foundation
import SwiftData

/// **Schema 9: the policy tunings** (focus-exdi, owner ruling 2026-09-08).
///
/// One new entity and nothing re-declared, for the reason v8 gave: v1…v8 are migration sources,
/// and a source you have edited is not a source. A `PolicyTuningRecord` is one row per turned
/// dial — the tuning's key and the person's value — so a tuning nobody touched has no row and
/// reads as the shipped constant, and a new tuning needs no schema stage at all.
public enum FocusSchemaV9: VersionedSchema {
    public static var versionIdentifier: Schema.Version {
        Schema.Version(9, 0, 0)
    }

    public static var models: [any PersistentModel.Type] {
        FocusSchemaV8.models + [PolicyTuningRecord.self]
    }

    /// One turned dial. `key` is `PolicyTuning.rawValue`; a key the running app does not know
    /// (a tuning that was renamed or retired) is read as nothing and left where it is.
    @Model
    public final class PolicyTuningRecord {
        public var id: UUID
        public var key: String
        public var value: Double
        public var touchedAt: Date

        public init(id: UUID = UUID(), key: String, value: Double, touchedAt: Date) {
            self.id = id
            self.key = key
            self.value = value
            self.touchedAt = touchedAt
        }
    }
}

// MARK: - Typed accessors

extension FocusSchemaV9.PolicyTuningRecord {
    /// The tuning this row is about, or `nil` for a key the app no longer knows.
    public var tuning: PolicyTuning? {
        PolicyTuning.decode(key)
    }
}

extension PolicyTuning {
    /// Total: every stored key resolves to a tuning or to `nil`, never to a throw (R-45).
    public static func decode(_ raw: String) -> PolicyTuning? {
        allCases.first { $0.rawValue == raw }
    }
}
