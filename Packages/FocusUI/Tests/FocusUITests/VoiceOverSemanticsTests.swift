import FocusCore
import Foundation
import SwiftUI
import Testing

@testable import FocusUI

/// **The VoiceOver semantics sweep** (F-144, e10 plan §9.1).
///
/// The Court verified that exposing this app's own UI needs no Accessibility grant, so the sweep
/// is a gate assertion rather than a manual lane. The trap the plan names is the word *every*:
///
/// > *Hostile criterion **H9.1**: the sweep iterates a literal array of surfaces, and a surface
/// > added in e11 or e12 does not join it. The fold must be over the surface **type**.*
///
/// So the enumeration below is `DecisionSurface.allCases` and `SettingsTab.allCases` through
/// **exhaustive switches**. A case added to either vocabulary does not silently miss the sweep: it
/// fails to compile until somebody describes it. The count is asserted against `allCases.count`
/// rather than against a number written here, so a case that is added and described still has to
/// be reached.
///
/// **What is swept is the source closure of each surface, not its own file.** A defect moved into
/// a shared component — the status badge, the capability table, the sensing rows — is a defect
/// that has left the file the sweep reads. The closure is the transitive set of FocusUI view types
/// the surface names, which is the same reachability-fixpoint discipline `check-strings.sh` applies
/// to catalog keys.
///
/// **Charts: there are none.** The plan asks for `accessibilityChartDescriptor` on e09's charts;
/// History ships as a ledger and no view in this package imports Swift Charts. `noChartsExistYet()`
/// below asserts that, so the day one arrives this suite goes red and the descriptor is written
/// with it rather than remembered.
@Suite("Every shipped surface is legible to VoiceOver", .serialized)
@MainActor
struct VoiceOverSemanticsTests {
    // MARK: - The vocabulary of surfaces, folded over the type

    /// Where a surface's announcement comes from.
    enum Announced {
        /// The surface composes its own sentence and draws it as the element's label.
        case own(String)
        /// The surface draws other decision surfaces and inherits theirs. The named surfaces must
        /// really be in its source closure, which is what stops this being an excuse.
        case inherited(from: [DecisionSurface])
    }

    struct Audited {
        let name: String
        /// Path under `Sources/FocusUI`, the root of the surface's source closure.
        let file: String
        let announced: Announced?
    }

    /// **Exhaustive.** A fourth `DecisionSurface` fails to compile here.
    static func audited(_ surface: DecisionSurface) -> Audited {
        switch surface {
        case .accusationPanel:
            Audited(
                name: surface.rawValue,
                file: "Nudge/AccusationPanelView.swift",
                announced: .own(AccusationFixture.rungTwo().announcement())
            )
        case .questionPanel:
            Audited(
                name: surface.rawValue,
                file: "Nudge/QueryPanelView.swift",
                announced: .own(QueryFixture.noNegativeBasis().announcement())
            )
        case .menuBarPopover:
            // The popover draws the same two views the panel does — the reuse is the point, so a
            // rung routed here is the same rung with the same actions and the same sentence.
            Audited(
                name: surface.rawValue,
                file: "MenuBar/MenuBarPopoverView.swift",
                announced: .inherited(from: [.accusationPanel, .questionPanel])
            )
        }
    }

    /// **Exhaustive.** A fourth `SettingsTab` fails to compile here.
    static func audited(_ tab: SettingsTab) -> Audited {
        switch tab {
        case .general:
            Audited(name: tab.rawValue, file: "Scenes/GeneralSettingsView.swift", announced: nil)
        case .intervention:
            Audited(
                name: tab.rawValue,
                file: "Scenes/InterventionSettingsView.swift",
                announced: nil
            )
        case .privacy:
            Audited(name: tab.rawValue, file: "Scenes/PrivacySettingsView.swift", announced: nil)
        case .tasks:
            Audited(name: tab.rawValue, file: "Tasks/TaskSettingsView.swift", announced: nil)
        }
    }

    static var surfaces: [Audited] {
        DecisionSurface.allCases.map(audited) + SettingsTab.allCases.map(audited)
    }

    // MARK: - The source closure

    /// `…/Packages/FocusUI/Sources/FocusUI`, found from this file rather than from a bundle: the
    /// sweep reads source, and a bundled copy would not be the tree the gate builds.
    static let sources: URL = URL(filePath: #filePath)
        .deletingLastPathComponent()      // …/Tests/FocusUITests
        .deletingLastPathComponent()      // …/Tests
        .deletingLastPathComponent()      // …/FocusUI
        .appending(path: "Sources/FocusUI", directoryHint: .isDirectory)

    static func swiftFiles() -> [URL] {
        guard
            let walk = FileManager.default.enumerator(
                at: sources,
                includingPropertiesForKeys: nil
            )
        else { return [] }
        return walk.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }.sorted {
            $0.path < $1.path
        }
    }

