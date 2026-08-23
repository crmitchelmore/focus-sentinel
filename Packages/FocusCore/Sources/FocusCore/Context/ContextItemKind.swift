import Foundation

/// What a context item *is*.
///
/// Four kinds and no fifth (F-09, scope-trimmed by the Court): an application, a normalised
/// web origin, a keyword, and a file. People and project ontology are out.
///
/// `unknown` is not a fifth kind — it is what this build calls a stored value it does not
/// recognise. A row written by a later version must render as an inert chip, never be dropped
/// and never be crashed on, and carrying the original string is what lets the row survive a
/// round trip through an older build unharmed.
public enum ContextItemKind: Sendable, Equatable, Hashable {
    /// An application, identified by bundle identifier. Resolved to a real name and icon
    /// through `NSWorkspace` at the surface, with no grant.
    case app
    /// A web origin, already normalised to `scheme://host[:port]` — never a full URL, never a
    /// path, never a query (standing condition 3).
    case domain
    /// A single word or phrase the user considers on-topic.
    case keyword
    /// A file, held as a security-scoped bookmark. `value` is the path at the time of adding
    /// and is for display only: a path is not a file.
    case file
    /// A stored kind this build does not understand, carrying the string verbatim.
    case unknown(String)

    /// The four kinds this build can create. `unknown` is deliberately absent.
    public static let known: [ContextItemKind] = [.app, .domain, .keyword, .file]

    public init(rawValue: String) {
        switch rawValue {
        case "app": self = .app
        case "domain": self = .domain
        case "keyword": self = .keyword
        case "file": self = .file
        default: self = .unknown(rawValue)
        }
    }

    /// What is written to `ContextItem.kindRaw`. An unknown kind round-trips its own string.
    public var rawValue: String {
        switch self {
        case .app: "app"
        case .domain: "domain"
        case .keyword: "keyword"
        case .file: "file"
        case .unknown(let raw): raw
        }
    }

    public var isKnown: Bool {
        if case .unknown = self { return false }
        return true
    }

    /// The SF Symbol the chip draws.
    ///
    /// Silhouettes are deliberately unalike, for the same reason `FocusStatus`'s are: under
    /// "Differentiate without colour" the shape is what tells one chip from another.
    public var symbolName: String {
        switch self {
        case .app: "app.badge"
        case .domain: "globe"
        case .keyword: "text.quote"
        case .file: "doc"
        case .unknown: "questionmark.square.dashed"
        }
    }
}

extension FocusSchemaV2.ContextItem {
    /// The stored kind, decoded. An unrecognised string becomes `.unknown` carrying itself —
    /// a forward-compatible read, never a crash and never a silent drop.
    public var kind: ContextItemKind {
        get { ContextItemKind(rawValue: kindRaw) }
        set { kindRaw = newValue.rawValue }
    }
}
