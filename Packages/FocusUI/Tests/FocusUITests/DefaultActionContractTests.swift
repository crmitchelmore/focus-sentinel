import Foundation
import SwiftUI
import Testing

@testable import FocusUI

/// Where a bare Return is allowed to go — and, far more importantly, where it is not.
///
/// ## The defect this suite exists to stop coming back
///
/// `CockpitView` bound its Complete button to `.keyboardShortcut(.defaultAction)` whenever the
/// capture field was closed. A window default button collects every Return that no focused
/// field claimed, so the sequence a person actually performs — type the one thing, press
/// Return to commit it — left the capture field closed with Complete promoted to default, and
/// the *next* Return opened the completion sheet. Inside that sheet Complete is itself the
/// default action and is enabled with both fields empty, so one further Return finished the
/// priority with nothing recorded about it.
///
/// This was measured, not imagined: the live evidence lane pressed Return twice after capture
/// and both `cockpit-priority.png` and `context-chips.png` came back as byte-identical
/// pictures of the "Finish this priority" sheet.
///
/// `CommandRegistry` had already written the rule — Complete Priority is ⌃⌘⏎ and deliberately
/// not ⌘⏎, because "finishing the thing you are working on must not be one modifier away from
/// typing" — and the cockpit's binding contradicted it. So:
///
/// * **A non-modal window declares no default action.** The cockpit is full of text fields;
///   Return belongs to whichever one has focus.
/// * **A modal surface may declare one**, because the person opened it on purpose and Escape
///   is always beside it. Where the modal's outcome is destructive — the handoff sheet, which
///   gives away the priority already in hand — the default is *Cancel*.
///
/// The check is a scan of the package's own sources, the same mechanism `TypeHierarchyTests`
/// uses to keep the hero to one use site: the question is about what the views *declare*, and
/// no runtime assertion can see a key equivalent that has not been registered with a window.
@Suite("Default-action contract")
struct DefaultActionContractTests {
    // MARK: - The allowlist

    /// Every file permitted to bind `.defaultAction`, and why.
    ///
    /// Adding a file here is a deliberate act with an argument attached. Adding one *without*
    /// coming here fails `defaultActionsAreConfinedToTheAllowlist` below.
    static let allowed: [String: String] = [
        "CompletionSheet.swift":
            "a modal sheet the user opened on purpose; Escape cancels it and nothing is lost",
        "HandoffConfirmationSheet.swift":
            "the default is Cancel, never Replace — Return must not give away the current priority",
        "PrivacySettingsView.swift":
            "a settings pane whose one action reveals a folder in Finder and changes nothing",
        "InterruptionSheet.swift":
            "a modal sheet the user opened by pressing Stop; Escape keeps the session going, and Stop is enabled with every field empty because reflection is offered rather than extracted",
        "StoreUnavailableSheet.swift":
            "a modal sheet the app raised because the store did not open, with one action and no Escape: Return means \"I have read this\", and there is nothing to lose by pressing it because there is nothing being saved (focus-tzj.4)",
        "FirstRunSheet.swift":
            "a modal sheet the app raised on the first launch against a store, with one action and no Escape: Return means \"I have read this\", and there is nothing to lose by pressing it because the sheet holds no field and changes nothing (focus-odz.7)"
    ]

    /// The surface the whole defect ran through. Named separately from the allowlist so the
    /// failure message can say what goes wrong rather than just "unexpected file".
    static let forbiddenFile = "CockpitView.swift"

    // MARK: - The scan

    @Test("no non-modal surface claims the bare Return key")
    func defaultActionsAreConfinedToTheAllowlist() throws {
        let sites = try Self.defaultActionSites()

        #expect(!sites.isEmpty, "the scan found nothing at all, so it is proving nothing")

        let files = Set(sites.map(\.file))
        let unexpected = files.subtracting(Self.allowed.keys)

        let unexpectedNames = unexpected.sorted().joined(separator: ", ")
        #expect(
            unexpected.isEmpty,
            """
            \(unexpectedNames) bind .defaultAction. A bare Return must reach a modal surface \
            the user opened on purpose, never a window full of text fields — see this suite's \
            documentation for the measured failure.
            """
        )

