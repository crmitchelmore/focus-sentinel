import FocusCore
import SwiftUI

/// The constructive half of F-07, and the whole of F-18's shipped scope.
///
/// A vague sentence is answered here, never refused. The strip says what is missing in plain
/// language, offers **one** rewrite built from the user's own words, and pre-fills a
/// definition of done from the object of their own sentence. It has two buttons and neither
/// of them is "OK": *Use This* takes the suggestion, *Keep My Words* dismisses it. The Set
/// Priority button behind the strip stays enabled throughout — pressing it again commits the
/// original sentence, unchanged (R-20).
///
/// **No prose is composed at runtime.** Every sentence here is a String Catalog entry; the
/// only thing substituted into it is a phrase the user typed, through `ShellText(_:argument:)`.
/// That is standing condition 4, and it stays true when e06 adds its optional
/// FoundationModels rewrite as one more row in this same strip.
///
/// `IntentAssessment.notAssessable` draws **nothing**: outside English the lexicon cannot
/// read the sentence, and a confident suggestion in a language the code does not know is
/// worse than silence.
public struct RefinementStrip: View {
    /// What the deterministic validator made of the current sentence.
    public let assessment: IntentAssessment
    /// Take the suggestion: the rewritten sentence, and a definition of done if one could be
    /// built from the user's own words.
    public let apply: (String, String?) -> Void
    /// Dismiss the strip and keep what was typed.
    public let dismiss: () -> Void

    @Environment(\.appearanceTraits) private var traits
    @ScaledMetric(relativeTo: .body) private var spacing: CGFloat = 12

    public init(
        assessment: IntentAssessment,
        apply: @escaping (String, String?) -> Void,
        dismiss: @escaping () -> Void
    ) {
        self.assessment = assessment
        self.apply = apply
        self.dismiss = dismiss
    }

    public var body: some View {
        let findings = assessment.findings

        return Group {
            if let leading = findings.first {
                VStack(alignment: .leading, spacing: spacing / 2) {
                    ShellText(.captureRefineHeading, role: .caption)
                        .foregroundStyle(DesignTokens.supportingTextColor(for: traits))

                    // Every finding is worth saying — they are emitted most-structural first
                    // — but only the leading one carries a rewrite, because offering three
                    // competing rewrites is not help.
                    ForEach(findings) { finding in
                        Label {
                            ShellText(Self.explanationKey(for: finding.kind), role: .callout)
                                .lineLimit(nil)
                                .fixedSize(horizontal: false, vertical: true)
                        } icon: {
                            Image(systemName: "lightbulb")
                        }
                    }

                    suggestion(leading.suggestion)
                }
                .padding(spacing)
                .frame(maxWidth: .infinity, alignment: .leading)
                .shellSurface(
                    DesignTokens.material(for: traits, provenance: .summoned),
                    in: RoundedRectangle(cornerRadius: spacing / 2, style: .continuous),
                    traits: traits
                )
                .overlay {
                    RoundedRectangle(cornerRadius: spacing / 2, style: .continuous)
                        .strokeBorder(
                            DesignTokens.Palette.separator(for: traits)
                                .opacity(DesignTokens.emphasis(for: traits).outlineOpacity),
                            lineWidth: DesignTokens.emphasis(for: traits).borderWidth
                        )
                }
            }
        }
    }

    // MARK: - The one suggestion

    @ViewBuilder
    private func suggestion(_ suggestion: IntentSuggestion) -> some View {
        let doneWhen = suggestion.doneWhenPhrase.map {
            ShellStrings.string(.captureSuggestionDoneWhen, argument: $0)
        }

        VStack(alignment: .leading, spacing: spacing / 3) {
            ShellText(
                Self.suggestionKey(for: suggestion.kind),
                argument: suggestion.rewrite
            )
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)

            if let phrase = suggestion.doneWhenPhrase {
                ShellText(.captureSuggestionDoneWhenLabel, role: .caption)
                    .foregroundStyle(DesignTokens.supportingTextColor(for: traits))
                ShellText(.captureSuggestionDoneWhen, role: .callout, argument: phrase)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }

        HStack(spacing: spacing) {
            Button {
                apply(suggestion.rewrite, doneWhen)
            } label: {
                ShellText(.captureSuggestionUse)
            }
            .disabled(suggestion.rewrite.isEmpty)
            // Tooltips from the catalog (focus-8ski); a disabled control says why.
            .shellHelp(
                .captureSuggestionUseHelp,
                disabled: .captureSuggestionUseDisabledHelp,
                when: suggestion.rewrite.isEmpty
            )

            Button {
                dismiss()
            } label: {
                ShellText(.captureSuggestionKeep)
            }
            .shellHelp(.captureSuggestionKeepHelp)

            Spacer(minLength: 0)
        }
    }

    // MARK: - Typed finding → authored explanation

    /// The explanation for a finding.
    ///
    /// `FocusCore` carries a typed `Kind` and never a sentence of English; the mapping from
    /// that type to the catalog lives here, in the module that draws it. A new finding kind
    /// therefore fails to compile until someone writes its explanation, which is the point.
    static func explanationKey(for kind: IntentFinding.Kind) -> ShellStringKey {
        switch kind {
        case .noLeadingVerb: .captureFindingNoLeadingVerb
        case .tooShort: .captureFindingTooShort
        case .nounOnlyPhrase: .captureFindingNounOnlyPhrase
        case .noOutcome: .captureFindingNoOutcome
        }
    }

    static func suggestionKey(for kind: IntentSuggestion.Kind) -> ShellStringKey {
        switch kind {
        case .startWithVerb: .captureSuggestionStartWithVerb
        case .sayMore: .captureSuggestionSayMore
        case .nameTheOutcome: .captureSuggestionNameTheOutcome
        }
    }
}
