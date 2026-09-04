import Foundation
import SwiftData
import Testing

@testable import FocusCore

/// **The settings a person carries to another Mac** (F-134, focus-ix9).
///
/// Two halves. What travels — every preference, round-tripped through the bytes and read back off
/// a second store, so a field the writer forgot is a field the reader cannot find. And what an
/// import refuses: every arm of `SettingsImportRefusal` driven, each one leaving the store
/// **exactly as it was**, because a partly-applied settings file is a configuration nobody has
/// ever chosen.
@Suite("Settings document")
@MainActor
struct SettingsDocumentTests {
    static let reference = Date(timeIntervalSince1970: 1_767_225_600)

    static func store() throws -> (ModelContainer, ModelContext) {
        let container = try FocusStore.makeContainer(kind: .inMemory)
        return (container, container.mainContext)
    }

    /// A store with every travelling preference moved off its default, so a round trip that
    /// silently dropped a field would come back as a default rather than as the value.
    static func configured(_ context: ModelContext) throws {
        try FocusStore.setAppearancePreference(.dark, in: context, now: reference)
        try FocusStore.setInterventionPreferences(
            InterventionPreferences(
                voice: .direct,
                reducedInterruption: true,
                quietHours: QuietHoursWindow(startMinuteOfDay: 1_320, endMinuteOfDay: 420)
            ),
            in: context,
            now: reference
        )
        try FocusStore.setRetentionWindow(.sevenDays, in: context, now: reference)
        try FocusStore.setRitualEnabled(false, in: context, now: reference)
        var sensing = FocusStore.sensingSettings(in: context)
        sensing.idleThresholdSeconds = 321
        sensing.corroborationTickSeconds = 9
        sensing.launchContextOnSessionStart = true
        sensing.mediaSuppressionEnabled = false
        try FocusStore.setSensingSettings(sensing, in: context, now: reference)
        _ = try SensitiveAppSeed.add(
            bundleID: "com.example.Keynote",
            to: .presentationExcluded,
            in: context,
            now: reference
        )
    }

    // MARK: - What travels

