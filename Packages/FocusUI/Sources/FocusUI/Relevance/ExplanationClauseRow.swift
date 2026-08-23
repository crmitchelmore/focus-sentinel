import FocusCore
import SwiftUI

/// One reason, drawn.
///
/// ## Why this is a view and not a `String`
///
/// `Explanation` is a list of typed `ExplanationClause` cases and there is **no clause that
/// takes free text** (R-62). Every textual payload is a `NormalisedToken`, which has no public
/// `String` initialiser and rejects anything carrying whitespace or a separator — so a window
/// title, a full URL, a document name or an absolute path cannot reach this row by any route.
/// It is not forbidden here; it is unrepresentable upstream, and this view is where that pays
/// off: it can draw its payload verbatim without checking anything, because there is nothing a
/// check would catch.
///
/// The sentence itself comes from `FocusCore`'s String Catalog, selected by the clause's kind
/// and never composed. **There is no runtime model-authored prose** — there is no model in this
/// build at all — so standing condition 4 and dissent ruling D-11 are structurally satisfied
/// rather than observed.
///
/// ## No number ever appears from the similarity signal
///
/// `similarityCorroborated` carries no distance and this row could not draw one if it wanted
/// to. Showing a person *"cosine 1.03"* would be showing them an implementation detail dressed
/// as a reason, and P-113 measured that the number would not even mean what they would take it
/// to mean: the related and unrelated classes overlap, and one pair inverts outright.
///
/// The two integers that *do* appear — a dwell in seconds and a count of subjects — are facts
/// about the person's own day rather than scores about them, and they are drawn through the
/// same locale-aware formatters the rest of the shell uses.
public struct ExplanationClauseRow: View {
    public let clause: ExplanationClause

    @Environment(\.appearanceTraits) private var traits
    @Environment(\.shellTextScale) private var textScale
    @ScaledMetric(relativeTo: .body) private var spacing: CGFloat = 8

    public init(clause: ExplanationClause) {
        self.clause = clause
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: spacing / 2) {
            Image(systemName: "circle.fill")
                .font(DesignTokens.font(.footnote, scale: textScale))
                .foregroundStyle(DesignTokens.supportingTextColor(for: traits))
                .accessibilityHidden(true)

            ShellText(resource: clause.kind.copyResource, role: .callout)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)

            // The clause's own payload, drawn as data rather than prose — the user's own words,
            // a rule subject they typed, or a context identity they attached. Safe verbatim by
            // construction (R-57), and never routed through a catalog, because it is theirs.
            if let evidence = Self.evidence(of: clause) {
                Text(verbatim: evidence)
                    .font(DesignTokens.font(.callout, scale: textScale))
                    .foregroundStyle(DesignTokens.supportingTextColor(for: traits))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    /// The clause's payload as one short string, or `nil` when it carries none.
    ///
    /// Tokens are already capped at `RelevancePolicy.maximumExplanationTokens` by
    /// `Explanation.make` — an explanation is evidence, not a transcript — so this joins what
    /// it is given rather than truncating again. A second cap here would be a second policy.
    nonisolated public static func evidence(of clause: ExplanationClause) -> String? {
        switch clause {
        case .sustainedDwell(let seconds):
            return Duration.seconds(seconds).formatted(
                .units(allowed: [.hours, .minutes, .seconds], width: .narrow)
            )
        case .mixedSubjects(let count):
            return count.formatted(.number)
        case .insufficientEvidence, .similarityCorroborated, .noNegativeBasis:
            return nil
        default:
            let tokens = clause.tokens
            guard !tokens.isEmpty else { return nil }
            return ListFormatter.localizedString(byJoining: tokens.map(\.value))
        }
    }
}
