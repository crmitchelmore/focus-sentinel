import AppKit
import ApplicationServices
import FocusCore
import Foundation

/// Reads which item is selected inside the frontmost application (issue #24).
///
/// A protocol so the composition root can be driven by a double: every test that asserts "with
/// the switch off, nothing is read" counts calls on a recording reader rather than trusting a
/// real one to stay quiet.
@MainActor
protocol SelectedItemReading: AnyObject {
    /// The item selected in `activation`'s application, or `nil` when the person has not
    /// switched the Accessibility ask on, macOS has not granted it, the application is not one
    /// whose window title names a task, or the title names nothing worth keeping.
    func selectedItem(in activation: ClearedActivation, optIns: GrantOptIns) -> SelectedItem?

    /// How many reads reached the Accessibility API.
    var readCount: Int { get }
}

/// **The one place in this application that reads what the Accessibility grant unlocks**
/// (issue #24, owner's ruling 2026-10-15).
///
/// Every Accessibility *use* selector this repository contains lives in this file and nowhere
/// else; `Config/grant-use-sites.txt` names it so `check-grants.sh` and R-33b in
/// `check-forbidden.sh` can prove the confinement from both sides, as they already do for
/// `SystemGrantRequester.swift` and the request selectors.
///
/// ## The privacy shape, and where each part of it is kept
///
/// * **Opt-in.** Nothing is read unless the person switched the Accessibility ask on in
///   Settings ▸ Privacy *and* macOS trusts the app. A default install never reaches the first
///   Accessibility call.
/// * **Frontmost only, at judgement time.** The caller hands in the activation e03's
///   `SensitivityGate` already cleared, so a password manager or a private window is never read:
///   the gate stood it down before this object was asked.
/// * **A short list of applications.** `SelectedItem.readableApplications` names the
///   mixed-use applications whose window title says which chat, project or session is open.
///   Browsers, mail and messages are not on it, on purpose.
/// * **Reduced before it is kept.** The raw title lives in this function's locals and nowhere
///   else: it is never logged, never stored, never exported. What leaves is a `SelectedItem`,
///   whose label is one segment of the title, sanitised and capped.
/// * **On device.** This file imports no networking API, and nothing it returns is sent
///   anywhere; `check-boundaries.sh` holds FocusHost to that already.
@MainActor
final class SystemSelectedItemReader: SelectedItemReading {
    /// How long one Accessibility message may block the main actor. A hung application must not
    /// hang this one: past this, the read gives up and the question falls back to the app.
    private static let messagingTimeout: Float = 0.25

    /// The attribute names, spelled rather than imported: `ApplicationServices` declares them as
    /// global `var`s, which Swift 6 refuses to read from a concurrent context — the same reason
    /// `SystemGrantRequester` spells its prompt key.
    private static let focusedWindowAttribute = "AXFocusedWindow" as CFString
    private static let titleAttribute = "AXTitle" as CFString

    /// How many reads reached the Accessibility API. The self-check publishes it, so a default
    /// install can prove the reader never ran.
    private(set) var readCount = 0

    func selectedItem(in activation: ClearedActivation, optIns: GrantOptIns) -> SelectedItem? {
        guard optIns.isEnabled(.accessibilityWindowContext),
              SelectedItem.isReadable(activation.bundleIdentifier),
              AXIsProcessTrusted()
        else { return nil }

        readCount += 1
        let application = AXUIElementCreateApplication(activation.pid)
        AXUIElementSetMessagingTimeout(application, Self.messagingTimeout)

        var window: CFTypeRef?
        guard AXUIElementCopyAttributeValue(application, Self.focusedWindowAttribute, &window) == .success,
              let window, CFGetTypeID(window) == AXUIElementGetTypeID()
        else { return nil }

        var title: CFTypeRef?
        // The cast is checked by the type ID above; `as!` on a CF type is how Swift spells it.
        // swiftlint:disable:next force_cast
        let windowElement = window as! AXUIElement
        guard AXUIElementCopyAttributeValue(windowElement, Self.titleAttribute, &title) == .success,
              let rawTitle = title as? String
        else { return nil }

        let applicationName = NSRunningApplication(processIdentifier: activation.pid)?.localizedName
        return SelectedItem.normalise(
            title: rawTitle,
            applicationName: applicationName,
            bundleIdentifier: activation.bundleIdentifier
        )
    }
}
