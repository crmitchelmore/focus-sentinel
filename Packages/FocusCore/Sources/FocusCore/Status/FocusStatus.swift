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
/// Every case carries **three** independent channels — a distinct mark whose silhouette differs
/// from the others, a distinct shape token, and a distinct localised short label. Colour is an
/// *additional* channel and never the only one. Under "Differentiate without colour" the label is
/// always shown alongside the glyph, and sound is never the sole alternative channel.
///
/// The mark was an SF Symbol until e11b and is now the app's own drawn family
/// (`markAssetName`), with the SF Symbol kept as `fallbackSymbolName`. What changed is the
/// evidence, not the doctrine: "the silhouettes are unalike" used to be a sentence in this
/// comment and is now a floor a gate stage holds.
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

    /// **The app's own mark for this status, as an asset name.**
    ///
    /// e11b replaced the SF Symbols with a drawn family (focus-w41, direction §1.2): one ring —
    /// the app icon's own mark — with the **outline broken** differently for each state, rather
    /// than a dot moved inside a constant one. At 16 pt in monochrome, with Differentiate Without
    /// Colour on, an internal dot's position is a far weaker signal than a discontinuity, and
    /// "silhouettes are deliberately unalike" is now a *number*: `scripts/glyph-distance.py`
    /// renders all ten images the menu bar can draw, blurs them, and holds every pair above a
    /// committed floor.
    ///
    /// A **name**, not an image. `FocusCore` imports Foundation and may not name `NSImage`; the
    /// catalogue lives in `FocusUI`, which owns every pixel this app draws. So the status stays a
    /// value that says which mark it is, and `StatusMark` in `FocusUI` is what turns the name
    /// into ink.
    ///
    /// Undotted and capitalised on purpose: `check-strings.sh` keys its "this looks like a
    /// catalogue key" heuristic on dotted names under a known namespace, and an asset called
    /// `status.relevant.mark` would be hunted for in a String Catalog for ever.
    public var markAssetName: String {
        switch self {
        case .relevant: "StatusMarkRelevant"
        case .uncertain: "StatusMarkUncertain"
        case .unrelated: "StatusMarkUnrelated"
        case .paused: "StatusMarkPaused"
        case .onBreak: "StatusMarkOnBreak"
        }
    }

    /// The SF Symbol this status used to be drawn as, kept as a **fallback and a reading**.
    ///
    /// Not dead code and not nostalgia. Two things still want it: the `--focus-self-check`
    /// report, which has published a `symbol` per status since e01 and whose readers compare the
    /// five for distinctness; and any surface that has no asset catalogue to resolve against —
    /// a name is portable in a way an asset is not.
    ///
    /// Renamed rather than left as `symbolName`, because a property called that would go on
    /// being reached for by the next surface that needs a glyph, and the whole point of the
    /// family is that there is one mark per state and it is the app's.
    public var fallbackSymbolName: String {
        switch self {
        case .relevant: "checkmark.circle.fill"
        case .uncertain: "questionmark.diamond.fill"
        case .unrelated: "exclamationmark.triangle.fill"
        case .paused: "pause.rectangle.fill"
        case .onBreak: "cup.and.saucer.fill"
        }
    }

    /// The String Catalog key for **what this mark looks like, said in words**.
    ///
    /// An SF Symbol carries an accessibility description the system wrote; a drawn asset carries
    /// nothing at all. That loss is named in the direction (§5.2 item 5) and this is where it is
    /// paid back — one authored sentence per state, in the catalogue, rather than a filename
    /// read aloud.
    ///
    /// It is **not** the short label. `shortLabelKey` is the status's *name* — the word beside
    /// the glyph in a badge that already says it in text. This is the *image's* description, and
    /// the surface that needs it is the menu bar, where the mark is the entire content and there
    /// is no label anywhere near it.
    public var markDescriptionKey: String {
        switch self {
        case .relevant: "status.mark.relevant"
        case .uncertain: "status.mark.uncertain"
        case .unrelated: "status.mark.unrelated"
        case .paused: "status.mark.paused"
        case .onBreak: "status.mark.break"
        }
    }

    /// The localised mark description, as a resource the UI renders directly.
    public var markDescriptionResource: LocalizedStringResource {
        LocalizedStringResource(
            String.LocalizationValue(markDescriptionKey),
            bundle: .atURL(Bundle.module.bundleURL)
        )
    }

    /// The localised mark description as a plain `String`.
    ///
    /// Used where AppKit wants a `String` — `NSImage.accessibilityDescription` — and by the
    /// self-check. Under `swift test` this returns the key itself, for `shortLabel`'s reason.
    public var markDescription: String {
        String(
            localized: String.LocalizationValue(markDescriptionKey),
            bundle: .module,
            comment: "What the status mark looks like, for a reader who cannot see it"
        )
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
