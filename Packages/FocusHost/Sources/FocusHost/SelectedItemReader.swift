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
    /// switched the Accessibility ask on, macOS has not granted it, or the focused document,
    /// selected row, main heading and window title identify no usable content.
    func selectedItem(in activation: ClearedActivation, optIns: GrantOptIns) -> SelectedItem?

    /// How many reads reached the Accessibility API.
    var readCount: Int { get }

    /// A read of `activation`'s focused window for the opt-in remote judge, or `nil` when the
    /// person has not switched the Accessibility ask on or macOS has not granted it. The read
    /// itself is returned rather than run, so the caller can run it off the main actor; it reads
    /// the window as it is when called.
    func windowContentRead(
        in activation: ClearedActivation,
        optIns: GrantOptIns
    ) -> (@Sendable () -> RemoteWindowContext?)?
}

extension SelectedItemReading {
    /// Doubles read nothing for the remote judge unless they say otherwise.
    func windowContentRead(
        in activation: ClearedActivation,
        optIns: GrantOptIns
    ) -> (@Sendable () -> RemoteWindowContext?)? { nil }
}

/// How long one Accessibility message may block the main actor. A hung application must not hang
/// this one: past this, the read gives up without inventing an app-wide question.
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
    static let document = "AXDocument"
    static let url = "AXURL"
    static let hidden = "AXHidden"
    static let focusedUIElement = "AXFocusedUIElement"
    static let window = "AXWindow"
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
///   is a `SelectedItem`: a short, sanitised name or an HTTP(S) page with credentials, query
///   and fragment discarded. Browser paths remain on device and are redacted from exports.
/// * **Bounded.** One message may block for `messagingTimeout`; a walk below the title reads at
///   most `SelectedItemSearch.maximumElements` elements and stops at `searchBudget`.
/// * **On device, with one opt-in exception.** This file imports no networking API, and a
///   `SelectedItem` is never sent anywhere. `windowContentRead` is the exception: when someone
///   configured the remote judge (`RemoteJudgeConfiguration`, off by default), it reads the
///   focused window's title, file, web address and text — bounded by `WindowContentWalk` — for
///   `DecisionOneJudge` to send once, unstored. It is reached only through
///   `RemoteJudgeContextSource`, which hands it a cleared activation that is still frontmost.
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
        let reading = read(activation)
        if BrowserPage.browserApplications.contains(activation.bundleIdentifier) {
            // A failed tab read must not teach a rule about the previously open page.
            grace.clear()
            if case let .item(item) = reading { return item }
            return nil
        }
        return grace.resolve(reading, pid: activation.pid, now: clock.elapsed)
    }

    /// How many window-content reads were handed out for the remote judge. Zero on a default
    /// install, where nothing configures one.
    private(set) var windowContentReadCount = 0

    func windowContentRead(
        in activation: ClearedActivation,
        optIns: GrantOptIns
    ) -> (@Sendable () -> RemoteWindowContext?)? {
        guard optIns.isEnabled(.accessibilityWindowContext), AXIsProcessTrusted() else { return nil }
        windowContentReadCount += 1
        let pid = activation.pid
        let bundleIdentifier = activation.bundleIdentifier
        let applicationName = NSRunningApplication(processIdentifier: pid)?.localizedName
        return {
            WindowContentWalk.read(pid: pid, bundleIdentifier: bundleIdentifier, applicationName: applicationName)
        }
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

        if let url = log.copy(window, Attribute.document) as? String,
           let page = BrowserPage(url),
           let item = SelectedItem(bundleIdentifier: activation.bundleIdentifier, browserPage: page) {
            return .item(item)
        }
        if BrowserPage.browserApplications.contains(activation.bundleIdentifier) {
            let deadline = clock.elapsed + Self.searchBudget
            guard let page = SelectedItemSearch.browserPage(
                from: WindowElement(element: window, log: log),
                shouldStop: { [clock] in clock.elapsed >= deadline }
            ), let item = SelectedItem(bundleIdentifier: activation.bundleIdentifier, browserPage: page)
            else { return .nothing }
            return .item(item)
        }

        // The view's selection or main heading is more specific than a shared window title.
        let deadline = clock.elapsed + Self.searchBudget
        let outcome = SelectedItemSearch.search(
            from: WindowElement(element: window, log: log),
            applicationName: applicationName,
            bundleIdentifier: activation.bundleIdentifier,
            shouldStop: { [clock] in clock.elapsed >= deadline }
        )
        switch outcome {
        case let .found(item): return .item(item)
        case .exhausted, .nothing:
            if let item = SelectedItem.normalise(
                title: log.copy(window, Attribute.title) as? String,
                applicationName: applicationName,
                bundleIdentifier: activation.bundleIdentifier
            ) {
                return .item(item)
            }
            return log.timedOut ? .failed : .nothing
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
        case "AXWebArea": return .webArea
        case "AXGroup":
            return log.copy(element, Attribute.subrole) as? String == "AXLandmarkMain" ? .mainRegion : .other
        default: return .other
        }
    }

    var children: [WindowElement] { elements(Attribute.children) }

    var documentURL: String? {
        if log.copy(element, Attribute.hidden) as? Bool == true { return nil }
        for attribute in [Attribute.url, Attribute.document] {
            let value = log.copy(element, attribute)
            if let url = value as? URL { return url.absoluteString }
            if let string = value as? String { return string }
        }
        return nil
    }

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

