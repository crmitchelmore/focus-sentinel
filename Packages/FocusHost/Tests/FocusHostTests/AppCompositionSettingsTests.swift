import FocusCore
import FocusUI
import Foundation
import SwiftData
import Testing

@testable import FocusHost

/// **What the Settings scene asks the composition root to do** (focus-cp2).
///
/// ## Why these exist rather than a self-check probe
///
/// The other three `App/` wires are driven end-to-end by `scripts/self-check.sh`, because each of
/// them fires on its own during a launch: the cockpit draws, the window's undo manager arrives,
/// the appearance is resolved, and a `focus://` URL can be delivered through
/// `NSApp.delegate.application(_:open:)`. The Settings pane's two are different in kind — a
/// person has to **click** a control to fire either — and no lane in this programme holds the
/// Accessibility grant it would take to synthesise that click in a headless run. The charter
/// forbids an acceptance criterion that depends on a grant, so there is no honest way to assert
/// those two closures from the gate.
///
/// What *is* achievable is that neither closure has anything in it left to get wrong. The Settings
/// scene now reads one value and calls one verb, and both verbs are here. A regression in what
/// they do fails this suite; the two remaining lines in `App/` are pure forwarding, and gutting
/// one produces a control that visibly does nothing rather than a defect that hides.
@Suite("The Settings scene's two stored facts", .serialized)
@MainActor
struct AppCompositionSettingsTests {
    static func root() -> AppComposition {
        CompositionRootTests.root()
    }

    /// A root over a store this test owns, so a second one can open the same file and read back
    /// what the first wrote. `.inMemory` builds a **fresh** container every time, which is
    /// exactly the reading that cannot see a missing write.
    static func root(storeKind: FocusStore.Kind) -> AppComposition {
        CompositionRootTests.root(storeKind: storeKind)
    }

    /// A writable directory holding a store this test owns.
    static func temporaryStoreURL() -> URL {
        let directory = URL(filePath: NSTemporaryDirectory(), directoryHint: .isDirectory)
            .appending(path: "focus-settings-\(UUID().uuidString)", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appending(path: FocusStore.storeFileName, directoryHint: .notDirectory)
    }

    /// The window every quiet-hours assertion below is about: 22:00 to 07:00, which wraps
    /// midnight and is the common case for the setting.
    static let window = QuietHoursWindow(startMinuteOfDay: 22 * 60, endMinuteOfDay: 7 * 60)

    // MARK: - The appearance preference

    @Test("the stored appearance preference round-trips through the composition root")
    func theAppearancePreferenceRoundTrips() {
        let root = Self.root()
        defer { root.stop() }

        // Nothing stored: the honest answer is the default, not a guess.
        #expect(root.storedAppearancePreference() == .matchSystem)

        root.setAppearancePreference(.dark)
        #expect(root.storedAppearancePreference() == .dark)

        // …and it is one row, rewritten, rather than a second one the next read might miss.
        root.setAppearancePreference(.light)
        #expect(root.storedAppearancePreference() == .light)
    }

    /// The write goes to the container the Settings scene is handed, which is the one the rest of
    /// the application reads. A preference written into a context nobody else has is a preference
    /// that vanishes at relaunch.
    @Test("the appearance preference is written into the application's own container")
    func theAppearanceWriteGoesToTheAppsContainer() {
        let root = Self.root()
        defer { root.stop() }

        root.setAppearancePreference(.dark)

        #expect(
            FocusStore.appearancePreference(in: root.modelContainer.mainContext) == .dark
        )
    }

