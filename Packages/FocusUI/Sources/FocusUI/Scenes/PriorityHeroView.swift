import FocusCore
import SwiftUI

/// The one thing, drawn as the largest and highest object on the screen.
///
/// This view is the whole of F-02's visual promise and the whole of F-147's. Three properties
/// make it a promise rather than a preference:
///
/// * **This file is the only place `DesignTokens.FontRole.priorityHero` is named**, asserted
///   by `TypeHierarchyTests`. A type role used twice is a heading style, not a hero — so the
///   sentence, the empty-state invitation and the in-place editor all draw through the one
///   `HeroType` modifier below.
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

/// Fixing the wording of the commitment you are already making.
///
/// Deliberately **not** the same act as capturing a new priority. Setting a priority starts a
/// new commitment and pushes the old one into history; this keeps the task — its context pack,
/// its rules, its timebox — and changes only the sentence, one revision later. Both are
/// undoable, and the Edit menu names which of the two you took.
///
/// It is drawn at the hero role because it edits the hero in place: a sentence that shrinks
/// the moment you start typing in it is a different sentence to the eye, and the person is
/// correcting the largest thing on the screen, not filling in a form field.
struct PriorityIntentEditor: View {
    @Binding var draft: String
    /// Return, or leaving the field. Commits whatever is there.
    let commit: () -> Void
    /// Escape. Leaves the stored sentence exactly as it was.
    let cancel: () -> Void
    /// The surrounding surface's focus state, so the editor keeps its place in the Tab order.
    let focus: FocusState<FocusField?>.Binding

    var body: some View {
        TextField(
            text: $draft,
            prompt: Text(ShellStrings.resource(.priorityIntentEditPrompt))
        ) {
            ShellText(.priorityIntentEditLabel)
        }
        .labelsHidden()
        .heroType()
        .textFieldStyle(.plain)
        // One line, and Return commits it. A vertical-axis field would take Return for a
        // newline, and a priority is one sentence — the place to write more than that is the
        // definition of done, which is right underneath.
        .focused(focus, equals: .cockpitEditIntent)
        .onSubmit(commit)
        .onExitCommand(perform: cancel)
        .accessibilityLabel(Text(ShellStrings.resource(.priorityIntentEditLabel)))
    }
}

/// Text at the hero role.
///
/// It exists so that the empty-state prompt and the user's own sentence — which have to be
/// drawn by different mechanisms, one through the catalog seam and one verbatim — share a
/// single way of asking for the hero role.
private struct HeroText: View {
    let string: String

    var body: some View {
        Text(verbatim: string)
            .heroType()
    }
}

/// The **one** place in `FocusUI` that names `DesignTokens.FontRole.priorityHero`.
///
/// Three things are drawn at hero size — the user's sentence, the empty-state invitation and
/// the in-place editor — and they must be the same size or the hero is not one thing. Routing
/// all three through a single modifier is what keeps the "used exactly once" assertion in
/// `TypeHierarchyTests` meaningful instead of something that had to be weakened the first time
/// a second hero-sized element shipped.
private struct HeroType: ViewModifier {
    @Environment(\.shellTextScale) private var textScale

    func body(content: Content) -> some View {
        content.font(DesignTokens.font(.priorityHero, scale: textScale))
    }
}

extension View {
    /// Draw this at the priority-hero role.
    fileprivate func heroType() -> some View {
        modifier(HeroType())
    }
}
