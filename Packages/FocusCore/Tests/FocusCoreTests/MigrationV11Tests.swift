import Foundation
import SwiftData
import Testing
@testable import FocusCore

/// **Schema 11: the update-check preference's row** (focus-h8jf).
@Suite("Schema v11 migration")
@MainActor
struct MigrationV11Tests {
    static let timestamp = Date(timeIntervalSince1970: 1_767_225_600)

    @Test("the plan's newest schema is v11, and it is the tenth stage")
    func planShape() {
        #expect(FocusSchemaV11.versionIdentifier == Schema.Version(11, 0, 0))
        #expect(FocusMigrationPlan.schemas.count == 11)
        #expect(FocusMigrationPlan.schemas[10] is FocusSchemaV11.Type)
        #expect(FocusMigrationPlan.stages.count == 10)
        #expect(FocusStore.schema.version == Schema.Version(11, 0, 0))
    }

    @Test("v11 adds exactly one entity and re-declares none")
    func versionElevenIsStrictlyAdditive() {
        #expect(FocusSchemaV11.models.count == FocusSchemaV10.models.count + 1)
        for prior in FocusSchemaV10.models {
            #expect(
                FocusSchemaV11.models.contains { $0 == prior },
                "v11 re-declared \(String(describing: prior))"
            )
        }
        let before = Schema(versionedSchema: FocusSchemaV10.self)
        let after = Schema(versionedSchema: FocusSchemaV11.self)
        let beforeNames = Set(before.entities.map(\.name))
        let afterNames = Set(after.entities.map(\.name))
        #expect(afterNames.subtracting(beforeNames) == ["SoftwareUpdatePreferenceRecord"])
        #expect(beforeNames.subtracting(afterNames).isEmpty, "v11 removed an entity")
        for name in beforeNames {
            let beforeProperties = Set(before.entities.first { $0.name == name }?.properties.map(\.name) ?? [])
            let afterProperties = Set(after.entities.first { $0.name == name }?.properties.map(\.name) ?? [])
            #expect(!beforeProperties.isEmpty, "the v10 entity \(name) was not found")
            #expect(beforeProperties == afterProperties, "v11 changed the columns of \(name)")
        }
    }

    /// **A fresh store checks for nothing**, which is the promise every earlier build made and
    /// the state a migrated store arrives in: no row.
    @Test("a fresh store has checks off, a choice is one row, and off keeps the row")
    func preferenceIsARow() throws {
        let container = try FocusStore.makeContainer(kind: .inMemory)
        let context = container.mainContext
        #expect(!FocusStore.softwareUpdateChecksEnabled(in: context))
        #expect(FocusStore.softwareUpdatePreferenceRows(in: context).isEmpty)

        try FocusStore.setSoftwareUpdateChecksEnabled(true, in: context, now: Self.timestamp)
        #expect(FocusStore.softwareUpdateChecksEnabled(in: context))
        #expect(FocusStore.softwareUpdatePreferenceRows(in: context).count == 1)

        // Choosing twice is still one row.
        try FocusStore.setSoftwareUpdateChecksEnabled(true, in: context, now: Self.timestamp)
        #expect(FocusStore.softwareUpdatePreferenceRows(in: context).count == 1)

        // Off is a written `false`, not a deleted row: "switched off" and "never asked" are two
        // facts, and the second means the updater was never started in this store.
        try FocusStore.setSoftwareUpdateChecksEnabled(false, in: context, now: Self.timestamp)
        #expect(!FocusStore.softwareUpdateChecksEnabled(in: context))
        #expect(FocusStore.softwareUpdatePreferenceRows(in: context).count == 1)
    }
}
