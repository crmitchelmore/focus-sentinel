import Foundation
import SwiftData

/// The store's migration plan: v1 → v2 through one **custom** stage, then v2 → v3 through a
/// **lightweight** one.
///
/// This is the whole of F-139's insurance policy, and it was declared in e01 with no stages
/// precisely so that this change would be *adding a stage to an existing plan* rather than
/// retrofitting migration onto a store that never had any — which is where data loss
/// actually comes from. Every container in this programme is built through
/// `ModelContainer(for:migrationPlan:configurations:)`; the plan-less initialiser is
/// forbidden and `scripts/check-forbidden.sh` fails the gate on it.
///
/// ## Why the stage is custom rather than lightweight
///
/// v1 recorded the active priority in a `PriorityTask.isActive` boolean. v2 records it as the
/// unique-slot `ActivePriority` pointer row and **removes the column** (R-16, R-18). A
/// *lightweight* stage would migrate perfectly happily and silently drop the user's active
/// priority on the floor: the column disappears, no pointer row is created, and the app opens
/// with nothing selected. Probe P-52 measured the custom stage carrying it across instead —
/// `willMigrate` reads the v1 flag, `didMigrate` creates the v2 pointer — and measured that
/// reopening an already-migrated store does not re-run it.
///
/// ## When more than one v1 row claims to be active
///
/// v1 enforced "exactly one active task" in code, not in the store, so a v1 file *can* hold
/// two. The stage takes the **most recently created** such row and leaves the rest as
/// ordinary history. That is a decision, recorded here so it cannot later be mistaken for an
/// accident.
///
/// ## Why v2 → v3 is lightweight, and how that is kept true
///
/// e03 adds a great deal to the store — the session runtime, a transition log, the capability
/// table, the sensitive-app list — but it **removes nothing and renames nothing**, and every
/// new attribute is either optional or carries a property default. e02's probe P-51 measured
/// that to be exactly the condition SwiftData needs to migrate without a custom stage. A
/// lightweight stage with no closures is therefore not laziness; it is the shape the schema
/// was deliberately given so that the stage could carry no code and have nothing to get wrong.
///
/// The v1 fixture now migrates through **both** stages. That chain is what makes "no data
/// loss on upgrade" a fact rather than an intention, and it is asserted directly.
public enum FocusMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] {
        [FocusSchemaV1.self, FocusSchemaV2.self, FocusSchemaV3.self]
    }

    public static var stages: [MigrationStage] {
        [v1ToV2, v2ToV3]
    }

    /// v2 → v3: every addition is optional or defaulted, so nothing has to be carried by hand.
    static var v2ToV3: MigrationStage {
        MigrationStage.lightweight(
            fromVersion: FocusSchemaV2.self,
            toVersion: FocusSchemaV3.self
        )
    }

    /// State carried from `willMigrate` to `didMigrate`.
    ///
    /// A stage's two closures run against different contexts and cannot hand each other a
    /// model object, so the identifiers travel as plain values through a box the plan owns —
    /// mirroring e01's `NotificationTokens` pattern rather than reaching for a global `var`.
    /// The lock is what makes `@unchecked Sendable` an honest claim.
    final class MigrationCarry: @unchecked Sendable {
        private let lock = NSLock()
        private var storage: [UUID] = []

        /// The identifiers of the v1 tasks that carried `isActive == true`, most recently
        /// created first.
        var activeTaskIDs: [UUID] {
            get {
                lock.lock()
                defer { lock.unlock() }
                return storage
            }
            set {
                lock.lock()
                defer { lock.unlock() }
                storage = newValue
            }
        }
    }

    /// The one carry box, owned by the plan.
    static let carry = MigrationCarry()

    /// v1 → v2: everything else migrates lightweight; the active priority is carried by hand.
    static var v1ToV2: MigrationStage {
        MigrationStage.custom(
            fromVersion: FocusSchemaV1.self,
            toVersion: FocusSchemaV2.self,
            willMigrate: { context in
                // Fetched and filtered in Swift rather than through a predicate: the set is
                // tiny, and a migration is the worst possible place to discover that a
                // predicate compiled against a schema that is halfway through changing.
                let tasks = try context.fetch(FetchDescriptor<FocusSchemaV1.PriorityTask>())
                carry.activeTaskIDs = tasks
                    .filter(\.isActive)
                    .sorted { $0.createdAt > $1.createdAt }
                    .map(\.id)
            },
            didMigrate: { context in
                guard let identifier = carry.activeTaskIDs.first else { return }
                carry.activeTaskIDs = []

                let descriptor = FetchDescriptor<FocusSchemaV2.PriorityTask>(
                    predicate: #Predicate { $0.id == identifier }
                )
                guard let task = try context.fetch(descriptor).first else { return }

                // The pointer is inserted, once, against a task that owns none. That is the
                // only safe way to create it: inserting a second row whose target already has
                // one is a process fatal error in SwiftData (probe P-46).
                context.insert(
                    FocusSchemaV2.ActivePriority(task: task, activatedAt: task.createdAt)
                )
                try context.save()
            }
        )
    }
}
