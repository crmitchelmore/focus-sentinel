import Foundation

/// **The item a person has selected inside a mixed-use application** (issue #24, owner's ruling
/// 2026-10-15).
///
/// In GitHub Copilot, a terminal, an editor, the bundle identifier is the same for the task and
/// for the detour, so a question about the application asks about the wrong thing. This is the
/// narrower subject: the chat session, the project folder, the workspace, reduced from the
/// focused window's title to a short label.
///
/// ## What is kept, and what never is
///
/// The raw title is read on device, at judgement time, from the frontmost application only, and
/// it is handed to `normalise(title:applicationName:bundleIdentifier:)` and dropped. What
/// survives is `label`: one segment of the title, its punctuation removed, capped at
/// `maximumLabelLength` characters on a word boundary. Nothing else from the title reaches the
/// store, the export or a log. An export goes further and redacts even the label
/// (`StoreExport`), because a project name is the person's own material.
///
/// ## Why it lives here
///
/// `FocusCore` holds no Accessibility symbol (`check-boundaries.sh`). The reading is
/// `FocusHost.SystemSelectedItemReader`'s, the one file `Config/grant-use-sites.txt` registers;
/// the rule about what a title becomes is this pure function, so it is checkable without a Mac.
public struct SelectedItem: Sendable, Hashable, Codable, CustomStringConvertible {
    /// The application the item belongs to.
    public let bundleIdentifier: String
    /// The short, normalised name drawn in the question: letters, digits, spaces and `-_.`.
    public let label: String

    /// The separator between the bundle identifier and the label in a stored subject. A bundle
    /// identifier never contains it, and `label` cannot.
    public static let subjectSeparator = "::"

    /// The longest label kept. A label is a name, not a sentence.
    public static let maximumLabelLength = 48

    private init(validBundle bundleIdentifier: String, validLabel label: String) {
        self.bundleIdentifier = bundleIdentifier
        self.label = label
    }

    /// Build one from parts, or `nil` when either part does not survive normalisation.
    public init?(bundleIdentifier: String, label rawLabel: String) {
        let bundle = bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isBundleShaped(bundle), let label = Self.sanitise(rawLabel) else { return nil }
        self.init(validBundle: bundle, validLabel: label)
    }

    // MARK: - The stored form

    /// The rule subject an item is filed under: `<bundle>::<label>`, scope `.titleToken`.
    public var subject: String { bundleIdentifier + Self.subjectSeparator + label }

    /// The case-folded form the cascade matches on, so a title that only changed case is the
    /// same item.
    public var slug: NormalisedToken? {
        NormalisedToken.normalised(
            label.lowercased().split(separator: " ").joined(separator: "-")
        )
    }

    /// Read a stored subject back, or `nil` when it is not one this type wrote.
    ///
    /// Strict on purpose: the label must already be in normalised form, so a legacy title-token
    /// rule (a bare word) or a hand-edited row never reads as an item.
    public static func parse(_ subject: String) -> SelectedItem? {
        guard let range = subject.range(of: subjectSeparator) else { return nil }
        let bundle = String(subject[subject.startIndex..<range.lowerBound])
        let label = String(subject[range.upperBound...])
        guard isBundleShaped(bundle), sanitise(label) == label else { return nil }
        return SelectedItem(validBundle: bundle, validLabel: label)
    }

    /// Whether a stored subject is an item rather than a legacy word.
    public static func isItemSubject(_ subject: String) -> Bool {
        parse(subject) != nil
    }

    /// The same item: one application, one slug.
    public func matches(_ other: SelectedItem) -> Bool {
        bundleIdentifier == other.bundleIdentifier && slug != nil && slug == other.slug
    }

    public var description: String { subject }

    /// The label an export writes in place of every item's own: the application stays, the
    /// name the person's work goes by does not.
    public static let exportedLabel = "selected-item"

    /// **What an export writes for a stored subject.** An item subject keeps its application
    /// and loses its label; anything else passes through unchanged.
    public static func exportedSubject(_ subject: String) -> String {
        guard let item = parse(subject) else { return subject }
        return item.bundleIdentifier + subjectSeparator + exportedLabel
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case bundleIdentifier
        case label
    }