        // The other direction: an allowlist entry whose reason has expired is an exemption
        // outliving its argument, which is how the next one gets waved through.
        let stale = Set(Self.allowed.keys).subtracting(files)
        let staleNames = stale.sorted().joined(separator: ", ")
        #expect(
            stale.isEmpty,
            """
            \(staleNames) no longer bind .defaultAction; remove the allowlist entry rather \
            than leaving a standing permission behind.
            """
        )
    }

    @Test("the cockpit binds no default action at all")
    func theCockpitClaimsNoReturnKey() throws {
        let sites = try Self.defaultActionSites().filter { $0.file == Self.forbiddenFile }

        let where_ = sites.map(\.description).joined(separator: ", ")
        #expect(
            sites.isEmpty,
            """
            \(Self.forbiddenFile) binds .defaultAction at \(where_). The cockpit is a \
            non-modal window whose Return commits the focused field. A window default button \
            collects the Returns no field claimed, which is how a second press after capture \
            reached Complete Priority and opened the completion sheet.
            """
        )
    }

    // MARK: - The same rule, stated in the models the views are built from

    @Test("the cockpit's focus contract declares no default field")
    func theCockpitContractDeclaresNoDefault() {
        #expect(FocusTraversal.contract(for: .cockpit).defaultField == nil)
    }

    @Test("completing is never reachable by an unmodified keystroke")
    func completionAlwaysCostsAModifier() throws {
        let complete = try #require(CommandRegistry.shell.action(id: "priority.complete"))
        let shortcut = try #require(complete.shortcut)

        #expect(shortcut.character == "\r")
        // Two modifiers, and control among them. ⌘⏎ alone is one slip away from ⏎ on a
        // keyboard where the hand is already on the command key.
        #expect(shortcut.modifiers.contains(.command))
        #expect(shortcut.modifiers.contains(.control))
        #expect(
            !shortcut.modifiers.isEmpty,
            "Complete Priority must never be an unmodified Return"
        )
    }

    @Test("the handoff sheet's default action is the one that changes nothing")
    func theHandoffDefaultIsCancel() {
        // The one modal in the app whose confirming button is destructive. Return lands on
        // Cancel there, and `HandoffConfirmationSheet` binds `.defaultAction` to the Cancel
        // button for exactly that reason.
        #expect(FocusTraversal.contract(for: .handoffConfirm).defaultField == .handoffCancel)
        #expect(FocusTraversal.contract(for: .handoffConfirm).cancel == .dismissWindow)
    }

    @Test("every surface that claims Return also offers a way out that changes nothing")
    func modalDefaultsAlwaysHaveAnEscape() {
        for contract in FocusTraversal.surfaces where contract.defaultField != nil {
            #expect(
                contract.cancel == .dismissWindow,
                "\(contract.surface.rawValue) binds Return but Escape does nothing in it"
            )
        }
    }

    // MARK: - Scanning the package's own sources

    struct Site: CustomStringConvertible {
        let file: String
        let line: Int

        var description: String { "\(file):\(line)" }
    }

    /// `FocusUI`'s source directory, found from this file: the question is about the sources,
    /// and a test bundle does not contain them.
    static var sourceDirectory: URL {
        URL(filePath: #filePath)
            .deletingLastPathComponent()   // …/Tests/FocusUITests
            .deletingLastPathComponent()   // …/Tests
            .deletingLastPathComponent()   // …/FocusUI
            .appending(path: "Sources", directoryHint: .isDirectory)
            .appending(path: "FocusUI", directoryHint: .isDirectory)
    }

    static let defaultActionReference = try! NSRegularExpression(pattern: #"\.defaultAction\b"#)

    static func defaultActionSites() throws -> [Site] {
        var sites: [Site] = []
        let enumerator = FileManager.default.enumerator(
            at: sourceDirectory,
            includingPropertiesForKeys: nil
        )
        let files = (enumerator?.allObjects as? [URL] ?? [])
            .filter { $0.pathExtension == "swift" }

        #expect(!files.isEmpty, "no sources found at \(sourceDirectory.path(percentEncoded: false))")

        for file in files.sorted(by: { $0.path < $1.path }) {
            let text = try String(contentsOf: file, encoding: .utf8)
            for (offset, line) in text.split(
                separator: "\n",
                omittingEmptySubsequences: false
            ).enumerated() {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                // Documentation naming the rule is not a binding of it.
                if trimmed.hasPrefix("//") || trimmed.hasPrefix("*") || trimmed.hasPrefix("/*") {
                    continue
                }
                let lineText = String(line)
                let range = NSRange(lineText.startIndex..<lineText.endIndex, in: lineText)
                if defaultActionReference.firstMatch(in: lineText, range: range) != nil {
                    sites.append(Site(file: file.lastPathComponent, line: offset + 1))
                }
            }
        }
        return sites
    }
}