/// **The remote judge's read of one window** — the ContextSpike's `full` capture, bounded.
///
/// Depth-first in reading order, content first: text inside a web area, a text area, a cell or
/// a document layout goes first; toolbar, tab-strip and status-bar text after it; control labels
/// (buttons, menus, sliders) are dropped, and exact repeats are dropped. Run off the main actor,
/// and stopped by whichever comes first of `maximumElements`, `budget` and enough text.
enum WindowContentWalk {
    /// The spike read up to 8,000 elements with no clock. A judgement is worth less than that on
    /// a person's machine, so the walk stops sooner and says so with "(truncated)".
    static let maximumElements = 4_000
    static let budget: Duration = .milliseconds(1_500)

    private static let valueRoles: Set<String> = [
        "AXStaticText", "AXTextArea", "AXTextField", "AXCell", "AXHeading", "AXLink",
        "AXComboBox", "AXSearchField",
    ]
    private static let controlRoles: Set<String> = [
        "AXButton", "AXMenuButton", "AXPopUpButton", "AXCheckBox", "AXRadioButton", "AXMenuItem",
        "AXMenuBarItem", "AXSlider", "AXIncrementor", "AXDisclosureTriangle", "AXScrollBar",
        "AXValueIndicator", "AXSplitter", "AXImage", "AXRadioGroup",
    ]
    private static let contentRoles: Set<String> = [
        "AXWebArea", "AXTextArea", "AXLayoutArea", "AXTable", "AXCell", "AXDocument",
    ]
    private static let chromeRoles: Set<String> = ["AXToolbar", "AXMenuBar", "AXTabGroup"]

    private enum Zone { case content, neutral, chrome }

    static func read(pid: pid_t, bundleIdentifier: String, applicationName: String?) -> RemoteWindowContext? {
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, messagingTimeout)
        let log = MessageLog()
        guard let windowValue = log.copy(application, Attribute.focusedWindow),
              CFGetTypeID(windowValue) == AXUIElementGetTypeID()
        else { return nil }
        // swiftlint:disable:next force_cast
        let window = windowValue as! AXUIElement

        let document = string(log.copy(window, Attribute.document))
        var webAddress = RemoteWindowContext.reducedWebAddress(document)
        let deadline = ContinuousClock.now + budget
        let enough = RemoteWindowContext.maximumTextLength * 2

        var stack: [(AXUIElement, Zone)] = [(window, .neutral)]
        var seen = Set<String>()
        var content: [String] = [], neutral: [String] = [], chrome: [String] = []
        var collected = 0
        var visited = 0
        while let (element, inherited) = stack.popLast(),
              visited < maximumElements, collected < enough, ContinuousClock.now < deadline {
            visited += 1
            let role = string(log.copy(element, Attribute.role)) ?? ""
            if role == "AXWebArea", webAddress == nil {
                webAddress = RemoteWindowContext.reducedWebAddress(string(log.copy(element, Attribute.url)))
            }
            var zone = inherited
            if zone != .chrome, contentRoles.contains(role) { zone = .content }
            if zone != .content, isChrome(role, element, log) { zone = .chrome }
            if !controlRoles.contains(role) {
                var candidates = [Attribute.title, Attribute.description]
                if valueRoles.contains(role) { candidates.insert(Attribute.value, at: 0) }
                for attribute in candidates {
                    guard let text = string(log.copy(element, attribute))?
                        .trimmingCharacters(in: .whitespacesAndNewlines),
                        text.count > 1, seen.insert(text).inserted
                    else { continue }
                    collected += text.count
                    switch zone {
                    case .content: content.append(text)
                    case .neutral: neutral.append(text)
                    case .chrome: chrome.append(text)
                    }
                }
            }
            let children = (log.copy(element, Attribute.children) as? [AXUIElement]) ?? []
            for child in children.reversed() {
                AXUIElementSetMessagingTimeout(child, messagingTimeout)
                stack.append((child, zone))
            }
        }

        return RemoteWindowContext(
            applicationName: applicationName,
            bundleIdentifier: bundleIdentifier,
            title: string(log.copy(window, Attribute.title)),
            webAddress: webAddress,
            openFile: RemoteWindowContext.filePath(fromDocument: document),
            focused: focusedSummary(application: application, window: window, log: log),
            text: (content + neutral + chrome).joined(separator: "\n")
        )
    }

    private static func isChrome(_ role: String, _ element: AXUIElement, _ log: MessageLog) -> Bool {
        if chromeRoles.contains(role) { return true }
        guard role == "AXGroup" else { return false }
        let label = (string(log.copy(element, Attribute.description)) ?? "")
            + (string(log.copy(element, Attribute.title)) ?? "")
        return label.localizedCaseInsensitiveContains("status bar")
    }

    /// The focused element, only when it sits in the focused window.
    private static func focusedSummary(application: AXUIElement, window: AXUIElement, log: MessageLog) -> String? {
        guard let focusedValue = log.copy(application, Attribute.focusedUIElement),
              CFGetTypeID(focusedValue) == AXUIElementGetTypeID()
        else { return nil }
        // swiftlint:disable:next force_cast
        let focused = focusedValue as! AXUIElement
        guard let owner = log.copy(focused, Attribute.window), CFEqual(owner, window) else { return nil }
        let role = string(log.copy(focused, Attribute.role)) ?? "?"
        let label = string(log.copy(focused, Attribute.title))
            ?? string(log.copy(focused, Attribute.description)) ?? ""
        let value = string(log.copy(focused, Attribute.value)).map { String($0.prefix(300)) } ?? ""
        return [role, label, value].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private static func string(_ value: CFTypeRef?) -> String? {
        switch value {
        case let string as String: string
        case let url as URL: url.absoluteString
        default: nil
        }
    }
}
