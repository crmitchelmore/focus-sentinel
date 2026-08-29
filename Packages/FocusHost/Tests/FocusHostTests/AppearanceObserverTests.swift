import AppKit
import FocusCore
import Foundation
import Testing

@testable import FocusHost

/// **The object that decides whether the shell honours the Mac's settings** (focus-2er).
///
/// ## What had no test at all
///
/// `AppearanceObserver` lived in `App/`, which is not a package: no test bundle can import it.
/// So nothing anywhere asserted that the person's Match System / Light / Dark choice resolves
/// against the real system appearance, that all four accessibility flags are read, or — the one
/// that matters most — that the observer is *attached* to the Mac at all. Deleting
/// `startObserving()` left the whole nineteen-stage gate green while the app silently stopped
/// reacting to somebody switching to dark mode or turning on Reduce Motion.
///
/// It is in the composition layer now. It declares no view and imports no SwiftUI, so the
/// boundary matrix is unchanged, and these drive the real object against the real notification
/// centre — the accessibility half of which can be posted from inside this process, which is
/// what turns "the registration exists" into something a test can watch happen.
@Suite("The appearance observer", .serialized)
@MainActor
struct AppearanceObserverTests {
    // MARK: - The preference resolves against the machine

    /// Light and Dark are the person overriding the Mac; Match System is not. Read against
    /// `systemColorScheme`, not against a constant, because a test that hard-coded `.light`
    /// would fail on a developer's machine in dark mode for a reason that is not a defect.
    @Test("an explicit preference overrides the system, and Match System follows it")
    func thePreferenceResolvesAgainstTheSystem() {
        let observer = AppearanceObserver(preference: .dark)
        #expect(observer.traits.colorScheme == .dark)

        observer.preference = .light
        #expect(observer.traits.colorScheme == .light)

        observer.preference = .matchSystem
        #expect(observer.traits.colorScheme == AppearanceObserver.systemColorScheme)
    }

    /// Setting the preference recomputes: it is `didSet`, and a `didSet` somebody deleted would
    /// leave the shell drawing the previous choice until the next system notification.
    @Test("choosing a preference republishes the traits immediately")
    func settingThePreferenceRepublishes() {
        let observer = AppearanceObserver(preference: .light)
        let before = observer.refreshCount

        observer.preference = .dark

        #expect(observer.refreshCount == before + 1, "the preference was stored and not applied")
        #expect(observer.traits.colorScheme == .dark)
    }

    /// The four accessibility flags come from `NSWorkspace`, which reports them with no
    /// permission prompt. Asserted against the same source rather than against literals, for the
    /// reason above: this machine's own settings are not the subject.
    @Test("all four accessibility flags are read from the workspace")
    func everyAccessibilityFlagIsRead() {
        let workspace = NSWorkspace.shared
        let traits = AppearanceObserver(preference: .matchSystem).traits

        #expect(traits.increasedContrast == workspace.accessibilityDisplayShouldIncreaseContrast)
        #expect(traits.reduceTransparency == workspace.accessibilityDisplayShouldReduceTransparency)
        #expect(traits.reduceMotion == workspace.accessibilityDisplayShouldReduceMotion)
        #expect(
            traits.differentiateWithoutColor
                == workspace.accessibilityDisplayShouldDifferentiateWithoutColor
        )
    }

    // MARK: - It is attached to the Mac

    /// **The registration, watched happening.**
    ///
    /// `NSWorkspace.accessibilityDisplayOptionsDidChangeNotification` is the one notification
    /// covering Increase Contrast, Reduce Transparency, Reduce Motion and Differentiate Without
    /// Colour, and it can be posted from inside this process — so "the observer is listening" is
    /// a thing a test can make happen rather than a line of code somebody read.
    ///
    /// Delete `startObserving()`, or drop the workspace registration inside it, and this fails.
    @Test("a workspace accessibility notification re-reads the live system")
    func theAccessibilityRegistrationIsLive() {
        let observer = AppearanceObserver(preference: .light)
        let before = observer.refreshCount

        NSWorkspace.shared.notificationCenter.post(
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil
        )
        Self.settle()

        #expect(
            observer.refreshCount > before,
            "the observer is not listening to the Mac's accessibility settings"
        )
    }

    /// The observer the whole shell is themed from is the composition root's own, and it is the
    /// one `AppComposition.appearanceTraits(for:)` publishes. Two instances would mean the
    /// quick-capture panel and the cockpit could disagree about what the Mac looks like.
    @Test("the composition root publishes its own observer's traits to every window")
    func theRootPublishesItsOwnObserver() {
        let root = CompositionRootTests.root()
        defer { root.stop() }
        root.appearance.preference = .dark

        for surface in ShellThemedSurface.allCases {
            #expect(root.appearanceTraits(for: surface) == root.appearance.traits)
            #expect(root.appearanceTraits(for: surface).colorScheme == .dark)
        }
        #expect(root.shellWires == Set(ShellThemedSurface.allCases.map(\.wire)))
    }

    /// Give the notification queued on `.main` its turn. The observer registers with
    /// `queue: .main`, so the callback is delivered asynchronously even when the poster is
    /// already on the main actor.
    static func settle() {
        CFRunLoopRunInMode(.defaultMode, 0.3, false)
    }
}
