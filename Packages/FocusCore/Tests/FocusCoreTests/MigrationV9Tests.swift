import Foundation
import SwiftData
import Testing
@testable import FocusCore

/// **Schema 9: the policy tunings' rows** (focus-exdi).
@Suite("Schema v9 migration")
@MainActor
struct MigrationV9Tests {
    static let timestamp = Date(timeIntervalSince1970: 1_767_225_600)

    @Test("v9 is the ninth schema and the eighth stage")
    func planShape() {
        // The newest schema is v10 since focus-exdi.4; `MigrationV10Tests` pins the plan's tail.
        #expect(FocusSchemaV9.versionIdentifier == Schema.Version(9, 0, 0))
        #expect(FocusMigrationPlan.schemas.count >= 9)
        #expect(FocusMigrationPlan.schemas[8] is FocusSchemaV9.Type)
        #expect(FocusMigrationPlan.stages.count >= 8)
    }

    @Test("v9 adds exactly one entity and re-declares none")
    func versionNineIsStrictlyAdditive() {
        #expect(FocusSchemaV9.models.count == FocusSchemaV8.models.count + 1)
        for prior in FocusSchemaV8.models {
            #expect(
                FocusSchemaV9.models.contains { $0 == prior },
                "v9 re-declared \(String(describing: prior))"
            )
        }
        let before = Schema(versionedSchema: FocusSchemaV8.self)
        let after = Schema(versionedSchema: FocusSchemaV9.self)
        let beforeNames = Set(before.entities.map(\.name))
        let afterNames = Set(after.entities.map(\.name))
        #expect(afterNames.subtracting(beforeNames) == ["PolicyTuningRecord"])
        #expect(beforeNames.subtracting(afterNames).isEmpty, "v9 removed an entity")
        for name in beforeNames {
            let beforeProperties = Set(before.entities.first { $0.name == name }?.properties.map(\.name) ?? [])
            let afterProperties = Set(after.entities.first { $0.name == name }?.properties.map(\.name) ?? [])
            #expect(!beforeProperties.isEmpty, "the v8 entity \(name) was not found")
            #expect(beforeProperties == afterProperties, "v9 changed the columns of \(name)")
        }
    }

    @Test("the committed v8 fixture opens under v9 with its rows intact and no dial turned")
    func versionEightFixtureOpensUnderVersionNine() throws {
        let source = try SchemaV8Fixture.copyToTemporaryDirectory()
        let container = try FocusStore.makeContainer(kind: .temporary(source))
        let context = container.mainContext
        let tasks = try context.fetch(FetchDescriptor<FocusSchemaV3.PriorityTask>())
        #expect(tasks.map(\.intent) == [SchemaV8Fixture.taskIntent])
        #expect(FocusStore.privacyPreferences(in: context).retention == SchemaV8Fixture.retentionWindow)
        #expect(FocusStore.policyTunings(in: context).isShipped)
    }

    @Test("a dial turned is a row; turned back it is no row; reset is no rows")
    func dialsAreRows() throws {
        let container = try FocusStore.makeContainer(kind: .inMemory)
        let context = container.mainContext
        #expect(FocusStore.policyTunings(in: context).isShipped)

        try FocusStore.setPolicyTuning(.dailyInterruptionCap, to: 12, in: context, now: Self.timestamp)
        try FocusStore.setPolicyTuning(.mandateCooldown, to: 900, in: context, now: Self.timestamp)
        var read = FocusStore.policyTunings(in: context)
        #expect(read.count(.dailyInterruptionCap) == 12)
        #expect(read.duration(.mandateCooldown) == .seconds(900))
        #expect(read.duration(.queryCooldown) == InterventionPolicy.queryCooldown, "an untouched dial moved")
        #expect(FocusStore.policyTuningRows(in: context).count == 2)

        // Out of range is clamped, not stored raw.
        try FocusStore.setPolicyTuning(.dailyQueryCap, to: 9_999, in: context, now: Self.timestamp)
        read = FocusStore.policyTunings(in: context)
        #expect(Double(read.count(.dailyQueryCap)) == PolicyTuning.dailyQueryCap.range.upperBound)

        // Back to the shipped value deletes the row.
        try FocusStore.setPolicyTuning(.dailyInterruptionCap, to: Double(InterventionPolicy.dailyInterruptionCap), in: context, now: Self.timestamp)
        #expect(FocusStore.policyTuningRows(in: context).count == 2)
        #expect(FocusStore.policyTunings(in: context).count(.dailyInterruptionCap) == InterventionPolicy.dailyInterruptionCap)

        try FocusStore.resetPolicyTunings(in: context)
        #expect(FocusStore.policyTuningRows(in: context).isEmpty)
        #expect(FocusStore.policyTunings(in: context).isShipped)
    }

    @Test("a row whose key the app no longer knows is skipped and kept")
    func unknownKeysAreKept() throws {
        let container = try FocusStore.makeContainer(kind: .inMemory)
        let context = container.mainContext
        context.insert(FocusSchemaV9.PolicyTuningRecord(key: "retiredDial", value: 3, touchedAt: Self.timestamp))
        try context.save()
        #expect(FocusStore.policyTunings(in: context).isShipped)
        #expect(FocusStore.policyTuningRows(in: context).count == 1)
        #expect(PolicyTuning.decode("retiredDial") == nil)
        #expect(PolicyTuning.decode("mandateCooldown") == .mandateCooldown)
    }
}
