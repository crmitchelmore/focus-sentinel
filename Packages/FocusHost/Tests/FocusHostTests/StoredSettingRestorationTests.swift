import FocusCore
import FocusUI
import Foundation
import SwiftData
import Testing

@testable import FocusHost

/// **Every stored setting is read back at launch** (focus-8ry).
///
/// ## Why this is a fold over the schema and not a list of tests
///
/// The appearance preference was never restored at launch, and it was found by accident. Three
/// things had to be true at once for that to be possible, and only one of them was the missing
/// line: `AppComposition.appearance` was a stored-property initialiser, which structurally
/// cannot consult the store; the only proofs were single-root and in-process, where "restored"
/// and "never read" are the same reading; and **nothing anywhere enumerated the settings**, so
/// the question *which other columns share this shape?* had no answer short of reading the
/// schema by hand.
///
/// The last of those is the one this suite closes. `StoredSetting` is a total enumeration of the
/// person's stored settings, checked against `FocusStore.schema` itself — so a column a later
/// epic adds to either settings row fails `everySettingsColumnIsAccountedFor` until somebody
/// says what restores it. The switch below is exhaustive, so answering that question means
/// writing a value and reading it back through the value the running app actually uses, in a
/// **second composition root over the same store file**. One process cannot tell a restored
/// setting from a defaulted one, which is exactly how the defect survived every gate it faced.
@Suite("Every stored setting survives a relaunch", .serialized)
@MainActor
struct StoredSettingRestorationTests {
    /// One case per persisted settings column that holds a person's choice.
    ///
    /// Raw values are the **column names**, because that is what the schema check compares
    /// against: a case whose spelling drifts from its column fails as loudly as a missing one.
    enum StoredSetting: String, CaseIterable {
        case appearancePreferenceRaw
        case sensingPaused
        case idleThresholdSeconds
        case corroborationTickSeconds
        case launchContextOnSessionStart
        case mediaSuppressionEnabled
        case lastRitualLocalDay
        case ritualEnabled
        case hotKeyKeyCode
        case hotKeyModifierFlags
        case voiceRaw
        case reducedInterruption
        case quietHoursStartMinuteOfDay
        case quietHoursEndMinuteOfDay
    }

    /// The two rows the app persists a person's settings into.
    static let settingsEntities = ["AppSettingsRecord", "NudgePreferencesRecord"]

    /// Columns that are not anybody's choice: the identity and the two schema timestamps.
    static let bookkeeping: Set<String> = ["id", "schemaTouchedAt", "touchedAt"]

