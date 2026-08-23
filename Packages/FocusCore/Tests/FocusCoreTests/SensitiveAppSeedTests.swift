import Foundation
import SwiftData
import Testing

@testable import FocusCore

@MainActor
@Suite("Sensitive-app seed")
struct SensitiveAppSeedTests {
    private static let now = FixedDateProvider.reference.now

    /// A store on disk, so that "across launches" means what it says: a second container over
    /// the same file, not the same context asked twice.
    private static func makeStoreURL() -> URL {
        let directory = URL.temporaryDirectory.appending(
            path: "focus-seed-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appending(path: "FocusSentinel.store", directoryHint: .notDirectory)
    }

    // MARK: - The seed itself

    @Test("Seeding an empty store writes every built-in identifier, marked as built-in")
    func seedWritesTheBuiltInList() throws {
        let container = try FocusStore.makeContainer(kind: .inMemory)
        let context = container.mainContext

        let inserted = try SensitiveAppSeed.seed(in: context, now: Self.now)

        #expect(inserted == SensitivityGate.builtInSensitiveBundleIDs.count)
        let rows = try SensitiveAppSeed.rows(in: context)
        let everyRowIsBuiltIn = rows.allSatisfy(\.isBuiltIn)
        let everyRowIsSensitive = rows.allSatisfy { $0.kind == .sensitive }
        #expect(everyRowIsBuiltIn)
        #expect(everyRowIsSensitive)
        #expect(Set(rows.map(\.bundleID)) == SensitivityGate.builtInSensitiveBundleIDs)
    }

    @Test("The seeded list is conservative and Messages is deliberately not on it")
    func messagesIsOfferedRatherThanSeeded() throws {
        let container = try FocusStore.makeContainer(kind: .inMemory)
        try SensitiveAppSeed.seed(in: container.mainContext, now: Self.now)

        let seeded = try SensitiveAppSeed.activeBundleIDs(in: container.mainContext)

        // A private-messaging app that is also a work tool for a great many people. Deciding
        // that for somebody would be the app having an opinion about who they talk to.
        #expect(seeded.contains("com.apple.MobileSMS") == false)
        #expect(SensitivityGate.suggestedSensitiveBundleIDs.contains("com.apple.MobileSMS"))

        // And the categories that *are* on it, one from each.
        #expect(seeded.contains("com.1password.1password"))
        #expect(seeded.contains("com.apple.keychainaccess"))
        #expect(seeded.contains("com.apple.PassKit.WalletApp"))
        #expect(seeded.contains("com.apple.Health"))
        #expect(seeded.contains("org.whispersystems.signal-desktop"))
    }

    @Test("The presentation-exclusion list seeds empty")
    func presentationExclusionsSeedEmpty() throws {
        let container = try FocusStore.makeContainer(kind: .inMemory)
        try SensitiveAppSeed.seed(in: container.mainContext, now: Self.now)

        // Seeding it with guesses would be a claim about applications this programme has not
        // measured.
        let excluded = try SensitiveAppSeed.activeBundleIDs(
            .presentationExcluded,
            in: container.mainContext
        )
        #expect(excluded.isEmpty)
    }

    // MARK: - Idempotence

    @Test("Seeding twice in one process inserts nothing the second time")
    func seedIsIdempotentInProcess() throws {
        let container = try FocusStore.makeContainer(kind: .inMemory)
        let context = container.mainContext

        let first = try SensitiveAppSeed.seed(in: context, now: Self.now)
        let second = try SensitiveAppSeed.seed(in: context, now: Self.now)

        #expect(first > 0)
        #expect(second == 0)
        #expect(try SensitiveAppSeed.rows(in: context).count == first)
    }

    @Test("Seeding is idempotent across launches")
    func seedIsIdempotentAcrossLaunches() throws {
        let url = Self.makeStoreURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let firstCount: Int
        do {
            let container = try FocusStore.makeContainer(kind: .temporary(url))
            firstCount = try SensitiveAppSeed.seed(in: container.mainContext, now: Self.now)
        }

        let container = try FocusStore.makeContainer(kind: .temporary(url))
        let secondCount = try SensitiveAppSeed.seed(
            in: container.mainContext,
            now: Self.now.addingTimeInterval(86_400)
        )

        #expect(secondCount == 0)
        #expect(try SensitiveAppSeed.rows(in: container.mainContext).count == firstCount)
    }

    // MARK: - A removal survives a reseed

    @Test("A user's removal of a built-in entry survives a reseed, across launches")
    func removalSurvivesAReseed() throws {
        let url = Self.makeStoreURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        do {
            let container = try FocusStore.makeContainer(kind: .temporary(url))
            try SensitiveAppSeed.seed(in: container.mainContext, now: Self.now)
            // The person decides their stocks app is not private enough to be worth pausing for.
            try SensitiveAppSeed.remove(bundleID: "com.apple.stocks", in: container.mainContext)
            #expect(
                try SensitiveAppSeed.activeBundleIDs(in: container.mainContext)
                    .contains("com.apple.stocks") == false
            )
        }

        // A later launch reseeds. An app that put the entry back would be arguing with them.
        let container = try FocusStore.makeContainer(kind: .temporary(url))
        let inserted = try SensitiveAppSeed.seed(
            in: container.mainContext,
            now: Self.now.addingTimeInterval(86_400)
        )

        #expect(inserted == 0)
        let active = try SensitiveAppSeed.activeBundleIDs(in: container.mainContext)
        #expect(active.contains("com.apple.stocks") == false)
        // Every other built-in is still there — the removal took one entry, not the list.
        #expect(active.count == SensitivityGate.builtInSensitiveBundleIDs.count - 1)
    }

