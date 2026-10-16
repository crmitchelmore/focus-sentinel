import Foundation

/// **What a nudge is about, in the two halves that must never be confused** (focus-ebv).
///
/// ## The conflation this type exists to end
///
/// `FrontmostActivation.localizedName` carries a true and load-bearing warning: it is *"never as
/// a rule subject, because a rule keyed on a display name is not a rule"*. That is correct
/// doctrine about the **storage key** — a rule, a receipt, a snooze and a budget row are all
/// keyed on the bundle identifier, and keying any of them on a name a person can change in the
/// Finder would be keying them on nothing. e05 applied it to the **sentence** as well, and the
/// sentence is the one place it does not belong: what shipped was
/// *"Is com.figma.Desktop part of Write the Q3 proposal?"* on four user-visible surfaces, one of
/// them directly under a button reading *"Back to Pages"* — the same panel naming the same kind
/// of thing two ways, three lines apart.
///
/// e02 had already solved it and the fix is its shape: `ContextItemValue` carries `value` **and**
/// `displayName`, which is why `contextPack.dark.standard.png` renders *"Safari"* on the chip
/// row while the nudge beside it rendered *"com.apple.Safari"*.
///
/// So a nudge subject is a pair:
///
/// | half | what it is | who reads it |
/// |---|---|---|
/// | `identifier` | the bundle identifier or normalised `scheme://host[:port]` origin | every rule, receipt, snooze and budget key. Never a sentence |
/// | `displayName` | what the application calls itself | every sentence. Never a key |
///
/// ## `displayName` is never empty, and the fallback is the identifier
///
/// A nudge that renders an empty string is worse than one that renders an identifier: the
/// identifier is ugly and the empty string is a bug the person is asked to answer. Every route
/// through `named(_:runningName:)` therefore ends at a non-empty string, and the last resort is
/// `identifier` itself.
///
/// *"Back to …"* is drawn from the same function rather than from a copy of the rule
/// (focus-7gc). It was cited here as the exemplar while it was in fact the unrepaired surface:
/// `ReturnTarget.displayName` fell straight to the identifier for anything not running, so the
/// button read *"Back to com.apple.Safari"* under a sentence that said *"Safari"*. A rule
/// justified by pointing at a second copy of itself is a rule with one place left to drift.
///
/// ## There is no public initialiser
///
/// The memberwise one is `fileprivate` and this file holds the only two functions that call it,
/// so the two halves cannot be filled in at a call site that has not thought about which is
/// which — the mistake being repaired here is precisely a call site passing the key where the
/// name goes. `check-forbidden.sh` asserts the count (R-96o).
public struct NudgeSubject: Sendable, Equatable, Hashable {
    /// **The storage key.** A bundle identifier or a normalised `scheme://host[:port]` origin,
    /// trimmed and never empty. Everything the person's answer writes is keyed on this.
    public let identifier: String
    /// **What the sentence says.** The application's localised name where the app could supply
    /// one, the host for an origin, and the identifier when there is nothing better. Never
    /// empty.
    public let displayName: String

    /// **Fileprivate on purpose.** `named(_:runningName:)` and `of(_:runningName:)` below are
    /// the only callers in the programme.
    fileprivate init(identifier: String, displayName: String) {
        self.identifier = identifier
        self.displayName = displayName
    }

    /// Whether this subject is an origin rather than an application.
    ///
    /// `OriginNormalizer` emits `scheme://host[:port]` and nothing else does, so the separator is
    /// a reliable discriminator — the same one `QuerySubject.kind(of:)` decides `.domain` by, and
    /// it now decides it *by calling this*, so the two cannot drift apart.
    public static func isOrigin(_ identifier: String) -> Bool { identifier.contains("://") }

    /// Whether this subject is an item selected inside an application (issue #24), which the
    /// question panel words as an item rather than as an app. A property rather than a parse at
    /// the drawing site, because the panel never reads the identifier (R-96o).
    public var isSelectedItem: Bool { SelectedItem.isItemSubject(identifier) }

