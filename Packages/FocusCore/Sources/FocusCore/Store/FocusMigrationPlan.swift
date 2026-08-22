import Foundation
import SwiftData

/// The store's migration plan, declared **now**, with one schema and no stages.
///
/// This is the whole of F-139's insurance policy and the reason it is written before there
/// is anything to migrate. Every container in this programme is built through
/// `ModelContainer(for:migrationPlan:configurations:)`; the plan-less initialiser is
/// forbidden and `scripts/check-forbidden.sh` fails the gate on it. So when e02 changes the
/// shape of `PriorityTask`, the change is *adding a stage to an existing plan* — a
/// mechanism that is already exercised by every test in the suite — rather than retrofitting
/// migration onto a store that never had any, which is where data loss actually comes from.
///
/// Adding v2 means: declare `FocusSchemaV2`, append it to `schemas`, and append a
/// `MigrationStage` describing the change. The committed v1 store fixture in
/// `FocusCoreTests/Resources/SchemaV1` is what turns "no data loss on upgrade" from an
/// intention into a fact.
public enum FocusMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] {
        [FocusSchemaV1.self]
    }

    public static var stages: [MigrationStage] {
        []
    }
}