    /// Every `struct` FocusUI declares, and the file it lives in. Structs rather than every
    /// identifier, because a view in this package is always a struct and a name that is not a
    /// declared type cannot pull a file into the closure.
    static let declarations: [String: URL] = {
        var found: [String: URL] = [:]
        for file in swiftFiles() {
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                for prefix in ["struct ", "public struct ", "private struct ", "fileprivate struct "]
                where trimmed.hasPrefix(prefix) {
                    let rest = trimmed.dropFirst(prefix.count)
                    let name = String(
                        rest.prefix { $0.isLetter || $0.isNumber || $0 == "_" }
                    )
                    if let first = name.first, first.isUppercase, found[name] == nil {
                        found[name] = file
                    }
                }
            }
        }
        return found
    }()

    /// Comment-stripped source, so a type named only in a doc comment does not join a closure and
    /// an `Image(` in prose is not audited.
    static func code(of file: URL) -> [String] {
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return [] }
        return text.split(separator: "\n", omittingEmptySubsequences: false).map { line in
            let whole = String(line)
            guard let marker = whole.range(of: "//") else { return whole }
            return String(whole[whole.startIndex ..< marker.lowerBound])
        }
    }

    /// The transitive set of FocusUI files a surface draws through.
    static func closure(of relativePath: String) -> Set<URL> {
        let root = sources.appending(path: relativePath)
        var seen: Set<URL> = [root]
        var stack = [root]
        while let file = stack.popLast() {
            let text = code(of: file).joined(separator: "\n")
            for (name, target) in declarations where !seen.contains(target) {
                if text.contains(name) {
                    seen.insert(target)
                    stack.append(target)
                }
            }
        }
        return seen
    }

    // MARK: - Reading one file's drawing sites

    static let accessibilityDecisions = [
        "accessibilityLabel(", "accessibilityHidden(", "accessibilityElement(",
        "accessibilityValue("
    ]
    static let textSources = ["ShellText(", "Text(", "NudgeText(", "Label(", "ShellStrings."]
    static let controlKeywords = [
        "Button", "Toggle", "Picker", "Stepper", "TextField", "SecureField"
    ]

    static func indent(_ line: String) -> Int {
        line.count - line.drop(while: { $0 == " " }).count
    }

    /// The trailing modifier chain after a block closes — `.frame(…)` spread over four lines is
    /// still the same expression, and the `.accessibilityHidden(true)` after it is still this
    /// view's answer. Measured: without the paren-aware walk, `StatusBadge`'s hidden glyph reads
    /// as an undecided image.
    static func chain(from start: Int, in lines: [String]) -> Int {
        var index = start + 1
        var parens = 0
        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if parens == 0 && !trimmed.hasPrefix(".") { break }
            parens += line.filter { $0 == "(" }.count - line.filter { $0 == ")" }.count
            index += 1
        }
        return index
    }

    /// The smallest brace- and paren-balanced expression beginning at `start`, plus its chain.
    static func block(from start: Int, in lines: [String]) -> Range<Int> {
        var braces = 0
        var parens = 0
        var index = start
        while index < lines.count {
            let line = lines[index]
            braces += line.filter { $0 == "{" }.count - line.filter { $0 == "}" }.count
            parens += line.filter { $0 == "(" }.count - line.filter { $0 == ")" }.count
            if index > start && braces <= 0 && parens <= 0 { break }
            index += 1
        }
        return start ..< chain(from: min(index, lines.count - 1), in: lines)
    }

    /// The block that encloses line `index` — the nearest preceding line at a smaller indent that
    /// opens a brace and is not itself a continuation (`} label: {` is the *middle* of `Button`,
    /// not its start, and starting there would miss the label on the button).
    static func enclosing(_ index: Int, in lines: [String]) -> Int {
        let depth = indent(lines[index])
        var scan = index - 1
        while scan >= 0 {
            let line = lines[scan]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty, indent(line) < depth, trimmed.hasSuffix("{"),
               !trimmed.hasPrefix("}") {
                return scan
            }
            scan -= 1
        }
        return max(0, index - 1)
    }

    /// The name a line declares, if it declares a view member — `private var glyph: some View {`
    /// or `private func row(_:) -> some View {`.
    static func memberName(of line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasSuffix("{") || trimmed.contains("some View") else { return nil }
        for keyword in ["var ", "func "] {
            guard let range = trimmed.range(of: keyword) else { continue }
            let head = trimmed[trimmed.startIndex ..< range.lowerBound]
            guard head.allSatisfy({ $0.isLetter || $0 == " " || $0 == "@" }) else { continue }
            let name = String(
                trimmed[range.upperBound...].prefix { $0.isLetter || $0.isNumber || $0 == "_" }
            )
            return name.isEmpty ? nil : name
        }
        return nil
    }

    /// **Whether an image has been decided about, anywhere the decision could honestly live.**
    ///
    /// A glyph is very often drawn by a computed member and hidden at the *use* site, where the
    /// frame that sizes it is applied — `ContextChip`'s `glyph` is exactly that, and reading only
    /// the declaration reports a defect that is not there. So this walks outward: the innermost
    /// enclosing expression first, then its parents, and when it reaches the member declaration it
    /// follows the member's own use sites in the same file. It stops at the declaration rather than
    /// walking on into `body`, because a `.accessibilityElement(children: .contain)` three hundred
    /// lines away is not a decision about this image.
    static func imageIsDecided(at index: Int, in lines: [String]) -> Bool {
        var here = index
        for _ in 0 ..< 6 {
            let start = enclosing(here, in: lines)
            let text = lines[block(from: start, in: lines)].joined(separator: "\n")
            // `Label { … } icon: { Image(…) }` labels its own icon with its title: the image is
            // decorative *because* the sentence beside it is the element's name.
            if text.contains("Label {"), textSources.contains(where: { text.contains($0) }) {
                return true
            }
            let decisions = accessibilityDecisions.reduce(0) {
                $0 + text.components(separatedBy: $1).count - 1
            }
            let images = text.components(separatedBy: "Image(").count - 1
            if decisions >= images { return true }
            if let name = memberName(of: lines[start]) {
                return memberIsDecidedWhereItIsUsed(name, declaredAt: start, in: lines)
            }
            if start == here { return false }
            here = start
        }
        return false
    }

    /// Every use of a view member outside its own declaration, and whether the chain applied there
    /// carries an accessibility decision.
    static func memberIsDecidedWhereItIsUsed(
        _ name: String,
        declaredAt declaration: Int,
        in lines: [String]
    ) -> Bool {
        let span = block(from: declaration, in: lines)
        for (index, line) in lines.enumerated() where !span.contains(index) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed == name || trimmed.hasPrefix(name + "(") || trimmed.hasPrefix(name + ".")
            else { continue }
            let text = lines[index ..< chain(from: index, in: lines)].joined(separator: "\n")
            if accessibilityDecisions.contains(where: { text.contains($0) }) { return true }
        }
        return false
    }

    struct Finding: CustomStringConvertible {
        let kind: String
        let file: String
        let line: Int
        let text: String
        var description: String { "\(kind) \(file):\(line) — \(text)" }
    }

    struct Reading {
        var images = 0
        var controls = 0
        var findings: [Finding] = []
    }

    static func read(_ file: URL) -> Reading {
        let lines = code(of: file)
        var reading = Reading()
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if line.contains("Image(") {
                reading.images += 1
                if !imageIsDecided(at: index, in: lines) {
                    reading.findings.append(
                        Finding(
                            kind: "image",
                            file: file.lastPathComponent,
                            line: index + 1,
                            text: "\(trimmed) — no label, no accessibilityHidden, no Label title"
                        )
                    )
                }
            }

            if controlKeywords.contains(where: { trimmed.hasPrefix($0) && trimmed.count > $0.count })
                || controlKeywords.contains(where: { trimmed == $0 + " {" }) {
                reading.controls += 1
                let text = lines[block(from: index, in: lines)].joined(separator: "\n")
                let named = textSources.contains { text.contains($0) }
                    || text.contains("accessibilityLabel(")
                if !named {
                    reading.findings.append(
                        Finding(
                            kind: "control",
                            file: file.lastPathComponent,
                            line: index + 1,
                            text: "\(trimmed) — a control with nothing to call it"
                        )
                    )
                }
            }
        }
        return reading
    }

    // MARK: - The sweep

    /// **The fold.** Every decision surface and every settings pane, through its whole source
    /// closure: every control carries a label, and every image carries a label or is hidden.
    @Test("every control is named and every image is labelled or hidden, on every surface")
    func everySurfaceIsLegible() {
        var findings: [Finding] = []
        var images = 0
        var controls = 0
        var files: Set<URL> = []

        for surface in Self.surfaces {
            let closure = Self.closure(of: surface.file)
            #expect(
                closure.count >= 2,
                "\(surface.name): the source closure is \(closure.count) file(s) — it did not resolve"
            )
            files.formUnion(closure)
            for file in closure.sorted(by: { $0.path < $1.path }) {
                let reading = Self.read(file)
                images += reading.images
                controls += reading.controls
                findings.append(contentsOf: reading.findings)
            }
        }

        let report = findings.map(\.description).joined(separator: "\n")
        #expect(findings.isEmpty, "VoiceOver sweep findings:\n\(report)")

        // **The non-vacuity controls.** Every assertion above is satisfied by a sweep that read
        // nothing: an unresolved path, a closure of one file, a regex that matched no drawing
        // site. The floors are the measured counts at 9af6d0c, less a little headroom.
        #expect(files.count >= 16, "the sweep read \(files.count) files across all six surfaces")
        #expect(images >= 10, "the sweep found \(images) image sites")
        #expect(controls >= 20, "the sweep found \(controls) control sites")
    }

    /// The count is asserted against the vocabularies themselves, so a case that is added **and**
    /// described still has to be reached by the fold.
    @Test("the sweep folds over the surface type, not a list")
    func theFoldIsOverTheType() {
        #expect(
            Self.surfaces.count == DecisionSurface.allCases.count + SettingsTab.allCases.count
        )
        #expect(Set(Self.surfaces.map(\.name)).count == Self.surfaces.count)
        for surface in Self.surfaces {
            let file = Self.sources.appending(path: surface.file)
            #expect(
                FileManager.default.fileExists(atPath: file.path),
                "\(surface.name) names a source file that is not there: \(surface.file)"
            )
        }
    }

    /// **Every decision surface has an announcement**, and it is drawn.
    ///
    /// Asserting that an announcement API was *called* is not asserting that a person hears the
    /// right thing, so this asserts the string: that it exists, that it is prose and not a catalog
    /// key, and that the surface really hands it to the accessibility tree.
    @Test("every decision surface announces itself in words from the catalog")
    func everyDecisionSurfaceAnnouncesItself() {
        var sentences: [String] = []
        for surface in DecisionSurface.allCases {
            let audited = Self.audited(surface)
            let source = Self.code(of: Self.sources.appending(path: audited.file))
                .joined(separator: "\n")
            switch audited.announced {
            case .own(let sentence):
                sentences.append(sentence)
                #expect(!sentence.isEmpty, "\(audited.name) announces nothing")
                // A catalog that was copied rather than compiled resolves a key to itself, and a
                // sentence that is a key is a sentence nobody can hear.
                //
                // **Taken only where it can be true**, through the same `LocalizationLane` gate
                // every other localisation-dependent test in this package uses: `xcodebuild`
                // compiles the String Catalog and `swift test` copies it, so in the inner loop the
                // key echoes itself. The gate lane is `xcodebuild`, so the gate always takes this
                // branch; `StringCatalogTests` holds the same ground for every `ShellStringKey`.
                if LocalizationLane.catalogsAreCompiled {
                    #expect(
                        !NudgeCopyKey.allCases.contains { sentence.contains($0.rawValue) },
                        "\(audited.name)'s announcement carries a raw catalog key: \(sentence)"
                    )
                }
                #expect(
                    source.contains("announcement()"),
                    "\(audited.name) composes an announcement and never draws it"
                )
                #expect(
                    source.contains("accessibilityLabel("),
                    "\(audited.name)'s announcement reaches no accessibility label"
                )
            case .inherited(let parents):
                let closure = Self.closure(of: audited.file)
                for parent in parents {
                    let file = Self.sources.appending(path: Self.audited(parent).file)
                    #expect(
                        closure.contains(file),
                        """
                        \(audited.name) claims \(parent.rawValue)'s announcement and does not draw \
                        that surface at all
                        """
                    )
                }
                #expect(!parents.isEmpty)
            case nil:
                Issue.record("\(audited.name) is a decision surface with no announcement at all")
            }
        }
        // Two surfaces that announce the same thing are two surfaces one of which is misheard.
        #expect(Set(sentences).count == sentences.count, "two surfaces announce the same sentence")
    }

    /// **Chart descriptors: there are none to write.** History is a ledger and no view in this
    /// package draws a chart. The day one arrives, this goes red and the descriptor is written
    /// beside it rather than remembered.
    @Test("no view draws a chart, so no chart descriptor is owed")
    func noChartsExistYet() {
        let charting = Self.swiftFiles().filter { file in
            Self.code(of: file).contains { $0.trimmingCharacters(in: .whitespaces) == "import Charts" }
        }
        #expect(
            charting.isEmpty,
            """
            \(charting.map(\.lastPathComponent)) import Charts: F-144 asks for \
            accessibilityChartDescriptor on every chart, and this sweep does not check for one yet
            """
        )
    }
}
