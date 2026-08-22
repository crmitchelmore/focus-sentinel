import Foundation

/// The silhouette a status is drawn as.
///
/// Shape is a *second* channel alongside the SF Symbol, not decoration: a user who cannot
/// distinguish the symbols still has an outline that differs, and a component that has no
/// room for a glyph can fall back to the shape alone.
public enum StatusShape: String, Sendable, CaseIterable, Codable, Hashable {
    case circle
    case diamond
    case triangle
    case rectangle
    case capsule
}

/// The status token set: what the app can say about the user's current context.
///
/// Every case carries **three** independent channels — a distinct SF Symbol whose
/// silhouette differs from the others, a distinct shape token, and a distinct localised
/// short label. Colour is an *additional* channel and never the only one. Under
/// "Differentiate without colour" the label is always shown alongside the glyph, and sound
/// is never the sole alternative channel.
///
/// These tokens ship in e01, before anything consumes them, precisely so that the later
/// surfaces — the escalation ladder, the notch companion, the timeline — consume them
/// rather than inventing colour-only glyphs of their own.
public enum FocusStatus: String, Sendable, CaseIterable, Codable, Hashable {
    /// The observed context supports the current priority.
    case relevant
    /// There is not enough evidence to say. Never escalates, never nudges.
    case uncertain
    /// The observed context does not support the current priority.
    case unrelated
    /// The user paused the session, or nothing is being observed.
    case paused
    /// The user is on a deliberate break.
    case onBreak

    /// The SF Symbol drawn for this status. Silhouettes are deliberately unalike: a filled
    /// circle, a diamond, a triangle, a rectangle and a cup read differently at a glance
    /// even in monochrome at small sizes.
    public var symbolName: String {
        switch self {
        case .relevant: "checkmark.circle.fill"
        case .uncertain: "questionmark.diamond.fill"
        case .unrelated: "exclamationmark.triangle.fill"
        case .paused: "pause.rectangle.fill"
        case .onBreak: "cup.and.saucer.fill"
        }
    }

    /// The shape token, for surfaces that draw their own outline rather than a symbol.
    public var shape: StatusShape {
        switch self {
        case .relevant: .circle
        case .uncertain: .diamond
        case .unrelated: .triangle
        case .paused: .rectangle
        case .onBreak: .capsule
        }
    }

    /// The String Catalog key for this status's short label.
    ///
    /// Kept as a `String` because it is also what the lint and the catalog-completeness
    /// test compare against. The value the UI actually renders is `shortLabelResource`.
    public var shortLabelKey: String {
        switch self {
        case .relevant: "status.relevant.short"
        case .uncertain: "status.uncertain.short"
        case .unrelated: "status.unrelated.short"
        case .paused: "status.paused.short"
        case .onBreak: "status.break.short"
        }
    }

    /// The localised short label, as a resource the UI renders directly.
    ///
    /// Resolved against this package's own bundle, because the catalog that defines these
    /// keys ships with `FocusCore`, not with the app.
    public var shortLabelResource: LocalizedStringResource {
        LocalizedStringResource(
            String.LocalizationValue(shortLabelKey),
            bundle: .atURL(Bundle.module.bundleURL)
        )
    }

    /// The localised short label as a plain `String`.
    ///
    /// Used by the self-check (which serialises it to JSON) and by tests. Note that under
    /// `swift test` this returns the key itself, because SwiftPM copies String Catalogs
    /// instead of compiling them — see `LocalizationLane`.
    public var shortLabel: String {
        String(
            localized: String.LocalizationValue(shortLabelKey),
            bundle: .module,
            comment: "Short status label shown beside the status glyph"
        )
    }

    /// Whether this status permits the app to interrupt the user.
    ///
    /// Only `unrelated` does. `uncertain` explicitly does not: declining to decide can
    /// never become a reason to nudge.
    public var permitsIntervention: Bool {
        self == .unrelated
    }
}