    @Test("every preference survives the round trip into a second store")
    func everyPreferenceTravels() throws {
        let (sourceContainer, source) = try Self.store()
        _ = sourceContainer
        try Self.configured(source)

        let data = try SettingsDocument.json(from: source, generatedAt: Self.reference)

        let (targetContainer, target) = try Self.store()
        _ = targetContainer
        // The target starts on the defaults, so every assertion below is a value that moved.
        #expect(FocusStore.appearancePreference(in: target) == .matchSystem)
        #expect(FocusStore.privacyPreferences(in: target).retention == .ninetyDays)

        let result = SettingsDocument.import(data, into: target, now: Self.reference)
        #expect(try result.get().version == SettingsDocument.formatVersion)

        #expect(FocusStore.appearancePreference(in: target) == .dark)
        let intervention = FocusStore.interventionPreferences(in: target)
        #expect(intervention.voice == .direct)
        #expect(intervention.reducedInterruption)
        #expect(intervention.quietHours?.startMinuteOfDay == 1_320)
        #expect(intervention.quietHours?.endMinuteOfDay == 420)
        #expect(FocusStore.privacyPreferences(in: target).retention == .sevenDays)
        #expect(FocusStore.ritualEnabled(in: target) == false)
        let sensing = FocusStore.sensingSettings(in: target)
        #expect(sensing.idleThresholdSeconds == 321)
        #expect(sensing.corroborationTickSeconds == 9)
        #expect(sensing.launchContextOnSessionStart)
        #expect(sensing.mediaSuppressionEnabled == false)
        #expect(
            try SensitiveAppSeed.rows(in: target)
                .contains { $0.bundleID == "com.example.Keynote" && !$0.isBuiltIn }
        )
    }

    /// **No history travels.** The one assertion that says this is a settings file and not a
    /// second, quieter export.
    @Test("the settings document carries nothing about what the person did")
    func noHistoryTravels() throws {
        let (container, context) = try Self.store()
        _ = container
        let task = FocusSchemaV3.PriorityTask(
            intent: "A commitment nobody may carry away in a settings file",
            createdAt: Self.reference
        )
        context.insert(task)
        try context.save()

        let data = try SettingsDocument.json(from: context, generatedAt: Self.reference)
        let text = try #require(String(data: data, encoding: .utf8))
        #expect(!text.contains("A commitment nobody may carry away"))
        #expect(!text.contains("priorities"))
        #expect(!text.contains("sessions"))
        #expect(!text.contains("interventions"))
        // And no machine identifier, which is the other exclusion doctrine it inherits.
        #expect(!text.contains("bootIdentity"))
        #expect(!text.contains("sensingPaused"))
    }

    /// The paused switch is a state, not a way somebody wants their Macs set up. Deliberately
    /// left behind, and asserted so the omission is a decision rather than a gap.
    @Test("a paused Mac exports settings that do not pause the Mac they are imported to")
    func pausingDoesNotTravel() throws {
        let (sourceContainer, source) = try Self.store()
        _ = sourceContainer
        try FocusStore.setSensingPaused(true, in: source, now: Self.reference)
        let data = try SettingsDocument.json(from: source, generatedAt: Self.reference)

        let (targetContainer, target) = try Self.store()
        _ = targetContainer
        _ = SettingsDocument.import(data, into: target, now: Self.reference)
        #expect(FocusStore.sensingSettings(in: target).sensingPaused == false)
    }

    @Test("the document is deterministic")
    func theDocumentIsDeterministic() throws {
        let (container, context) = try Self.store()
        _ = container
        try Self.configured(context)
        let first = try SettingsDocument.json(from: context, generatedAt: Self.reference)
        let second = try SettingsDocument.json(from: context, generatedAt: Self.reference)
        #expect(first == second)
    }

    // MARK: - What an import refuses

    /// Mutate one field of a well-formed document and re-encode it. The refusal cases are driven
    /// through real bytes rather than through a hand-built struct, because the bytes are what a
    /// person actually hands the app.
    static func bytes(mutating change: (inout [String: Any]) -> Void) throws -> Data {
        let (container, context) = try store()
        _ = container
        try configured(context)
        let data = try SettingsDocument.json(from: context, generatedAt: reference)
        var object = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        change(&object)
        return try JSONSerialization.data(withJSONObject: object)
    }

    /// **A refused import changes nothing.** Asserted for every arm, by comparing the whole
    /// settings document the target would export before and after — one reading that moves if any
    /// field did.
    static func expectRefusedAndUnchanged(
        _ data: Data,
        _ expected: SettingsImportRefusal
    ) throws {
        let (container, target) = try store()
        _ = container
        let before = try SettingsDocument.read(from: target, generatedAt: reference).json()

        let result = SettingsDocument.import(data, into: target, now: reference)
        switch result {
        case .success:
            Issue.record("the import was accepted: \(expected)")
        case .failure(let refusal):
            #expect(refusal == expected)
            #expect(!refusal.reason.isEmpty)
        }

        let after = try SettingsDocument.read(from: target, generatedAt: reference).json()
        #expect(before == after, "a refused import moved something")
    }

    @Test("a version this build does not know is refused by number")
    func anUnknownVersionIsRefused() throws {
        let data = try Self.bytes { $0["version"] = 99 }
        try Self.expectRefusedAndUnchanged(data, .unknownVersion(99))
    }

    @Test("a data export picked by mistake is refused as what it is")
    func aDataExportIsRefusedAsOne() throws {
        let (container, context) = try Self.store()
        _ = container
        let data = try StoreExport.json(in: context, generatedAt: Self.reference)
        try Self.expectRefusedAndUnchanged(data, .notASettingsDocument("focus-sentinel.data"))
    }

    @Test("bytes that are not a document at all are refused")
    func malformedBytesAreRefused() throws {
        try Self.expectRefusedAndUnchanged(Data("not json, not anything".utf8), .malformed)
    }

    @Test("a deck this build has never heard of is refused rather than defaulted")
    func anUnknownVoiceIsRefused() throws {
        let data = try Self.bytes { $0["voiceRaw"] = "focus-ix9-not-a-deck" }
        try Self.expectRefusedAndUnchanged(data, .unknownVoice("focus-ix9-not-a-deck"))
    }

    @Test("a retention window this build does not offer is refused")
    func anUnknownWindowIsRefused() throws {
        let data = try Self.bytes { $0["retentionDays"] = 3 }
        try Self.expectRefusedAndUnchanged(data, .unknownRetentionWindow(3))
    }

    @Test("an exclusion row that is not an application identifier is refused")
    func anUnnormalisableSubjectIsRefused() throws {
        let data = try Self.bytes {
            $0["exclusions"] = [["bundleID": "https://example.com/path", "kindRaw": "sensitive"]]
        }
        try Self.expectRefusedAndUnchanged(
            data,
            .unnormalisableSubject("https://example.com/path")
        )
    }

    @Test("a quick-capture combination this platform will not register is refused")
    func anUnusableShortcutIsRefused() throws {
        let data = try Self.bytes { $0["hotKeyModifierFlags"] = 0 }
        let (container, target) = try Self.store()
        _ = container
        let before = try SettingsDocument.read(from: target, generatedAt: Self.reference).json()
        switch SettingsDocument.import(data, into: target, now: Self.reference) {
        case .success:
            Issue.record("an unmodified quick-capture key was accepted")
        case .failure(let refusal):
            if case .unusableShortcut = refusal {
                #expect(!refusal.reason.isEmpty)
            } else {
                Issue.record("wrong refusal: \(refusal)")
            }
        }
        let after = try SettingsDocument.read(from: target, generatedAt: Self.reference).json()
        #expect(before == after)
    }

    /// Every refusal has its own sentence, and no two share one — a vocabulary a surface can name
    /// rather than a single "the file is bad".
    @Test("every refusal says something different")
    func everyRefusalIsDistinct() {
        let refusals: [SettingsImportRefusal] = [
            .notASettingsDocument("x"),
            .unknownVersion(2),
            .malformed,
            .unknownVoice("x"),
            .unknownRetentionWindow(3),
            .unnormalisableSubject("x"),
            .unusableShortcut("x")
        ]
        let reasons = refusals.map(\.reason)
        #expect(Set(reasons).count == reasons.count)
        #expect(reasons.allSatisfy { !$0.isEmpty })
    }
}
