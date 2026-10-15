import Foundation
import SwiftData
import Testing
@testable import FocusCore

/// **Schema 12: the standing priorities' rows** (focus-standing).
@Suite("Schema v12 migration")
@MainActor
struct MigrationV12Tests {
    @Test("the plan's newest schema is v12, and it is the eleventh stage")
    func planShape() {
        #expect(FocusSchemaV12.versionIdentifier == Schema.Version(12, 0, 0))
        #expect(FocusMigrationPlan.schemas.count == 12)
        #expect(FocusMigrationPlan.schemas[11] is FocusSchemaV12.Type)
        #expect(FocusMigrationPlan.stages.count == 11)
        #expect(FocusStore.schema.version == Schema.Version(12, 0, 0))
    }

    @Test("v12 adds exactly one entity and re-declares none")
    func versionTwelveIsStrictlyAdditive() {
        #expect(FocusSchemaV12.models.count == FocusSchemaV11.models.count + 1)
        for prior in FocusSchemaV11.models {
            #expect(
                FocusSchemaV12.models.contains { $0 == prior },
                "v12 re-declared \(String(describing: prior))"
            )
        }
        let before = Schema(versionedSchema: FocusSchemaV11.self)
        let after = Schema(versionedSchema: FocusSchemaV12.self)
        let beforeNames = Set(before.entities.map(\.name))
        let afterNames = Set(after.entities.map(\.name))
        #expect(afterNames.subtracting(beforeNames) == ["StandingPriorityRecord"])
        #expect(beforeNames.subtracting(afterNames).isEmpty, "v12 removed an entity")
        for name in beforeNames {
            let beforeProperties = Set(before.entities.first { $0.name == name }?.properties.map(\.name) ?? [])
            let afterProperties = Set(after.entities.first { $0.name == name }?.properties.map(\.name) ?? [])
            #expect(!beforeProperties.isEmpty, "the v11 entity \(name) was not found")
            #expect(beforeProperties == afterProperties, "v12 changed the columns of \(name)")
        }
    }
}