    /// The application an item subject belongs to, for a host that looks names up.
    public static func applicationIdentifier(of identifier: String) -> String {
        SelectedItem.parse(identifier)?.bundleIdentifier ?? identifier
    }

    /// The subject a sentence may name, or `nil` when there is nobody to name.
    ///
    /// - Parameters:
    ///   - identifier: the storage key. `nil`, empty and whitespace-only all mean the same thing
    ///     — e04's `InterventionMandate` carries `""` for mixed drift — and all three answer
    ///     `nil`, because a nudge over drift that named nobody must go on naming nobody.
    ///   - runningName: what the application calls itself, when something has looked. `nil` when
    ///     nothing has, when it is not running, or when it is running under no name at all; all
    ///     three fall back to the identifier rather than to an empty sentence.
    public static func named(_ identifier: String?, runningName: String? = nil) -> NudgeSubject? {
        guard let trimmed = nameable(identifier) else { return nil }
        return NudgeSubject(
            identifier: trimmed,
            displayName: display(for: trimmed, runningName: runningName)
        )
    }

    /// The same, for the one type that already guarantees a nameable identifier.
    ///
    /// `QuerySubject.identifier` is trimmed and non-empty by construction — `derive(…)` returns
    /// `nil` rather than producing an unnameable subject — so this route is **total**, and a
    /// question's subject does not have to be re-checked for a shape it cannot have. That is what
    /// keeps `QueryPresentation.subject` non-optional, which is R-76.2's own statement about the
    /// question: *"is something part of your task?"* is not a question, so it is never asked.
    public static func of(_ subject: QuerySubject, runningName: String? = nil) -> NudgeSubject {
        NudgeSubject(
            identifier: subject.identifier,
            displayName: display(for: subject.identifier, runningName: runningName)
        )
    }

    /// The naming policy, total over the whole input space and in one place.
    ///
    /// Order matters, and the origin comes first: an origin is not an application, has no
    /// localised name to have been looked up, and its display half is *derived* rather than
    /// asked for. Deriving it through `ContextItemValue.displayName(forOrigin:)` is the point of
    /// this line — the chip row and the nudge then say the same word about the same origin,
    /// which is the disagreement focus-ebv is about.
    private static func display(for identifier: String, runningName: String?) -> String {
        let candidate: String
        if let item = SelectedItem.parse(identifier) {
            // An item is named by its own label (issue #24): the application's name would be
            // the very thing the question is narrowing away from.
            candidate = item.label
        } else if isOrigin(identifier) {
            candidate = BrowserPage.displayName(for: identifier)
                ?? ContextItemValue.displayName(forOrigin: identifier)
        } else {
            candidate = runningName ?? identifier
        }
        // The last line of the fallback chain, stated once. Every branch above can in principle
        // hand back whitespace — a bundle running under a blank name, an origin whose host
        // parses to nothing — and none of them may put an empty sentence on a person's screen.
        return nameable(candidate) ?? identifier
    }

    /// **A candidate that is actually nameable, or `nil`** — the whole of the rule, in one place.
    ///
    /// Empty and whitespace-only are how an absent value arrives: e04's `InterventionMandate`
    /// carries `""` for mixed drift, and `FileManager.displayName` really does answer `"   "` for
    /// a bundle called `   .app` (measured). Neither is something a sentence can say.
    ///
    /// It is `public` because it had **three private copies** — here, on `QuerySubject` and on
    /// `CorrectionAction` — and a fourth was about to be written in `FocusUI` when focus-7gc
    /// asked why `ReturnTarget` guarded `isEmpty` while the subject beside it guarded whitespace.
    /// A rule with copies is a rule with places to drift, and this one had already drifted: the
    /// panel drew *"Back to    "* for an application the sentence three lines above was willing
    /// to call by its identifier instead. The other two now call this.
    public static func nameable(_ candidate: String?) -> String? {
        guard let candidate else { return nil }
        let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

extension NudgeSubject: CustomStringConvertible {
    /// **The name, not the key.** `QuerySubject.description` is the identifier because that value
    /// *is* the key; this one is what a person would be shown, so an interpolation of it in a log
    /// or a test message reads the way the panel does.
    public var description: String { displayName }
}