    @Test("A removed built-in keeps its row as a tombstone rather than vanishing")
    func removalLeavesATombstone() throws {
        let container = try FocusStore.makeContainer(kind: .inMemory)
        let context = container.mainContext
        try SensitiveAppSeed.seed(in: context, now: Self.now)
        let before = try SensitiveAppSeed.rows(in: context).count

        try SensitiveAppSeed.remove(bundleID: "com.apple.stocks", in: context)

        #expect(try SensitiveAppSeed.rows(in: context).count == before)
        let row = try #require(
            try SensitiveAppSeed.rows(in: context).first { $0.bundleID == "com.apple.stocks" }
        )
        #expect(row.kind == .sensitiveRemovedByUser)
        #expect(row.kind?.isActive == false)
        #expect(row.kind?.list == .sensitive)
    }

    @Test("Putting a removed built-in back revives its row rather than adding a second one")
    func addingBackRevivesTheTombstone() throws {
        let container = try FocusStore.makeContainer(kind: .inMemory)
        let context = container.mainContext
        try SensitiveAppSeed.seed(in: context, now: Self.now)
        try SensitiveAppSeed.remove(bundleID: "com.apple.stocks", in: context)

        try SensitiveAppSeed.add(bundleID: "com.apple.stocks", in: context, now: Self.now)

        let matching = try SensitiveAppSeed.rows(in: context).filter {
            $0.bundleID == "com.apple.stocks"
        }
        #expect(matching.count == 1)
        #expect(matching[0].kind == .sensitive)
        // It was and remains a built-in; reviving it does not make it the person's own entry.
        #expect(matching[0].isBuiltIn)
    }

    // MARK: - The person's own entries

    @Test("A user-added entry suppresses, and is marked as theirs rather than built-in")
    func userEntriesAreMarkedAsTheirs() throws {
        let container = try FocusStore.makeContainer(kind: .inMemory)
        let context = container.mainContext
        try SensitiveAppSeed.seed(in: context, now: Self.now)

        try SensitiveAppSeed.add(bundleID: "  com.example.Diary  ", in: context, now: Self.now)

        let row = try #require(
            try SensitiveAppSeed.rows(in: context).first { $0.bundleID == "com.example.Diary" }
        )
        #expect(row.isBuiltIn == false)
        #expect(try SensitiveAppSeed.activeBundleIDs(in: context).contains("com.example.Diary"))
    }

    @Test("Removing a user's own entry deletes the row outright, with no tombstone")
    func removingAUserEntryDeletesIt() throws {
        let container = try FocusStore.makeContainer(kind: .inMemory)
        let context = container.mainContext
        try SensitiveAppSeed.add(bundleID: "com.example.Diary", in: context, now: Self.now)

        try SensitiveAppSeed.remove(bundleID: "com.example.Diary", in: context)

        // Nothing would put it back, so keeping a record of a choice they reversed would be
        // keeping something for no reason.
        #expect(try SensitiveAppSeed.rows(in: context).isEmpty)
    }

    @Test("A user entry survives a reseed too")
    func userEntriesSurviveAReseed() throws {
        let container = try FocusStore.makeContainer(kind: .inMemory)
        let context = container.mainContext
        try SensitiveAppSeed.seed(in: context, now: Self.now)
        try SensitiveAppSeed.add(bundleID: "com.example.Diary", in: context, now: Self.now)

        try SensitiveAppSeed.seed(in: context, now: Self.now)

        #expect(try SensitiveAppSeed.activeBundleIDs(in: context).contains("com.example.Diary"))
    }

    // MARK: - The gate the store builds

    @Test("The gate is built from the store, and every seeded entry suppresses")
    func everySeededEntrySuppresses() throws {
        let container = try FocusStore.makeContainer(kind: .inMemory)
        let context = container.mainContext
        try SensitiveAppSeed.seed(in: context, now: Self.now)

        let gate = try SensitiveAppSeed.gate(in: context)

        for bundleID in SensitivityGate.builtInSensitiveBundleIDs {
            let decision = gate.evaluate(
                FrontmostActivation(bundleIdentifier: bundleID, pid: 42, at: Self.now)
            )
            #expect(decision.suppressionReason == .builtInList)
            // And there is no cleared activation to read anything deeper with.
            #expect(decision.clearedActivation == nil)
        }
    }

    @Test("The gate keeps the two halves apart, because they mean different things")
    func theGateDistinguishesBuiltInFromUserAdded() throws {
        let container = try FocusStore.makeContainer(kind: .inMemory)
        let context = container.mainContext
        try SensitiveAppSeed.seed(in: context, now: Self.now)
        try SensitiveAppSeed.add(bundleID: "com.example.Diary", in: context, now: Self.now)

        let gate = try SensitiveAppSeed.gate(in: context)

        #expect(gate.userAdded == ["com.example.Diary"])
        #expect(gate.builtIn == SensitivityGate.builtInSensitiveBundleIDs)
        #expect(
            gate.evaluate(FrontmostActivation(bundleIdentifier: "com.example.Diary", pid: 1, at: Self.now))
                .suppressionReason == .userList
        )
    }

    @Test("A removed built-in no longer suppresses")
    func aRemovedEntryStopsSuppressing() throws {
        let container = try FocusStore.makeContainer(kind: .inMemory)
        let context = container.mainContext
        try SensitiveAppSeed.seed(in: context, now: Self.now)
        try SensitiveAppSeed.remove(bundleID: "com.apple.stocks", in: context)

        let gate = try SensitiveAppSeed.gate(in: context)
        let decision = gate.evaluate(
            FrontmostActivation(bundleIdentifier: "com.apple.stocks", pid: 1, at: Self.now)
        )

        #expect(decision.clearedActivation != nil)
    }

    @Test("A row this build cannot interpret belongs to no list and is never deleted")
    func unknownKindsAreInertAndSurvive() throws {
        let container = try FocusStore.makeContainer(kind: .inMemory)
        let context = container.mainContext
        context.insert(
            FocusSchemaV3.SensitiveAppEntry(
                bundleID: "com.example.FromTheFuture",
                kindRaw: "somethingALaterBuildInvented",
                isBuiltIn: true,
                addedAt: Self.now
            )
        )
        try context.save()

        #expect(try SensitiveAppSeed.activeBundleIDs(in: context).isEmpty)
        // Inert, but still there: it survives the round trip to whichever build wrote it.
        #expect(try SensitiveAppSeed.rows(in: context).count == 1)
        #expect(SensitiveEntryKind.decode("somethingALaterBuildInvented") == nil)
    }
}

