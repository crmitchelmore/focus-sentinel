import Foundation
import SwiftData

/// **Schema 10: the grants the person switched on** (focus-exdi.4).
///
/// One row per opted-in grant, and no row is the shipped state — so a store written by any
/// earlier version reads as "asks for nothing", which is what PD-1 promised and what every
/// existing install still gets. A new entity and nothing re-declared, for the reason v8 and v9
/// gave: an earlier version is a migration source, and a source you have edited is not a source.
public enum FocusSchemaV10: VersionedSchema {
    public static var versionIdentifier: Schema.Version {
        Schema.Version(10, 0, 0)
    }

    public static var models: [any PersistentModel.Type] {
        FocusSchemaV9.models + [GrantOptInRecord.self]
    }

    /// One grant the person switched on. `key` is `GrantOptIn.rawValue`; a key this build does
    /// not know is read as nothing and left where it is.
    @Model
    public final class GrantOptInRecord {
        public var id: UUID
        public var key: String
        public var touchedAt: Date

        public init(id: UUID = UUID(), key: String, touchedAt: Date) {
            self.id = id
            self.key = key
            self.touchedAt = touchedAt
        }
    }
}

extension FocusSchemaV10.GrantOptInRecord {
    public var grant: GrantOptIn? { GrantOptIn.decode(key) }
}
