import Foundation
import SwiftData

/// **Schema 12: the person's standing priorities** (focus-standing).
///
/// Up to three rows: slot 0 is the one main priority, slots 1 and 2 the two secondary ones. Each
/// names an existing `PriorityTask` by identifier, so picking one is the history's own
/// "work on this again" — the stored desk and rules come back by construction, not by copying.
///
/// **A shortlist, not a backlog.** F-15 refused a queue because a queue is a second commitment
/// competing with the first. Three named slots, replaced only as a whole and only through the
/// confirmation sheet, are the person's own answer to "what should most of my focus time start
/// on", kept where the cockpit can offer it. They never become the priority on their own.
///
/// A UUID column rather than a relationship, so v3's `PriorityTask` is not re-declared: an
/// earlier version is a migration source, and a source you have edited is not a source. A row
/// whose task has since been deleted is ignored by the reader rather than repaired.
public enum FocusSchemaV12: VersionedSchema {
    public static var versionIdentifier: Schema.Version {
        Schema.Version(12, 0, 0)
    }

    public static var models: [any PersistentModel.Type] {
        FocusSchemaV11.models + [StandingPriorityRecord.self]
    }

    /// One standing slot.
    @Model
    public final class StandingPriorityRecord {
        public var id: UUID
        /// 0 for the main priority, 1 and 2 for the secondary ones.
        public var slot: Int
        /// The `PriorityTask` this slot offers.
        public var taskID: UUID
        public var updatedAt: Date

        public init(id: UUID = UUID(), slot: Int, taskID: UUID, updatedAt: Date) {
            self.id = id
            self.slot = slot
            self.taskID = taskID
            self.updatedAt = updatedAt
        }
    }
}
