import FocusCore
import SwiftData
import SwiftUI
import Testing

@testable import FocusUI

/// Settings ships two tabs and both are full. These tests hold that line — an empty pane is
/// the failure mode this suite exists to catch — and prove that the preference the General
/// tab edits really does survive a round trip through the local store.
@Suite("Settings")
@MainActor
struct SettingsTests {
    // MARK: - Both tabs exist and neither is empty

    @Test("there are exactly two tabs, and both are named")
    func bothTabsExist() {
        #expect(SettingsTab.allCases.map(\.id) == ["general", "privacy"])
        #expect(Set(SettingsTab.allCases.map(\.titleKey)).count == 2)
        #expect(Set(SettingsTab.allCases.map(\.systemImage)).count == 2)
        for tab in SettingsTab.allCases {
            #expect(!tab.systemImage.isEmpty)
        }
    }

    @Test("the General tab offers every appearance preference the domain declares")
    func generalTabIsPopulated() {
        #expect(GeneralSettingsView.options == AppearancePreference.allCases)
        #expect(GeneralSettingsView.options.count == 3)
        #expect(GeneralSettingsView.options.contains(.matchSystem))
        #expect(Set(GeneralSettingsView.options.map(\.settingsTitleKey)).count == 3)
    }

    @Test("the Privacy tab draws real content and a real store location")
    func privacyTabIsPopulated() {
        #expect(!PrivacySettingsView.contentKeys.isEmpty)
        #expect(PrivacySettingsView.contentKeys.contains(.settingsPrivacyStatement))
        #expect(PrivacySettingsView.contentKeys.contains(.settingsPrivacyReveal))

        // The reveal button points at a real location, not a placeholder path.
        let url = FocusStore.applicationSupportURL
        #expect(url.isFileURL)
        #expect(url.lastPathComponent == "FocusSentinel.store")
        #expect(url.path(percentEncoded: false).contains("com.chrismitchelmore.FocusSentinel"))
    }

    // MARK: - The preference round-trips through the store

    @Test("the appearance preference round-trips through AppSettingsRecord")
    func preferenceRoundTripsThroughTheStore() throws {
        let container = try FocusStore.makeContainer(kind: .inMemory)
        let context = ModelContext(container)
        let stamp = Date(timeIntervalSince1970: 1_700_000_000)

        // Nothing stored yet is a real answer, not an error.
        #expect(FocusStore.appearancePreference(in: context) == .matchSystem)

        try FocusStore.setAppearancePreference(.dark, in: context, now: stamp)
        #expect(FocusStore.appearancePreference(in: context) == .dark)

        // Enum-backed fields persist as string raw values, never ordinals.
        let row = try #require(FocusStore.settingsRow(in: context))
        #expect(row.appearancePreferenceRaw == "dark")
        #expect(row.schemaTouchedAt == stamp)

        // A second write reuses the same row rather than accumulating settings rows.
        let later = stamp.addingTimeInterval(60)
        try FocusStore.setAppearancePreference(.light, in: context, now: later)
        let rows = try context.fetch(FetchDescriptor<FocusSchemaV2.AppSettingsRecord>())
        #expect(rows.count == 1)
        #expect(FocusStore.appearancePreference(in: context) == .light)
        #expect(rows[0].schemaTouchedAt == later)
    }

    @Test("every preference resolves to the colour scheme it names")
    func preferenceResolvesToAScheme() {
        #expect(AppearancePreference.matchSystem.resolvedColorScheme(system: .dark) == .dark)
        #expect(AppearancePreference.matchSystem.resolvedColorScheme(system: .light) == .light)
        #expect(AppearancePreference.light.resolvedColorScheme(system: .dark) == .light)
        #expect(AppearancePreference.dark.resolvedColorScheme(system: .light) == .dark)
    }

    // MARK: - Text

    @Test(
        "every string either tab draws resolves to real text",
        .enabled(if: LocalizationLane.catalogsAreCompiled)
    )
    func settingsStringsResolve() {
        var keys: [ShellStringKey] = SettingsTab.allCases.map(\.titleKey)
        keys += GeneralSettingsView.options.map(\.settingsTitleKey)
        keys += [.settingsAppearanceLabel, .settingsAppearanceNote]
        keys += PrivacySettingsView.contentKeys

        for key in keys {
            let resolved = ShellStrings.string(key)
            #expect(!resolved.isEmpty)
            #expect(resolved != key.rawValue)
        }
    }
}
