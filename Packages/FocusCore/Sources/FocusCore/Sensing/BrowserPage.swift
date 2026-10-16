import Foundation

/// An on-device page identity. Credentials, queries and fragments never survive the read.
/// Unlike an origin, its case-sensitive path identifies the content the person is judging.
public struct BrowserPage: Sendable, Hashable {
    public let identifier: String
    public let origin: String
    public let path: String

    public init?(_ rawURL: String) {
        guard rawURL.count <= 2048,
              !rawURL.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
              var parts = URLComponents(string: rawURL),
              let scheme = parts.scheme?.lowercased(),
              ["https", "http"].contains(scheme),
              let host = parts.host?.lowercased(), !host.isEmpty,
              let origin = OriginNormalizer.normalize(rawURL)
        else { return nil }
        parts.scheme = scheme
        parts.host = host
        parts.user = nil
        parts.password = nil
        parts.query = nil
        parts.fragment = nil
        // A literal star must not become the path-rule marker.
        let path = parts.percentEncodedPath.replacingOccurrences(of: "*", with: "%2A")
        parts.percentEncodedPath = path.isEmpty ? "/" : path
        guard let identifier = parts.string else { return nil }
        self.identifier = identifier
        self.origin = origin
        self.path = parts.percentEncodedPath
    }

    public enum Scope: Sendable, Equatable {
        case page, path, domain
    }

    /// Origins have no slash, pages do, and path rules end in the explicit `/*` marker.
    public static func scope(of subject: String) -> Scope? {
        if OriginNormalizer.isNormalized(subject),
           subject.hasPrefix("https://") || subject.hasPrefix("http://") { return .domain }
        if subject.hasSuffix("/*") {
            let base = String(subject.dropLast(2))
            guard let page = BrowserPage(base), page.identifier == base else { return nil }
            return .path
        }
        guard let page = BrowserPage(subject), page.identifier == subject else { return nil }
        return .page
    }

    /// Exact page, progressively broader path prefixes, then the whole host (never subdomains).
    public var answerSubjects: [String] {
        var subjects = [identifier]
        var prefix = path.hasSuffix("/") ? String(path.dropLast()) : path
        while !prefix.isEmpty {
            subjects.append(origin + prefix + "/*")
            guard let separator = prefix.lastIndex(of: "/") else { break }
            prefix = String(prefix[..<separator])
        }
        subjects.append(origin)
        return subjects
    }

    public func matches(_ subject: String) -> Bool {
        switch Self.scope(of: subject) {
        case .domain: return subject == origin
        case .page: return subject == identifier
        case .path:
            guard let prefix = BrowserPage(String(subject.dropLast(2))), prefix.origin == origin else {
                return false
            }
            return path == prefix.path || path.hasPrefix(prefix.path + "/")
        case nil: return false
        }
    }

    /// Only compared among matching rules at the same authority.
    public static func specificity(of subject: String) -> Int {
        switch scope(of: subject) {
        case .page: Int.max
        case .path: subject.count
        case .domain, nil: 0
        }
    }

    public static func displayName(for subject: String) -> String? {
        guard scope(of: subject) != nil, let separator = subject.range(of: "://") else { return nil }
        return String(subject[separator.upperBound...])
    }

    public static let browserApplications: Set<String> = [
        "com.apple.Safari", "com.apple.SafariTechnologyPreview",
        "com.google.Chrome", "com.google.Chrome.beta", "com.google.Chrome.canary",
        "org.chromium.Chromium", "org.mozilla.firefox", "org.mozilla.firefoxdeveloperedition",
        "org.mozilla.nightly", "com.microsoft.edgemac", "com.microsoft.edgemac.Beta",
        "com.brave.Browser", "company.thebrowser.Browser", "com.kagi.kagimacOS",
        "app.zen-browser.zen", "com.operasoftware.Opera", "com.vivaldi.Vivaldi",
    ]
}
