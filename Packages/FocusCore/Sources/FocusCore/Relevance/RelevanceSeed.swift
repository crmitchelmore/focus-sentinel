import Foundation

/// The bundled per-application defaults.
///
/// **Code, not data** (R-64). A user's own rule sits at a strictly higher rung than any of
/// these, so "removing a seed" *is* writing a rule — which the rules pane already does — and
/// there is no reseed reconciliation to get wrong. e03 persisted its sensitive-application
/// list because that list gates a *read* and had to be editable before any classification
/// existed; this one gates a *judgement* the cascade already lets the user overrule, and
/// persisting it would buy a reseed problem for nothing.
///
/// ## Two rules govern this table and both are load-bearing
///
/// **Exactly one row is decisive**, and it is the one the Court ordered. **Every other row is
/// `askEachTime`**, which maps to `uncertain`, which suppresses intervention — so the seed
/// list is a net *reduction* in false nudges rather than a set of accusations the app ships
/// about applications it has not measured.
///
/// Note what is **absent**: no social network, no game and no video site is listed as
/// `alwaysDistracting`. Two reasons, both rulings rather than caution. First, at zero grants
/// the app sees a bundle identifier and nothing else, so "YouTube" and "a YouTube tutorial the
/// priority names" are the same observation, and adversarial family 3 exists precisely because
/// the app must not guess between them. Second, an `alwaysDistracting` seed is the only kind
/// of row that can *cause a nudge without the user having said anything*, and shipping a list
/// of those would make the app's first impression an accusation it cannot support.
public enum RelevanceSeed {
    /// The bundled defaults, keyed by bundle identifier. Every row carries a note.
    public static let defaults: [String: AppRuleDisposition] = [
        // The one decisive row, and the only opinion this app ships.
        // F-171, ruled DOWNGRADE (absorbed) by the Court: "one line of shipped seed data is a
        // real, verifiable artefact, which is strictly better than an unrecorded park."
        // Verified present on this Mac at /System/Applications/iPhone Mirroring.app (P-122).
        // Subject to the seed-override guard: a priority whose own words contain "mirroring"
        // or "iphone" downgrades this to `uncertain` (R-64).
        "com.apple.ScreenContinuity": .alwaysDistracting,

        // Everything below is `askEachTime` — i.e. `uncertain`, i.e. the app declines and
        // offers the person the one-click rule instead. A browser is not evidence about a
        // priority; neither is a chat client, a music player or a general-purpose editor.
        "com.apple.Safari": .askEachTime,               // a browser is anything
        "com.google.Chrome": .askEachTime,
        "org.mozilla.firefox": .askEachTime,
        "com.microsoft.edgemac": .askEachTime,
        "com.brave.Browser": .askEachTime,
        "com.apple.MobileSMS": .askEachTime,            // e03 offers this as sensitive too
        "com.apple.mail": .askEachTime,                 // work and not-work in one window
        "com.tinyspeck.slackmacgap": .askEachTime,
        "com.hnc.Discord": .askEachTime,                // a game chat and a work chat
        "us.zoom.xos": .askEachTime,
        "com.apple.Music": .askEachTime,                // music while working is working
        "com.spotify.client": .askEachTime,
        "com.apple.TV": .askEachTime,
        "com.google.Chrome.app.Default": .askEachTime,
        "com.apple.Notes": .askEachTime,                // the misleading-name family's fixture
        "com.apple.Terminal": .askEachTime,
        "com.apple.systempreferences": .askEachTime     // maintenance is neither
    ]

    /// The bundled disposition for a bundle identifier, or `nil` when the app ships no opinion
    /// about it — which is the case for every application on this Mac but eighteen.
    ///
    /// Matching is exact. There is no prefix rule and no fuzzy match, because
    /// `com.apple.Safari` and `com.apple.SafariTechnologyPreview` are different applications
    /// and a seed that guessed between them would be an opinion the app never measured.
    public static func disposition(for bundleIdentifier: String) -> AppRuleDisposition? {
        defaults[bundleIdentifier]
    }

    /// The single decisive row, as a value rather than as a lookup — so a test can assert
    /// there is exactly one, and which one it is.
    public static var decisiveSeeds: [String: AppRuleDisposition] {
        defaults.filter { $0.value.seedStage == .seedRule }
    }

    /// Every row that declines to decide, which is every other row.
    public static var fallbackSeeds: [String: AppRuleDisposition] {
        defaults.filter { $0.value.seedStage == .seedFallback }
    }
}
