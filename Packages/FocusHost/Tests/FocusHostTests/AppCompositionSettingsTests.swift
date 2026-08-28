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

    /// The two the pane reports and this build does not yet store. They are a deliberate no-op
    /// rather than a fake write, and the assertion is that nothing else moved.
    @Test("the settings this build does not persist change nothing else")
    func theUnstoredSettingsChangeNothing() {
        let root = Self.root()
        defer { root.stop() }
        root.perform(InterventionSettingsAction.setVoice(NudgeVoice.warm))
        root.perform(InterventionSettingsAction.setReducedInterruption(true))
        let before = root.interventionSettings

        root.perform(InterventionSettingsAction.setQuietHours(InterventionPolicy.quietHoursDefault))
        root.perform(InterventionSettingsAction.removePresentationExclusion("com.example.Slides"))

        #expect(root.interventionSettings == before)
    }
}
