import FocusCore
import SwiftUI

/// **What Focus currently thinks, and why** — the verdict inspector (R-71).
///
/// ## Why it lives in Settings ▸ Privacy rather than behind a developer flag
///
/// The roadmap asked for *"an internal 'current verdict' debug surface"*. It ships here instead,
/// beside the capability matrix e03 put in the same pane, because a surface that shows a person
/// exactly what the app concluded about them and why is a **trust** surface and belongs where
/// the other ones are. A debug window nobody but the author can open is a claim about the app's
/// honesty that the app never actually makes.
///
/// ## It reports the judgement the app acts on, not a copy of it
///
/// **This pane and the ladder read the same verdict** (focus-lmy). `RelevanceHost` assigns the
/// eligibility once and hands it to both: to Settings, and to `NudgeHost`, which folds the
/// mandate into the ladder. So when the eligibility reads *mandated* there is a rung being
/// raised — the ambient glyph first, the panel if the drift keeps up — and the sentence here
/// says that rather than announcing an absence.
///
/// It said the opposite for the whole of e05. `settings.verdict.mandated` shipped reading
/// *"Focus would speak up now. Nothing in this version can, so it does not."*, which was true
/// of e04 and became a **denial of the panel that was on screen while a person read it**. The
/// lesson is not about the sentence: three separate proofs agreed with it, because each was
/// written to the world the sentence described rather than to the branch it draws.
///
/// ## What it may show, and what it structurally cannot
///
/// It shows the status glyph and label, the rung that decided, the evidence band, the drift
/// clock, the typed explanation clauses, the reason for silence when it is silent, and the
/// engine stamp. It shows **no number from the similarity signal** — `ExplanationClause` has no
/// case that could carry one — and **no raw evidence**, which is unrepresentable rather than
/// merely forbidden: every textual payload it can reach is a `NormalisedToken` (R-57).
///
/// `FocusUI` renders this without importing `FocusClassify`, which is only possible because the
/// whole classification vocabulary moved to `FocusCore` (R-53).
public struct VerdictInspectorView: View {
    /// What the engine last concluded, or `nil` when it has concluded nothing.
    ///
    /// `nil` is a real answer rather than a missing one, and it is drawn as *nothing judged
    /// yet*: an app that showed `relevant` before it had looked at anything would be inventing
    /// a judgement, in exactly the way `CockpitState.ready` refuses to.
    public let verdict: VerdictSnapshot?

    @Environment(\.appearanceTraits) private var traits
    @Environment(\.shellTextScale) private var textScale
    @ScaledMetric(relativeTo: .body) private var spacing: CGFloat = 12

    public init(verdict: VerdictSnapshot?) {
        self.verdict = verdict
    }

    /// The strings this surface always draws, whatever the verdict. Asserted non-empty by the
    /// settings suite: a section that renders nothing is a defect, not a design.
    nonisolated public static let contentKeys: [ShellStringKey] = [
        .verdictHeading,
        .verdictExplanation,
        .verdictNothingJudged,
        .verdictRungLabel,
        .verdictBandLabel,
        .verdictDriftLabel,
        .verdictReasonsLabel,
        .verdictSilenceLabel,
        .verdictMandated,
        .verdictEngineLabel
    ]

    public var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            ShellText(.verdictHeading, role: .headline)

            ShellText(.verdictExplanation, role: .callout)
                .foregroundStyle(DesignTokens.supportingTextColor(for: traits))
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)

            if let verdict {
                judged(verdict)
            } else {
                ShellText(.verdictNothingJudged, role: .callout)
                    .foregroundStyle(DesignTokens.supportingTextColor(for: traits))
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(ShellStrings.resource(.verdictHeading)))
    }

    // MARK: - A verdict there is

    @ViewBuilder
    private func judged(_ verdict: VerdictSnapshot) -> some View {
        VStack(alignment: .leading, spacing: spacing / 2) {
            // Three channels, as everywhere else in this shell: the SF Symbol, the silhouette
            // it sits in, and the short label. Colour is a fourth and is never alone.
            StatusBadge(status: verdict.status)

            // Which rung answered. Read from `CascadePrecedence` — the only ordered list of
            // rungs in the repository — so the pane and the engine cannot say different things
            // about who decided (R-54).
            if let rung = verdict.rung {
                row(.verdictRungLabel) {
                    ShellText(resource: rung.settingsCopyResource, role: .callout)
                }
            }

            // How much it had to go on. Absent for `uncertain`, because declining to decide has
            // no evidence to band and drawing `low` there would imply a weak *decision* rather
            // than the absence of one.
            if let band = verdict.band {
                row(.verdictBandLabel) {
                    ShellText(resource: band.labelResource, role: .callout)
                }
            }

            // The drift clock, counting. Drawn only once there is something to count: `aligned`
            // is not "zero seconds off track", it is "not off track".
            if verdict.drift != .aligned {
                row(.verdictDriftLabel) {
                    Text(
                        verbatim: verdict.drift.accumulated.formatted(
                            .units(allowed: [.hours, .minutes, .seconds], width: .narrow)
                        )
                    )
                    .font(DesignTokens.font(.callout, scale: textScale))
                    .monospacedDigit()
                }
            }

            if !verdict.explanation.isEmpty {
                ShellText(.verdictReasonsLabel, role: .caption)
                    .foregroundStyle(DesignTokens.supportingTextColor(for: traits))

                ForEach(Array(verdict.explanation.clauses.enumerated()), id: \.offset) { entry in
                    ExplanationClauseRow(clause: entry.element)
                        .padding(.leading, spacing / 2)
                }
            }

            eligibility(verdict)

            // Which engine said so. A version string is data, not prose, and it is here because
            // a person reading a verdict a week from now should be able to tell whether the
            // thing that produced it is the thing running today (R-63).
            row(.verdictEngineLabel) {
                Text(verbatim: verdict.stampKey)
                    .font(DesignTokens.font(.footnote, scale: textScale))
                    .monospaced()
                    .textSelection(.enabled)
            }
        }
    }

    /// Whether the app may interrupt — and, when it may not, the named reason.
    ///
    /// A surface that can say *why* it stayed silent is a surface a person can trust, which is
    /// why `SuppressionReason` is a first-class value with copy of its own rather than a
    /// `Bool` somewhere.
    @ViewBuilder
    private func eligibility(_ verdict: VerdictSnapshot) -> some View {
        if let reason = verdict.eligibility.suppressionReason {
            row(.verdictSilenceLabel) {
                ShellText(resource: reason.copyResource, role: .callout)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else {
            // No suppression reason is exactly `.mandated`: the engine has authorised an
            // interruption, and e05's ladder is what consumes it. There is no third state to
            // fall through to, which is why this branch needs no condition of its own — and
            // why a fixture that could not be `.mandated` left it with no picture at all.
            ShellText(.verdictMandated, role: .callout)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// One labelled line: a caption, then the value.
    private func row(
        _ label: ShellStringKey,
        @ViewBuilder value: () -> some View
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: spacing / 2) {
            ShellText(label, role: .caption)
                .foregroundStyle(DesignTokens.supportingTextColor(for: traits))
            value()
            Spacer(minLength: 0)
        }
    }
}
