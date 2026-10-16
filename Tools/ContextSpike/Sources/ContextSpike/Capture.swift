import AppKit
import ApplicationServices
import Foundation

/// Everything Accessibility gives up about one window, read without activating the app.
struct WindowCapture: Codable {
    let id: String
    let app: String
    let bundleID: String
    let title: String
    let document: String?
    let url: String?
    let focused: String?
    let text: String
    let nodes: Int
    let readMs: Double
}

enum AX {
    static func attribute(_ element: AXUIElement, _ name: String) -> AnyObject? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    static func string(_ element: AXUIElement, _ name: String) -> String? {
        switch attribute(element, name) {
        case let string as String: string
        case let url as URL: url.absoluteString
        default: nil
        }
    }

    static func children(_ element: AXUIElement) -> [AXUIElement] {
        (attribute(element, kAXChildrenAttribute) as? [AXUIElement]) ?? []
    }

    static func windows(pid: pid_t) -> [AXUIElement] {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 3)
        return (attribute(app, kAXWindowsAttribute) as? [AXUIElement]) ?? []
    }

    /// Depth-first in reading order, content first. Text inside a web area, a text area, a cell or
    /// a document layout goes first; toolbar, ribbon, status-bar and tab-strip text goes after it,
    /// and control labels (buttons, menus, sliders) are dropped. Exact repeats are dropped.
    /// Bounded by node count, not by time.
    static func read(window: AXUIElement, maxNodes: Int = 8000) -> (text: String, url: String?, nodes: Int) {
        let valueRoles: Set<String> = [
            "AXStaticText", "AXTextArea", "AXTextField", "AXCell", "AXHeading", "AXLink",
            "AXComboBox", "AXSearchField"
        ]
        let controlRoles: Set<String> = [
            "AXButton", "AXMenuButton", "AXPopUpButton", "AXCheckBox", "AXRadioButton", "AXMenuItem",
            "AXMenuBarItem", "AXSlider", "AXIncrementor", "AXDisclosureTriangle", "AXScrollBar",
            "AXValueIndicator", "AXSplitter", "AXImage", "AXRadioGroup"
        ]
        let contentRoles: Set<String> = ["AXWebArea", "AXTextArea", "AXLayoutArea", "AXTable", "AXCell", "AXDocument"]
        func isChrome(_ role: String, _ element: AXUIElement) -> Bool {
            if ["AXToolbar", "AXMenuBar", "AXTabGroup"].contains(role) { return true }
            let label = (string(element, kAXDescriptionAttribute) ?? "") + (string(element, kAXTitleAttribute) ?? "")
            return role == "AXGroup" && label.localizedCaseInsensitiveContains("status bar")
        }
        enum Zone { case content, neutral, chrome }
        var stack: [(AXUIElement, Zone)] = [(window, .neutral)]
        var seen = Set<String>()
        var content: [String] = [], neutral: [String] = [], chrome: [String] = []
        var url: String?
        var nodes = 0
        while let (element, inherited) = stack.popLast(), nodes < maxNodes {
            nodes += 1
            let role = string(element, kAXRoleAttribute) ?? ""
            if role == "AXWebArea", url == nil { url = string(element, "AXURL") }
            var zone = inherited
            if zone != .chrome, contentRoles.contains(role) { zone = .content }
            if zone != .content, isChrome(role, element) { zone = .chrome }
            if !controlRoles.contains(role) {
                var candidates: [String?] = [string(element, kAXTitleAttribute), string(element, kAXDescriptionAttribute)]
                if valueRoles.contains(role) { candidates.insert(string(element, kAXValueAttribute), at: 0) }
                for case let candidate? in candidates {
                    let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard trimmed.count > 1, seen.insert(trimmed).inserted else { continue }
                    switch zone {
                    case .content: content.append(trimmed)
                    case .neutral: neutral.append(trimmed)
                    case .chrome: chrome.append(trimmed)
                    }
                }
            }
            stack.append(contentsOf: children(element).reversed().map { ($0, zone) })
        }
        return ((content + neutral + chrome).joined(separator: "\n"), url, nodes)
    }

    /// The focused element, only when it sits in the captured window: an app's focus is usually
    /// in its frontmost window, which is not necessarily the one being judged.
    static func focusedSummary(pid: pid_t, window: AXUIElement) -> String? {
        let app = AXUIElementCreateApplication(pid)
        guard let focused = attribute(app, kAXFocusedUIElementAttribute) else { return nil }
        let element = focused as! AXUIElement
        guard let owner = attribute(element, kAXWindowAttribute), CFEqual(owner, window) else { return nil }
        let role = string(element, kAXRoleAttribute) ?? "?"
        let label = string(element, kAXTitleAttribute) ?? string(element, kAXDescriptionAttribute) ?? ""
        let value = string(element, kAXValueAttribute).map { String($0.prefix(300)) } ?? ""
        return [role, label, value].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

func capture(corpus: Corpus, to destination: URL) {
    guard AXIsProcessTrusted() else { fail("this process is not trusted for Accessibility") }
    var captures: [String: WindowCapture] = [:]
    for spec in corpus.windows {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: spec.bundleID).first else {
            print("MISSING \(spec.id): \(spec.bundleID) is not running"); continue
        }
        let started = ContinuousClock.now
        var found: WindowCapture?
        for window in AX.windows(pid: app.processIdentifier) {
            let title = AX.string(window, kAXTitleAttribute) ?? ""
            let document = AX.string(window, kAXDocumentAttribute)
            let isWeb = spec.url != nil
            if !isWeb, !title.contains(spec.match), !(document ?? "").removingPercentEncoding!.contains(spec.match) { continue }
            let read = AX.read(window: window)
            if isWeb, !(read.url ?? "").contains(spec.match) { continue }
            let elapsed = ContinuousClock.now - started
            found = WindowCapture(
                id: spec.id, app: app.localizedName ?? spec.app, bundleID: spec.bundleID, title: title,
                document: document, url: read.url, focused: AX.focusedSummary(pid: app.processIdentifier, window: window),
                text: read.text, nodes: read.nodes,
                readMs: Double(elapsed.components.seconds) * 1000 + Double(elapsed.components.attoseconds) / 1e15
            )
            break
        }
        if let found {
            captures[spec.id] = found
            print("ok \(spec.id): \(found.title.prefix(60)) — \(found.text.count) chars, \(found.nodes) nodes, \(Int(found.readMs)) ms")
        } else {
            print("MISSING \(spec.id): no window matching \(spec.match)")
        }
    }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    do { try encoder.encode(captures).write(to: destination) } catch { fail("write: \(error)") }
    print("wrote \(captures.count)/\(corpus.windows.count) captures to \(destination.path)")
}
