import Foundation

/// Reduces a web URL to the only part of it this programme is allowed to keep.
///
/// **Standing condition 3: only normalised origins, never full URLs.** A path is a document
/// title, a query is a search term, a fragment is a position in a page, and a user-info
/// component is a credential. None of them may reach the store, and e02 is the first epic that
/// stores a URL at all — which is why this ships here rather than in e07, with a property test
/// over generated URLs asserting that none of those five components survives.
///
/// The result is `scheme://host` plus an explicit port when the URL carried one. Measured
/// (P-68):
///
/// * `https://Docs.Google.com/document/d/abc?x=1#y` → `https://docs.google.com`
/// * `http://localhost:3000/a/b` → `http://localhost:3000`
/// * `https://user:pw@example.co.uk:8443/p` → `https://example.co.uk:8443`
public enum OriginNormalizer {
    /// The normalised origin, or `nil` for anything that does not have one.
    ///
    /// A `file:` URL, a `mailto:` URL and a bare path have no host and therefore no origin.
    /// Returning `nil` rather than a best guess is what keeps a path out of the domain field.
    public static func normalize(_ url: URL) -> String? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        return normalize(components)
    }

    /// The same, for text that has not been through `URL` yet — a paste, a drop, a query item.
    public static func normalize(_ string: String) -> String? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let components = URLComponents(string: trimmed) else {
            return nil
        }
        return normalize(components)
    }

    private static func normalize(_ components: URLComponents) -> String? {
        guard let scheme = components.scheme?.lowercased(), !scheme.isEmpty,
              let host = components.host?.lowercased(), !host.isEmpty
        else { return nil }

        // Everything not named here is discarded by construction: `user`, `password`, `path`,
        // `query` and `fragment` are simply never read.
        if let port = components.port {
            return "\(scheme)://\(host):\(port)"
        }
        return "\(scheme)://\(host)"
    }

    /// Whether a string already *is* a normalised origin.
    ///
    /// Used by the store's own assertions and by the property test's idempotence check:
    /// normalising an origin must return that same origin.
    public static func isNormalized(_ string: String) -> Bool {
        normalize(string) == string
    }
}