    /// Decoding re-runs the normalisation, so a stored value can never carry more than a label.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let bundle = try container.decode(String.self, forKey: .bundleIdentifier)
        let label = try container.decode(String.self, forKey: .label)
        guard let item = SelectedItem(bundleIdentifier: bundle, label: label), item.label == label else {
            throw DecodingError.dataCorruptedError(
                forKey: .label,
                in: container,
                debugDescription: "not a normalised selected item"
            )
        }
        self = item
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(bundleIdentifier, forKey: .bundleIdentifier)
        try container.encode(label, forKey: .label)
    }

    // MARK: - Which applications are read

    /// Which part of a window title names the item.
    public enum Segment: String, Sendable, Hashable, CaseIterable {
        /// The first segment that is not the application's own name.
        case first
        /// The last such segment — editors that put the open file first and the folder after.
        case last
    }

    /// **The applications whose window title may be read**, and where the item sits in it.
    ///
    /// Mixed-use tools only: places where one window holds several tasks. Browsers, Mail and
    /// Messages are deliberately absent — a page title or a subject line is somebody else's
    /// words, and the origin already narrows a browser (`.domain`). Adding an application here
    /// is adding a reading, and it is argued for in the same breath.
    public static let readableApplications: [String: Segment] = [
        "com.github.githubapp": .first,
        "com.microsoft.VSCode": .last,
        "com.todesktop.230313mzl4w4u92": .last,
        "com.apple.dt.Xcode": .first,
        "dev.zed.Zed": .first,
        "com.apple.Terminal": .first,
        "com.mitchellh.ghostty": .first,
        "com.googlecode.iterm2": .first,
        "com.microsoft.m365copilot": .first,
        "com.openai.chat": .first,
        "com.anthropic.claudefordesktop": .first,
    ]

    /// Whether this build may read the selected item of an application at all.
    public static func isReadable(_ bundleIdentifier: String) -> Bool {
        readableApplications[bundleIdentifier] != nil
    }

    // MARK: - Reduction

    /// The separators applications put between the parts of a window title.
    static let titleSeparators = [" — ", " – ", " - ", " | ", " · ", " ⸺ "]

    /// Segments that name a shell or a size rather than anything the person chose.
    static let uninformativeSegments: Set<String> = [
        "zsh", "-zsh", "bash", "-bash", "fish", "-fish", "sh", "login", "untitled", "welcome",
        "new chat", "new tab", "new window",
    ]

    /// **Reduce a window title to an item, then forget the title.**
    ///
    /// Splits on the usual separators, drops the application's own name, shells and terminal
    /// sizes, picks the segment the application's `Segment` names, reduces a path to its last
    /// component, and sanitises what is left. `nil` when nothing nameable survives, which is the
    /// common case for an application whose title is just its name.
    public static func normalise(
        title: String?,
        applicationName: String?,
        bundleIdentifier: String
    ) -> SelectedItem? {
        guard let segment = readableApplications[bundleIdentifier],
              let title, !title.isEmpty else { return nil }
        let appName = applicationName.map(fold)
        var parts = [title]
        for separator in titleSeparators {
            parts = parts.flatMap { $0.components(separatedBy: separator) }
        }
        let candidates = parts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { appName == nil || fold($0) != appName }
            .filter { !uninformativeSegments.contains(fold($0)) }
            .filter { !isTerminalSize($0) }
        let chosen: String?
        switch segment {
        case .first: chosen = candidates.first
        case .last: chosen = candidates.last
        }
        guard let chosen, let reduced = lastPathComponent(of: chosen) else { return nil }
        guard let item = SelectedItem(bundleIdentifier: bundleIdentifier, label: reduced) else {
            return nil
        }
        if let appName, fold(item.label) == appName { return nil }
        return item
    }

    /// The label a raw string sanitises to, or `nil` when nothing nameable is left.
    static func sanitise(_ raw: String) -> String? {
        let mapped = raw.map { character -> Character in
            if character.isLetter || character.isNumber { return character }
            if character == "-" || character == "_" || character == "." { return character }
            return " "
        }
        let words = String(mapped)
            .split(separator: " ", omittingEmptySubsequences: true)
            .map(String.init)
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "-_.")) }
            .filter { !$0.isEmpty }
        guard !words.isEmpty else { return nil }
        var label = ""
        for word in words {
            let candidate = label.isEmpty ? word : label + " " + word
            if candidate.count > maximumLabelLength {
                if label.isEmpty {
                    label = String(word.prefix(maximumLabelLength))
                        .trimmingCharacters(in: CharacterSet(charactersIn: "-_."))
                }
                break
            }
            label = candidate
        }
        return label.isEmpty ? nil : label
    }

    /// A path's last component; a bare home directory names nothing.
    private static func lastPathComponent(of segment: String) -> String? {
        guard segment.contains("/") || segment.hasPrefix("~") else { return segment }
        let trimmed = segment.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard trimmed != "~", !trimmed.isEmpty else { return nil }
        let last = trimmed.split(separator: "/").last.map(String.init) ?? trimmed
        return last == "~" ? nil : last
    }

    private static func isTerminalSize(_ segment: String) -> Bool {
        let parts = segment.split(whereSeparator: { $0 == "×" || $0 == "x" })
        return parts.count == 2 && parts.allSatisfy { $0.allSatisfy(\.isNumber) && !$0.isEmpty }
    }

    private static func isBundleShaped(_ candidate: String) -> Bool {
        !candidate.isEmpty
            && !candidate.contains(subjectSeparator)
            && !candidate.contains("://")
            && candidate.allSatisfy { !$0.isWhitespace }
    }

    private static func fold(_ string: String) -> String {
        string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