    /// A writable directory holding a store this test owns.
    static func temporaryStoreURL() -> URL {
        let directory = URL(filePath: NSTemporaryDirectory(), directoryHint: .isDirectory)
            .appending(path: "focus-restore-\(UUID().uuidString)", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appending(path: FocusStore.storeFileName, directoryHint: .notDirectory)
    }

    /// **The launch, as far as a test process may run it.**
    ///
    /// `start()` itself is out of reach: it offers a global shortcut to the real Carbon event
    /// target and attaches the observer graph, neither of which a unit process has any business
    /// doing. These are the three things it does that read the store, called in its order, so a
    /// setting restored here is a setting the shipping launch restores.
    static func launch(_ root: AppComposition) {
        root.joinHosts()
        root.registerHotKey(root.storedHotKeySpec())
        root.refreshCockpit()
    }

    /// **The schema is the list, and this suite is answerable to it** (focus-8ry).
    ///
    /// Read off `FocusStore.schema` rather than written down twice: a column added to either
    /// settings row by a later epic arrives here without anybody remembering to add it, and the
    /// only way to make this pass again is to say — in the exhaustive switch below — what writes
    /// it and what reads it back at launch.
    @Test("every settings column in the shipping schema is accounted for")
    func everySettingsColumnIsAccountedFor() {
        let entities = FocusStore.schema.entities
            .filter { Self.settingsEntities.contains($0.name) }

        // Non-vacuity first, and it is not decoration: the entity names above are strings, and a
        // renamed row would leave this fold reading no columns at all — which satisfies "every
        // column is covered" by covering none.
        #expect(entities.map(\.name).sorted() == Self.settingsEntities.sorted())

        let columns = entities
            .flatMap { $0.properties.map(\.name) }
            .filter { !Self.bookkeeping.contains($0) }
        #expect(Set(columns) == Set(StoredSetting.allCases.map(\.rawValue)))
    }

    /// **Write it in one root, read it back in the next.** Every case, one pair of roots each.
    ///
    /// The read is always of the value the *running app* uses — `appearance.preference`,
    /// `sensingHost.settings`, `nudgeHost.preferences`, `hotKeySpec`, the cockpit projection —
    /// and never of a `FocusStore.…(in:)` call. That distinction is the whole defect:
    /// `storedAppearancePreference()` answered correctly for the entire life of the bug.
    @Test("every stored setting is the app's live value again at the next launch",
          arguments: StoredSetting.allCases)
    func everyStoredSettingIsRestored(setting: StoredSetting) {
        let url = Self.temporaryStoreURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        do {
            let first = CompositionRootTests.root(storeKind: .temporary(url))
            defer { first.stop() }
            Self.write(setting, into: first)
        }

        let second = CompositionRootTests.root(storeKind: .temporary(url))
        defer {
            second.stop()
            second.menuBar.remove()
        }
        Self.launch(second)

        #expect(Self.isRestored(setting, in: second), "\(setting.rawValue) did not survive")
    }

    /// Put a value that is **not** the shipped default into the store, through the app's own
    /// writer wherever one exists.
    ///
    /// Not the default, because the defect's answer is the default: a launch that reads nothing
    /// agrees with a fixture that seeded the default, and the test would pass on the broken
    /// program.
    ///
    /// **Every column now goes through a writer the application has** (focus-d3g). Three of them
    /// used to be set on the row here by hand, with a comment saying why: nothing in the app
    /// could write them, so a read-back proof had to supply the write itself — which is precisely
    /// the shape a read-back proof cannot see through. Deleting that hand-seeding is what makes
    /// this suite red without the General pane's two controls.
    static func write(_ setting: StoredSetting, into root: AppComposition) {
        let context = root.modelContainer.mainContext
        let now = root.dateProvider.now
        switch setting {
        case .appearancePreferenceRaw:
            root.applyAppearancePreference(.light)

        case .sensingPaused, .idleThresholdSeconds, .corroborationTickSeconds,
             .launchContextOnSessionStart, .mediaSuppressionEnabled:
            // One writer for the whole value, which is what `setSensingSettings` is for: a
            // partial write from a caller that had read only its own field is the shape that
            // resets the other four.
            _ = try? FocusStore.setSensingSettings(
                Self.probeSensingSettings,
                in: context,
                now: now
            )

        case .lastRitualLocalDay:
            // The app's own writer. It records that today's ritual has been answered or
            // dismissed, which is the only thing that ever sets this column.
            root.priorityHost.dismissRitual()

        case .ritualEnabled:
            // **The app's own writer** (focus-d3g). This case used to set the column on the row
            // by hand, and said so: nothing in the application could write it, so the only value
            // it could ever hold was the schema's default. The General pane's switch is that
            // writer now, reached through the same sink the pane holds.
            root.perform(CaptureSettingsAction.setRitualEnabled(false))

        case .hotKeyKeyCode, .hotKeyModifierFlags:
            // The other half of the same defect, and the user-reachable one: P-55 measured that
            // `RegisterEventHotKey` hands over a combination another application already owns
            // without complaint, so somebody whose Mac binds the default had no route out.
            root.perform(CaptureSettingsAction.setQuickCaptureShortcut(Self.probeHotKey))

        case .voiceRaw, .reducedInterruption,
             .quietHoursStartMinuteOfDay, .quietHoursEndMinuteOfDay:
            _ = try? FocusStore.setInterventionPreferences(
                Self.probeInterventionPreferences,
                in: context,
                now: now
            )
        }
    }

    /// Whether the **live** value this launch is running on is the one the last launch stored.
    static func isRestored(_ setting: StoredSetting, in root: AppComposition) -> Bool {
        let sensing = root.sensingHost.settings
        // **`chosen`, not `preferences`** — what the person set, rather than that plus what the
        // Mac forces on top of it. `accessibilityDisplayShouldReduceMotion` can turn reduced
        // interruption on, so a developer with Reduce Motion enabled would read `true` from
        // `preferences` whether the store was consulted or not.
        let preferences = root.nudgeHost.chosen
        switch setting {
        case .appearancePreferenceRaw:
            // Both halves: what the shell believes, and what its windows are drawn in. A root
            // that read the store and left the traits alone would pass the first alone.
            return root.appearance.preference == .light
                && root.appearance.traits.colorScheme == .light

        case .sensingPaused:
            return sensing.sensingPaused == Self.probeSensingSettings.sensingPaused
        case .idleThresholdSeconds:
            return sensing.idleThresholdSeconds == Self.probeSensingSettings.idleThresholdSeconds
        case .corroborationTickSeconds:
            return sensing.corroborationTickSeconds
                == Self.probeSensingSettings.corroborationTickSeconds
        case .launchContextOnSessionStart:
            return sensing.launchContextOnSessionStart
                == Self.probeSensingSettings.launchContextOnSessionStart
        case .mediaSuppressionEnabled:
            return sensing.mediaSuppressionEnabled
                == Self.probeSensingSettings.mediaSuppressionEnabled

        case .lastRitualLocalDay:
            // The projection the cockpit draws. Today's ritual was answered in the launch above,
            // so the banner must not be offered again — which is the whole of "it asks once".
            return root.cockpitState.showsRitualPrompt == false
        case .ritualEnabled:
            // Nothing was dismissed in the launch above, so a root that ignored the column would
            // offer the banner. The switch is off, so it must not.
            return root.cockpitState.showsRitualPrompt == false

        case .hotKeyKeyCode:
            return root.hotKeySpec.keyCode == Self.probeHotKey.keyCode
        case .hotKeyModifierFlags:
            return root.hotKeySpec.modifierFlags == Self.probeHotKey.modifierFlags

        case .voiceRaw:
            return preferences.voice == Self.probeInterventionPreferences.voice
        case .reducedInterruption:
            return preferences.reducedInterruption
                == Self.probeInterventionPreferences.reducedInterruption
        case .quietHoursStartMinuteOfDay:
            return preferences.quietHours?.startMinuteOfDay
                == Self.probeInterventionPreferences.quietHours?.startMinuteOfDay
        case .quietHoursEndMinuteOfDay:
            return preferences.quietHours?.endMinuteOfDay
                == Self.probeInterventionPreferences.quietHours?.endMinuteOfDay
        }
    }

    /// Five sensing values, none of them the schema's default.
    static let probeSensingSettings = SensingSettingsValue(
        sensingPaused: true,
        idleThresholdSeconds: 321,
        corroborationTickSeconds: 7,
        launchContextOnSessionStart: true,
        mediaSuppressionEnabled: false
    )

    /// A shortcut that is registrable and is not `.quickCaptureDefault` — `storedHotKeySpec()`
    /// falls back to the default for anything this build would refuse, so an unregistrable probe
    /// would read back as the default and the check would pass on a launch that read nothing.
    static let probeHotKey = HotKeySpec(
        keyCode: 11,
        modifierFlags: HotKeySpec.quickCaptureDefault.modifierFlags
    )

    /// A voice, the flag and a window that wraps midnight — the common case for the setting.
    static let probeInterventionPreferences = InterventionPreferences(
        voice: .warm,
        reducedInterruption: true,
        quietHours: QuietHoursWindow(startMinuteOfDay: 22 * 60, endMinuteOfDay: 7 * 60)
    )
}
