import FocusCore
import SwiftUI

/// The one thing, drawn as the largest and highest object on the screen.
///
/// This view is the whole of F-02's visual promise and the whole of F-147's. Three properties
/// make it a promise rather than a preference:
///
/// * **It is the only use of `DesignTokens.FontRole.priorityHero` in the package**, asserted
///   by `TypeHierarchyTests`. A type role used twice is a heading style, not a hero.
/// * **It never truncates.** `lineLimit(nil)` plus `fixedSize(horizontal: false, vertical:
///   true)` means the text takes whatever width it is offered and grows *downward*. At the
///   largest text scale a long priority renders strictly taller rather than clipped, which is
///   what `DynamicTextResilienceTests` measures.
/// * **The user's own sentence is drawn verbatim.** It is data, not prose: it never goes
///   through a String Catalog and it is never abbreviated, ellipsised or title-cased.
///
/// With no priority yet, the hero is the invitation rather than an empty box — the question
/// itself, at hero size, in supporting colour. An empty state that leaves the largest area of
/// the window blank teaches the user that the app has nothing to say.
public struct PriorityHeroView: View {
    /// The user's sentence, or `nil` when nothing has been committed to yet.
    public let intent: String?

    @Environment(\.appearanceTraits) private var traits
    @Environment(\.shellStringTransform) private var transform

    public init(intent: String?) {
        self.intent = intent
    }

    public var body: some View {
        let words = intent?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let isPrompt = words.isEmpty

        // The prompt is prose and goes through the string seam; the priority is the user's
        // own words and must not. Both are drawn by the same view so the hero role has
        // exactly one use site — see `HeroText`.
        return HeroText(
            string: isPrompt ? transform(ShellStrings.string(.priorityHeroEmpty)) : words
        )
        .foregroundStyle(
            isPrompt
                ? DesignTokens.supportingTextColor(for: traits)
                : DesignTokens.Palette.primaryText
        )
        .lineLimit(nil)
        .fixedSize(horizontal: false, vertical: true)
        .textSelection(.enabled)
        .accessibilityAddTraits(.isHeader)
    }
}

/// Text at the hero role, and the **one** place in `FocusUI` that names that role.
///
/// It exists so that the empty-state prompt and the user's own sentence — which have to be
/// drawn by different mechanisms, one through the catalog seam and one verbatim — still share
/// a single reference to `DesignTokens.FontRole.priorityHero`. Without it the hero role would
/// appear twice in this file and the "used exactly once" assertion would have to be weakened
/// to something that no longer means anything.
private struct HeroText: View {
    let string: String

    @Environment(\.shellTextScale) private var textScale

    var body: some View {
        Text(verbatim: string)
            .font(DesignTokens.font(.priorityHero, scale: textScale))
    }
}