@MainActor
@Suite("Sensing settings")
struct SensingSettingsTests {
    private static let now = FixedDateProvider.reference.now

    @Test("An unwritten store reports the schema's own defaults")
    func defaultsBeforeAnythingIsStored() throws {
        let container = try FocusStore.makeContainer(kind: .inMemory)

        let settings = FocusStore.sensingSettings(in: container.mainContext)

        #expect(settings == .defaults)
        #expect(settings.sensingPaused == false)
        #expect(settings.idleThresholdSeconds == 180)
        #expect(settings.corroborationTickSeconds == 5)
        // F-169's launcher is off by default, and open-only when on.
        #expect(settings.launchContextOnSessionStart == false)
        #expect(settings.mediaSuppressionEnabled)
    }

    @Test("The five settings round-trip through a store reopen")
    func settingsRoundTrip() throws {
        let directory = URL.temporaryDirectory.appending(
            path: "focus-sensing-settings-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "FocusSentinel.store", directoryHint: .notDirectory)

        let written = SensingSettingsValue(
            sensingPaused: true,
            idleThresholdSeconds: 600,
            corroborationTickSeconds: 10,
            launchContextOnSessionStart: true,
            mediaSuppressionEnabled: false
        )
        do {
            let container = try FocusStore.makeContainer(kind: .temporary(url))
            try FocusStore.setSensingSettings(written, in: container.mainContext, now: Self.now)
        }

        let container = try FocusStore.makeContainer(kind: .temporary(url))
        #expect(FocusStore.sensingSettings(in: container.mainContext) == written)
    }

    @Test("Flipping the pause switch leaves every other setting alone")
    func pauseSwitchIsSurgical() throws {
        let container = try FocusStore.makeContainer(kind: .inMemory)
        let context = container.mainContext
        try FocusStore.setSensingSettings(
            SensingSettingsValue(idleThresholdSeconds: 600, mediaSuppressionEnabled: false),
            in: context,
            now: Self.now
        )

        try FocusStore.setSensingPaused(true, in: context, now: Self.now)

        let settings = FocusStore.sensingSettings(in: context)
        #expect(settings.sensingPaused)
        // The failure mode this verb exists to prevent: a surface that read, changed one field
        // and wrote back would have reset the other four to whatever it last read.
        #expect(settings.idleThresholdSeconds == 600)
        #expect(settings.mediaSuppressionEnabled == false)
    }

    @Test("Writing the sensing settings does not create a second settings row")
    func settingsRowStaysSingular() throws {
        let container = try FocusStore.makeContainer(kind: .inMemory)
        let context = container.mainContext

        try FocusStore.setAppearancePreference(.dark, in: context, now: Self.now)
        try FocusStore.setSensingPaused(true, in: context, now: Self.now)
        try FocusStore.setSensingPaused(false, in: context, now: Self.now)

        let rows = try context.fetch(FetchDescriptor<FocusSchemaV3.AppSettingsRecord>())
        #expect(rows.count == 1)
        // And it left the appearance preference alone, which shares the row.
        #expect(FocusStore.appearancePreference(in: context) == .dark)
    }

    @Test("A tick of zero is clamped to a second rather than becoming a spin")
    func tickIsClamped() {
        let settings = SensingSettingsValue(corroborationTickSeconds: 0)
        #expect(settings.corroborationTick == .seconds(1))

        #expect(SensingSettingsValue.defaults.corroborationTick == .seconds(5))
        #expect(SensingSettingsValue.defaults.idleThresholdInterval == 180)
    }
}