    /// **A second composition root over the same store file, folded over every preference the
    /// type has** (focus-8ry).
    ///
    /// The two tests above are single-root and in-process, and that is how "never restored"
    /// survived every gate: `storedAppearancePreference()` reads the store on demand and answered
    /// correctly the whole time, while `appearance.preference` — the value the three scenes are
    /// actually themed from — sat at the `.matchSystem` its stored-property initialiser gave it
    /// until somebody opened the Settings window. The proof and the defect were indistinguishable
    /// in one process.
    ///
    /// Over `allCases` rather than over one value, because the defect had a value that passes:
    /// a launch that reads nothing answers `.matchSystem`, so a test that seeded `.matchSystem`
    /// would agree with it. A fold cannot be written down that way — the case that agrees is in
    /// the loop beside the two that do not, and adding a fourth preference to the type puts it
    /// under this assertion without anybody remembering to.
    @Test("every appearance preference survives a relaunch", arguments: AppearancePreference.allCases)
    func theAppearanceSurvivesARelaunch(preference: AppearancePreference) {
        let url = Self.temporaryStoreURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        do {
            let first = Self.root(storeKind: .temporary(url))
            defer { first.stop() }
            first.applyAppearancePreference(preference)
            #expect(first.appearance.preference == preference)
        }

        let second = Self.root(storeKind: .temporary(url))
        defer { second.stop() }

        // The store's own answer first, so a failure below is legible: this one failing means the
        // write never landed, and this one passing while the next fails is the defect itself —
        // the value is on disk and the shell is not reading it.
        #expect(second.storedAppearancePreference() == preference)
        // **Read at construction, before anything opens a window.** No `start()`, no
        // `settingsWindowAppeared()`, no click: the person who never opens Settings is the person
        // the defect was about.
        #expect(second.appearance.preference == preference)
        // …and resolved, which is what the windows are actually drawn from. A root that stored
        // the preference and left the traits alone would satisfy the line above and still draw
        // every surface in the system's scheme.
        #expect(
            second.appearance.traits.colorScheme
                == preference.resolvedColorScheme(system: AppearanceObserver.systemColorScheme)
        )
    }

    /// The launch read is the composition root's own, not a side effect of some other verb.
    ///
    /// Stated separately because the repair is one line in `init` and the thing that would undo
    /// it is somebody moving it into `start()` or `joinHosts()` — both of which a menu-bar-only
    /// launch does run, but neither of which the *unit* lane runs, and neither of which is where
    /// the sensing settings are read.
    @Test("the appearance is restored by construction alone, with nothing started")
    func theAppearanceIsRestoredByConstructionAlone() {
        let url = Self.temporaryStoreURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        do {
            let first = Self.root(storeKind: .temporary(url))
            defer { first.stop() }
            first.setAppearancePreference(.dark)
        }

        let second = Self.root(storeKind: .temporary(url))
        defer { second.stop() }
        #expect(second.appearance.preference == .dark)
        #expect(second.appearance.traits.colorScheme == .dark)
    }

    // MARK: - The Intervention pane

    /// The pane's actions, performed. `onInterventionAction` is a bare reference to this method
    /// in `App/`, so this is every control in the pane that does anything today.
    @Test("the Intervention pane's voice and interruption settings reach the nudge loop")
    func theInterventionActionsReachTheLoop() {
        let root = Self.root()
        defer { root.stop() }
        #expect(root.interventionSettings.voice == .standard)
        #expect(root.interventionSettings.reducedInterruption == false)

        root.perform(InterventionSettingsAction.setVoice(NudgeVoice.warm))
        #expect(root.nudgeHost.preferences.voice == NudgeVoice.warm)
        #expect(root.interventionSettings.voice == NudgeVoice.warm)

        root.perform(InterventionSettingsAction.setReducedInterruption(true))
        #expect(root.nudgeHost.preferences.reducedInterruption == true)
        // …and it did not quietly take the voice back to its default on the way.
        #expect(root.nudgeHost.preferences.voice == NudgeVoice.warm)
        #expect(root.interventionSettings.reducedInterruption == true)
    }

    /// **Every action the pane can raise now writes something**, which is the state this round
    /// leaves the pane in. There was a test here for the ones that did not — a deliberate no-op
    /// rather than a fake write — and the set it covered is empty: quiet hours is wired
    /// (focus-z7g), and the presentation-exclusion actions are wired to `SensitiveAppSeed`'s own
    /// verbs (focus-u3w) — which is the bead: `add` had no shipping call site at all before it.
    /// A total switch, so a case added to the vocabulary is a compile error here rather than a
    /// control this suite silently stops covering.
    @Test("every request the pane can make is one this root performs")
    func everyPaneActionIsPerformed() {
        func isPerformed(_ action: InterventionSettingsAction) -> Bool {
            switch action {
            case .setVoice, .setReducedInterruption, .setQuietHours: true
            case .addPresentationExclusion, .removePresentationExclusion: true
            }
        }
        #expect(isPerformed(.setVoice(.warm)))
        #expect(isPerformed(.setReducedInterruption(true)))
        #expect(isPerformed(.setQuietHours(nil)))
        #expect(isPerformed(.addPresentationExclusion("com.example.Keynote")))
        #expect(isPerformed(.removePresentationExclusion("com.example.Keynote")))
    }

    // MARK: - The voice and "Interrupt me less" (focus-40i)

    /// **A second composition root over the same store file**, which is the only reading that
    /// can prove a setting was written. The suite's other reading of these two — set them, then
    /// assert they reached the loop — is satisfied exactly as well by an in-memory property,
    /// which is how "never persisted" survived every gate: the proof and the defect were
    /// indistinguishable in one process.
    @Test("the voice and Interrupt me less survive a relaunch")
    func theVoiceAndTheFlagSurviveARelaunch() {
        let url = Self.temporaryStoreURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        do {
            let first = Self.root(storeKind: .temporary(url))
            defer { first.stop() }
            first.perform(InterventionSettingsAction.setVoice(NudgeVoice.warm))
            first.perform(InterventionSettingsAction.setReducedInterruption(true))
        }

        let second = Self.root(storeKind: .temporary(url))
        defer {
            second.stop()
            second.menuBar.remove()
        }
        // Before the launch reads them back, the loop holds the constructed defaults. Asserted so
        // that the reading below is about the read-back rather than about a coincidence.
        #expect(second.nudgeHost.chosen == .defaults)

        second.startNudgeLoop()

        #expect(second.nudgeHost.preferences.voice == NudgeVoice.warm)
        #expect(second.nudgeHost.preferences.reducedInterruption == true)
        #expect(second.interventionSettings.voice == NudgeVoice.warm)
        #expect(second.interventionSettings.reducedInterruption == true)
    }

    /// A person who turns the flag **off** must get it off back, which a store that only ever
    /// wrote the interesting value would fail.
    @Test("turning Interrupt me less off survives a relaunch too")
    func turningTheFlagOffSurvivesARelaunch() {
        let url = Self.temporaryStoreURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        do {
            let first = Self.root(storeKind: .temporary(url))
            defer { first.stop() }
            first.perform(InterventionSettingsAction.setReducedInterruption(true))
            first.perform(InterventionSettingsAction.setReducedInterruption(false))
        }

        let second = Self.root(storeKind: .temporary(url))
        defer {
            second.stop()
            second.menuBar.remove()
        }
        second.startNudgeLoop()

        #expect(second.nudgeHost.chosen.reducedInterruption == false)
    }

    /// What is written is **what the person chose**, never what Reduce Motion forces. A row that
    /// recorded the forced flag would leave somebody who turns Reduce Motion off later holding a
    /// setting they never picked.
    @Test("Reduce Motion forces the loop's flag and is never written to the person's row")
    func theForcedFlagIsNotStored() {
        let root = Self.root()
        defer { root.stop() }

        root.nudgeHost.observe(reduceMotion: true)

        #expect(root.nudgeHost.preferences.reducedInterruption == true)
        #expect(root.nudgeHost.chosen.reducedInterruption == false)

        // A write of any of the three must not launder the forced flag into the row.
        root.perform(InterventionSettingsAction.setVoice(NudgeVoice.direct))

        #expect(
            FocusStore.interventionPreferences(in: root.modelContainer.mainContext)
                .reducedInterruption == false
        )
    }

    // MARK: - Quiet hours (focus-z7g)

    /// **The three places a window has to arrive**, and each of them was separately capable of
    /// being green over a dead control: the pane's read-back, the surroundings the twelve-gate
    /// suppression stack evaluates, and the row on disk.
    @Test("setting a quiet-hours window reaches the pane, the gate and the store")
    func theQuietHoursWindowReachesEverything() {
        let root = Self.root()
        defer { root.stop() }

        // R-85's shipped default, and the state the dead button could never leave.
        #expect(root.interventionSettings.quietHours == nil)
        #expect(root.nudgeSurroundings().quietHours.isEnabled == false)

        root.perform(InterventionSettingsAction.setQuietHours(Self.window))

        #expect(root.interventionSettings.quietHours == Self.window)
        #expect(root.nudgeSurroundings().quietHours.window == Self.window)
        #expect(
            FocusStore.interventionPreferences(in: root.modelContainer.mainContext).quietHours
                == Self.window
        )
    }

    /// The four boundary buttons were unreachable in the product because the pane could never
    /// draw them: they exist only inside `if let window = settings.quietHours`. This drives the
    /// sequence a person actually performs — switch on, then move a boundary — through the
    /// composition root's own verb.
    @Test("a boundary move lands on the window the pane is already showing")
    func aBoundaryMoveLands() {
        let root = Self.root()
        defer { root.stop() }

        root.perform(InterventionSettingsAction.setQuietHours(
            InterventionSettingsView.startingWindow
        ))
        let shown = try? #require(root.interventionSettings.quietHours)
        #expect(shown == InterventionSettingsView.startingWindow)

        root.perform(InterventionSettingsAction.setQuietHours(
            InterventionSettingsView.moved(
                InterventionSettingsView.startingWindow,
                startBy: -InterventionSettingsView.quietHoursStep
            )
        ))

        #expect(
            root.interventionSettings.quietHours?.startMinuteOfDay
                == InterventionSettingsView.startingWindow.startMinuteOfDay
                    - InterventionSettingsView.quietHoursStep
        )
    }

    /// Turning it off again is a state the pane can reach, and it must clear the row rather than
    /// leave the last window behind for the next launch to restore.
    @Test("turning the window off clears it everywhere")
    func turningTheWindowOffClearsIt() {
        let root = Self.root()
        defer { root.stop() }

        root.perform(InterventionSettingsAction.setQuietHours(Self.window))
        root.perform(InterventionSettingsAction.setQuietHours(nil))

        #expect(root.interventionSettings.quietHours == nil)
        #expect(root.nudgeSurroundings().quietHours.isEnabled == false)
        #expect(
            FocusStore.interventionPreferences(in: root.modelContainer.mainContext).quietHours
                == nil
        )
    }

    /// **A second composition root on the same store file**, which is the only reading that can
    /// tell a stored window from a remembered one. The first root sets it and stops; the second
    /// opens the same file and starts its nudge loop, exactly as a relaunch does.
    @Test("a window set in one launch is in the gate's hands in the next")
    func theWindowSurvivesARelaunch() throws {
        let url = Self.temporaryStoreURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        do {
            let first = Self.root(storeKind: .temporary(url))
            defer { first.stop() }
            first.perform(InterventionSettingsAction.setQuietHours(Self.window))
            #expect(first.interventionSettings.quietHours == Self.window)
        }

        let second = Self.root(storeKind: .temporary(url))
        defer {
            second.stop()
            second.menuBar.remove()
        }
        // The nudge half of `start()`, which is where a launch reads the person's settings back.
        second.startNudgeLoop()

        #expect(second.interventionSettings.quietHours == Self.window)
        #expect(second.nudgeSurroundings().quietHours.window == Self.window)
    }
}
