import Foundation
import SwiftData

/// **Schema 11: whether the person switched update checks on** (focus-h8jf).
///
/// One row at most, and no row is the shipped state — so a store written by any earlier
/// version reads as "checks off", which is what the Privacy pane promised those builds and what
/// every existing install still gets after upgrading. A new entity and nothing re-declared, for
/// the reason v8, v9 and v10 gave: an earlier version is a migration source, and a source you
/// have edited is not a source.
///
/// It is its own row rather than a column on `AppSettingsRecord` for `GrantOptInRecord`'s
/// reason: it is a consent about this Mac, not a preference to carry in a settings export, and
/// `SettingsDocument` deliberately does not know it.
public enum FocusSchemaV11: VersionedSchema {
    public static var versionIdentifier: Schema.Version {
        Schema.Version(11, 0, 0)
    }

    public static var models: [any PersistentModel.Type] {
        FocusSchemaV10.models + [SoftwareUpdatePreferenceRecord.self]
    }

    /// The person's choice about automatic update checks. Present only once they have chosen.
    @Model
    public final class SoftwareUpdatePreferenceRecord {
        public var id: UUID
        public var checksAutomatically: Bool
        public var touchedAt: Date

        public init(id: UUID = UUID(), checksAutomatically: Bool, touchedAt: Date) {
            self.id = id
            self.checksAutomatically = checksAutomatically
            self.touchedAt = touchedAt
        }
    }
}
