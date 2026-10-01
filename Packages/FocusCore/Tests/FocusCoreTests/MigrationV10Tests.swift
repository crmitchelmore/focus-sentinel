import Foundation
import SwiftData
import Testing
@testable import FocusCore

/// **Schema 10: the grant opt-ins' rows** (focus-exdi.4).
@Suite("Schema v10 migration")
@MainActor
struct MigrationV10Tests {
    static let timestamp = Date(timeIntervalSince1970: 1_767_225_600)

    @Test("v10 is the tenth schema and the ninth stage; v11 sits above it (focus-h8jf)")
    func planShape() {
        #expect(FocusSchemaV10.versionIdentifier == Schema.Version(10, 0, 0))
        #expect(FocusMigrationPlan.schemas.count == 11)
        #expect(FocusMigrationPlan.schemas[9] is FocusSchemaV10.Type)
        #expect(FocusMigrationPlan.stages.count == 10)
        #expect(FocusStore.schema.version == Schema.Version(11, 0, 0))
    }

    @Test("v10 adds exactly one entity and re-declares none")
    func versionTenIsStrictlyAdditive() {
        #expect(FocusSchemaV10.models.count == FocusSchemaV9.models.count + 1)
        for prior in FocusSchemaV9.models {
            #expect(
                FocusSchemaV10.models.contains { $0 == prior },
                "v10 re-declared \(String(describing: prior))"
            )
        }
        let before = Schema(versionedSchema: FocusSchemaV9.self)
        let after = Schema(versionedSchema: FocusSchemaV10.self)
        let beforeNames = Set(before.entities.map(\.name))
        let afterNames = Set(after.entities.map(\.name))
        #expect(afterNames.subtracting(beforeNames) == ["GrantOptInRecord"])
        #expect(beforeNames.subtracting(afterNames).isEmpty, "v10 removed an entity")
        for name in beforeNames {
            let beforeProperties = Set(before.entities.first { $0.name == name }?.properties.map(\.name) ?? [])
            let afterProperties = Set(after.entities.first { $0.name == name }?.properties.map(\.name) ?? [])
            #expect(!beforeProperties.isEmpty, "the v9 entity \(name) was not found")
            #expect(beforeProperties == afterProperties, "v10 changed the columns of \(name)")
        }
    }

    @Test("a fresh store asks for nothing, and a switch is a row")
    func optInsAreRows() throws {
        let container = try FocusStore.makeContainer(kind: .inMemory)
        let context = container.mainContext
        #expect(FocusStore.grantOptIns(in: context).asksForNothing)

        try FocusStore.setGrantOptIn(.accessibilityWindowContext, to: true, in: context, now: Self.timestamp)
        var read = FocusStore.grantOptIns(in: context)
        #expect(read.isEnabled(.accessibilityWindowContext))
        #expect(!read.isEnabled(.screenCapture))
        #expect(FocusStore.grantOptInRows(in: context).count == 1)

        // Switching on twice is still one row.
        try FocusStore.setGrantOptIn(.accessibilityWindowContext, to: true, in: context, now: Self.timestamp)
        #expect(FocusStore.grantOptInRows(in: context).count == 1)

        try FocusStore.setGrantOptIn(.accessibilityWindowContext, to: false, in: context, now: Self.timestamp)
        read = FocusStore.grantOptIns(in: context)
        #expect(read.asksForNothing)
        #expect(FocusStore.grantOptInRows(in: context).isEmpty)
    }

    @Test("a row whose key this build does not know is skipped and kept")
    func unknownKeysAreKept() throws {
        let container = try FocusStore.makeContainer(kind: .inMemory)
        let context = container.mainContext
        context.insert(FocusSchemaV10.GrantOptInRecord(key: "retiredGrant", touchedAt: Self.timestamp))
        try context.save()
        #expect(FocusStore.grantOptIns(in: context).asksForNothing)
        #expect(FocusStore.grantOptInRows(in: context).count == 1)
    }
}
