import FocusCore
import Foundation
import SwiftUI

/// **How a nudge surface turns a deck key into words**, and the one place it may do so.
///
/// The copy path is `NudgeVoice → NudgeCopyKey → LocalizedStringResource → String`, with no
/// step at which a string is composed rather than resolved. There is no model in this build at
/// all, and when e06 adds one this path is unchanged — which is what makes standing condition 4
/// and D-11 structural rather than observed.
///
/// Two substitutions exist and no more: the ones the templates themselves declare. Every
/// argument is a **typed value the app already has** — the priority's own sentence, an
/// application's localised name, a rendered duration — never prose about a person.
public enum NudgeCopy {
    /// One line of one deck, with the arguments its template declares.
    ///
    /// - Parameters:
    ///   - voice: which of the five static decks. `silentVisual` carries the full line set as
    ///     well as its routing behaviour, so this is total over `NudgeVoice`.
    ///   - line: which of the thirteen situations.
    ///   - arguments: the slot values, **in the order `NudgeCopyKey.slots` declares them**.
    ///     `NudgeVoiceTests` asserts every deck's string carries exactly that many specifiers,
    ///     so a deck that invented one fails the suite rather than a person's nudge.
    public static func string(
        voice: NudgeVoice,
        _ line: NudgeCopyKey,
        arguments: [String] = []
    ) -> String {
        let format = String(localized: voice.resource(line))
        guard !arguments.isEmpty else { return format }
        return String(format: format, arguments: arguments)
    }

    /// A span of time as a person would say it.
    ///
    /// Locale-aware through `Duration.UnitsFormatStyle`, so this is not prose the app composed:
    /// the words are Foundation's and the number is a fact about the person's own day. Minutes
    /// below the hour and hours-and-minutes above it, because "97 minutes" is a measurement and
    /// "1 hour, 37 minutes" is a sentence.
    /// Seconds below a minute, minutes below an hour, hours and minutes above it.
    ///
    /// The seconds band is not decoration: the Intervention pane draws
    /// `InterventionPolicy.queryDwellThreshold` — **45 s** — as a read-only mirror of the
    /// constant, and rounding it to "1 minute" would print a number the app does not use. A
    /// mirror that rounds is a mirror that lies.
    public static func duration(_ span: Duration) -> String {
        let clamped = span < .zero ? .zero : span
        if clamped >= .seconds(3600) {
            return clamped.formatted(.units(allowed: [.hours, .minutes], width: .wide))
        }
        if clamped < .seconds(60) {
            return clamped.formatted(.units(allowed: [.seconds], width: .wide))
        }
        return clamped.formatted(.units(allowed: [.minutes], width: .wide))
    }

    /// A countdown, in the fixed `mm:ss` form the menu bar draws (P-133).
    ///
    /// Digits rather than words, because this one **ticks**: P-133 measured the proportional
    /// system font moving a four-digit field by 7.69 pt between `11:11` and `88:88`, which would
    /// shove every menu-bar item to its left once a second. The monospaced-digit font that
    /// prevents that is applied where this string is drawn; the *shape* is fixed here, so the
    /// digit count cannot change mid-minute either.
    public static func countdown(_ remaining: Duration) -> String {
        let total = max(remaining.components.seconds, 0)
        return String(format: "%02lld:%02lld", total / 60, total % 60)
    }

    /// An elapsed time, in the fixed `h:mm:ss` form a session past the hour draws.
    ///
    /// The second of P-133's two forms. Which one a session uses is chosen **once**, from its
    /// planned duration, and does not change mid-session — because the width tracks the digit
    /// *count* (`1:00:00` measured 41.63 pt against `59:59`'s 31.30 pt), so a timer that grew a
    /// field at the hour mark would move every item beside it exactly once, unpredictably.
    public static func longCountdown(_ elapsed: Duration) -> String {
        let total = max(elapsed.components.seconds, 0)
        return String(
            format: "%lld:%02lld:%02lld",
            total / 3600,
            (total % 3600) / 60,
            total % 60
        )
    }
}

/// A line of nudge copy, drawn.
///
/// The nudge's counterpart to `ShellText`: it resolves a deck line, hands it to whatever string
/// transform is in force — so the pseudo-localisation lane expands the authored half and leaves
/// the person's own words alone — and draws the result at the shell's type role and scale.
///
/// `Text(verbatim:)` at the end, exactly as `ShellText` does, because by that point the string
/// is a resolved, transformed, argument-substituted value rather than a literal.
public struct NudgeText: View {
    private let voice: NudgeVoice
    private let line: NudgeCopyKey
    private let arguments: [String]
    private let role: DesignTokens.FontRole

    @Environment(\.shellStringTransform) private var transform
    @Environment(\.shellTextScale) private var scale

    public init(
        _ line: NudgeCopyKey,
        voice: NudgeVoice,
        arguments: [String] = [],
        role: DesignTokens.FontRole = .body
    ) {
        self.voice = voice
        self.line = line
        self.arguments = arguments
        self.role = role
    }

    /// The resolved string, exposed so a surface can hand the same words to an accessibility
    /// label or to `NSAccessibility`'s announcement without resolving them a second time.
    public var resolved: String {
        let format = transform(String(localized: voice.resource(line)))
        guard !arguments.isEmpty else { return format }
        return String(format: format, arguments: arguments)
    }

    public var body: some View {
        Text(verbatim: resolved)
            .font(DesignTokens.font(role, scale: scale))
    }
}
