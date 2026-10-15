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
    /// switched the Accessibility ask on, macOS has not granted it, or neither the window title
    /// nor the window's selected row or main heading names anything worth keeping.
    func selectedItem(in activation: ClearedActivation, optIns: GrantOptIns) -> SelectedItem?

    /// How many reads reached the Accessibility API.
    var readCount: Int { get }
}

/// How long one Accessibility message may block the main actor. A hung application must not hang
/// this one: past this, the read gives up and the question falls back to the app.
private let messagingTimeout: Float = 0.25

/// The attribute names, spelled rather than imported: `ApplicationServices` declares them as global
/// `var`s, which Swift 6 refuses to read from a concurrent context — the same reason
/// `SystemGrantRequester` spells its prompt key.
private enum Attribute {
    static let focusedWindow = "AXFocusedWindow"
    static let title = "AXTitle"
    static let value = "AXValue"
    static let description = "AXDescription"
    static let role = "AXRole"
    static let subrole = "AXSubrole"
    static let children = "AXChildren"
    static let selectedRows = "AXSelectedRows"
    static let selectedChildren = "AXSelectedChildren"
}

/// **The one place in this application that reads what the Accessibility grant unlocks**
/// (issue #24, owner's ruling 2026-10-15; every application since the owner's follow-up).
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
///   the gate stood it down before this object was asked. Any other application may be read.
/// * **Read, never written.** One selector reads attributes; nothing here sets an attribute,
///   performs an action, registers an observer or bulk-reads. Those stay banned in
///   `Config/tcc-families.txt`. An Electron application that exposes no tree until a client
///   *writes* `AXManualAccessibility` therefore stays unread below its title, by design.
/// * **Reduced before it is kept.** The raw title, row text and heading text live in this
///   function's locals and nowhere else: never logged, never stored, never exported. What leaves
///   is a `SelectedItem`, whose label is one short segment, sanitised and capped.
/// * **Bounded.** One message may block for `messagingTimeout`; a walk below the title reads at
///   most `SelectedItemSearch.maximumElements` elements and stops at `searchBudget`.
/// * **On device.** This file imports no networking API, and nothing it returns is sent
///   anywhere; `check-boundaries.sh` holds FocusHost to that already.
@MainActor
final class SystemSelectedItemReader: SelectedItemReading {
    /// How long a walk below the title may take, all messages included. Measured on the owner's
    /// Mac: the Copilot app's ~300 elements read in well under this; one application's full tree
    /// took ten seconds, which is what the budget is for.
    private static let searchBudget: Duration = .milliseconds(150)

    private let clock: any MonotonicClock
    private var grace = SelectedItemGrace()

    init(clock: any MonotonicClock = SystemMonotonicClock()) {
        self.clock = clock
    }

    /// How many reads reached the Accessibility API. The self-check publishes it, so a default
    /// install can prove the reader never ran.
    private(set) var readCount = 0

    func selectedItem(in activation: ClearedActivation, optIns: GrantOptIns) -> SelectedItem? {
        guard optIns.isEnabled(.accessibilityWindowContext), AXIsProcessTrusted() else {
            grace.clear()
            return nil
        }
        readCount += 1
        return grace.resolve(read(activation), pid: activation.pid, now: clock.elapsed)
    }

    private func read(_ activation: ClearedActivation) -> SelectedItemGrace.Reading {
        let application = AXUIElementCreateApplication(activation.pid)
        AXUIElementSetMessagingTimeout(application, messagingTimeout)
        let log = MessageLog()

        let windowValue = log.copy(application, Attribute.focusedWindow)
        guard let windowValue, CFGetTypeID(windowValue) == AXUIElementGetTypeID() else {
            return log.timedOut ? .failed : .nothing
        }
        // The cast is checked by the type ID above; `as!` on a CF type is how Swift spells it.
        // swiftlint:disable:next force_cast
        let window = windowValue as! AXUIElement
        let applicationName = NSRunningApplication(processIdentifier: activation.pid)?.localizedName

        if let rawTitle = log.copy(window, Attribute.title) as? String,
           let item = SelectedItem.normalise(
               title: rawTitle,
               applicationName: applicationName,
               bundleIdentifier: activation.bundleIdentifier
           ) {
            return .item(item)
        }

        // The title names nothing — "GitHub Copilot", "~" — so look inside the window (#26).
        let deadline = clock.elapsed + Self.searchBudget
        let outcome = SelectedItemSearch.search(
            from: WindowElement(element: window, log: log),
            applicationName: applicationName,
            bundleIdentifier: activation.bundleIdentifier,
            shouldStop: { [clock] in clock.elapsed >= deadline }
        )
        switch outcome {
        case let .found(item): return .item(item)
        case .exhausted: return .failed
        case .nothing: return log.timedOut ? .failed : .nothing
        }
    }
}

/// Every message one read sends, and whether any of them timed out.
private final class MessageLog {
    private(set) var timedOut = false

    func copy(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        if result == .cannotComplete { timedOut = true }
        return result == .success ? value : nil
    }
}

/// One element of the frontmost window, as `SelectedItemSearch` sees it. Each property is one
/// or two messages to the other application, sent only when the search asks.
private struct WindowElement: SelectedItemNode {
    let element: AXUIElement
    let log: MessageLog

    var kind: SelectedItemNodeKind {
        switch log.copy(element, Attribute.role) as? String {
        case "AXOutline", "AXTable", "AXList": return .collection
        case "AXHeading": return .heading
        case "AXGroup":
            return log.copy(element, Attribute.subrole) as? String == "AXLandmarkMain" ? .mainRegion : .other
        default: return .other
        }
    }

    var children: [WindowElement] { elements(Attribute.children) }

    var selectedRows: [WindowElement] {
        let rows = elements(Attribute.selectedRows)
        return rows.isEmpty ? elements(Attribute.selectedChildren) : rows
    }

    var text: String? {
        for attribute in [Attribute.title, Attribute.value, Attribute.description] {
            if let text = log.copy(element, attribute) as? String,
               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return text
            }
        }
        return nil
    }

    private func elements(_ attribute: String) -> [WindowElement] {
        guard let found = log.copy(element, attribute) as? [AXUIElement] else { return [] }
        return found.map { child in
            AXUIElementSetMessagingTimeout(child, messagingTimeout)
            return WindowElement(element: child, log: log)
        }
    }
}
