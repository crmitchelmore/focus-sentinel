import FocusCore
import SwiftUI

/// **Everything the question needs to draw itself**, as one value.
///
/// Note what is *not* on it. There is no band, no stage, no rung and no severity: a
/// `QueryWarrant` carries none of those and this presentation is built from one, so a surface
/// could not draw an accusation from a question even by mistake (R-76.2). It is the same
/// structural fact as the type-level one, one layer out.
public struct QueryPresentation: Sendable, Equatable {
    /// One of the four static decks.
    public let voice: NudgeVoice
    /// The priority's own sentence. `{task}`.
    public let task: String
    /// The application the question is about. `{subject}`.
    ///
    /// **Never optional.** `QuerySubject` has no mixed case and `QueryEligibility.decide(…)`
    /// withholds with `.noSingleSubject` rather than producing one, so by the time anybody can
    /// see this panel there is exactly one nameable thing to ask about. *"Is something part of
    /// your task?"* is not a question, so it is never asked.
    ///
    /// **Both halves, and the sentence draws only one of them** (focus-ebv). This was a `String`
    /// carrying `QuerySubject.identifier`, so the question a person met read *"Is
    /// com.figma.Desktop part of Write the Q3 proposal?"*. The rule an answer writes is still
    /// keyed on `subject.identifier`; `subject.displayName` is the only half this view draws.
    public let subject: NudgeSubject
    /// Which of the three answerable uncertainties produced it (R-77). Drawn, because a person
    /// asked a question deserves to know why they are being asked it.
    public let reason: QueryableUncertainty
    /// How long they have been with it, monotonic. Carried for the record; the panel draws no
    /// duration, because a question about a moment does not need to price it.
    public let dwelled: Duration

    public init(
        voice: NudgeVoice = .standard,
        task: String,
        subject: NudgeSubject,
        reason: QueryableUncertainty,
        dwelled: Duration
    ) {
        self.voice = voice
        self.task = task
        self.subject = subject
        self.reason = reason
        self.dwelled = dwelled
    }

    /// **Three answers, and no fourth** (U-1, §3.B.8).
    ///
    /// In the order the panel offers them: the answer that teaches the app most, the answer that
    /// teaches it the other thing, and the one that teaches it nothing but is still remembered.
    /// The panel's close affordance is `notNow` — the same action, because a person who closes
    /// a panel has answered it, and treating a dismissal as "nothing happened" is what makes an
    /// app ask again tomorrow.
    ///
    /// **Escape is that same answer only once the panel has been clicked into** (e07a). It
    /// reaches the panel through `NudgePanel.cancelOperation(_:)`, which travels the *key*
    /// window's responder chain — and the panel is a `.nonactivatingPanel` shown with
    /// `orderFrontRegardless()` and never made key (R-96m), so while the person is still in the
    /// application they were asked about, Escape reaches *that* application. The keyboard route
    /// that works from there is the View menu: one ⌘-Tab to Focus, then ⌃⌘Y, ⌃⌘U or ⌃⌘L
    /// (`CommandRegistry.shell`).
    public static let actionOrder: [QueryAnswer] = [.yesAddIt, .no, .notNow]

    /// The default. "Yes, add it" is the click that grows the context pack and buys future
    /// silence — U-1's whole bargain — so it is the easiest one to reach. It is a default, never
    /// a coercion: the other two are the same size and one keystroke away (D-07).
    public var primaryAnswer: QueryAnswer { .yesAddIt }

    /// What VoiceOver hears: the question and its scope, in the order they are drawn (F-144).
    public func announcement() -> String {
        [
            NudgeCopy.string(
                voice: voice,
                .queryPanelTitle,
                arguments: [subject.displayName, task]
            ),
            NudgeCopy.string(voice: voice, .queryPanelScopeApp)
        ].joined(separator: " ")
    }
}

/// The copy key each answer is titled from.
extension QueryAnswer {
    /// The deck line that names this answer. Total: every answer is a button, because the close
    /// affordance is `notNow` **as well as** a button rather than instead of one — an affordance
    /// a person can only reach by knowing a keystroke is an affordance they may never find. (And
    /// the keystroke they might know, Escape, reaches this panel only once it has been clicked
    /// into; see `actionOrder`.)
    public var copyKey: NudgeCopyKey {
        switch self {
        case .yesAddIt: .queryActionYes
        case .no: .queryActionNo
        case .notNow: .queryActionNotNow
        }
    }
}

/// **U-1's centrepiece: one question whose cheapest answer teaches the app** (R-77, R-86).
///
/// ## What makes this a question and not an accusation
///
/// The whole difference between this app and the ones people uninstall is that the question does
/// not carry an accusation inside it. Three things hold that:
///
/// * every line here comes from a `query.*` deck key, and `check-forbidden.sh`'s R-96f fails the
///   gate on any second-person accusatory string under one of them;
/// * the panel draws **no** status glyph and no severity — it is not reporting a verdict, it is
///   admitting the app cannot tell;
/// * the scope is stated before the person answers, not after. "Answering adds it for this whole
///   app" is the honest description of the rule a click writes at baseline (R-86, F-60), and
///   e07's origin signal narrows the same sentence without changing this view.
///
/// ## Three actions, and no fourth
///
/// There is no "always"/"never"/"just this once" ladder, no severity picker and no free-text
/// field. A question whose answer takes thought is a question that costs more than the silence
/// it buys.
public struct QueryPanelView: DecisionSurfaceContent {
    private let presentation: QueryPresentation
    /// What the person clicked. **Internal, so the unit lane can invoke it directly**: the view
    /// decides nothing and writes nothing, and `QueryLedger.answer(…)` remains the single place
    /// an answer becomes the atomic two-record transaction R-78 requires.
    let onAnswer: (QueryAnswer) -> Void
    /// **Who put this on the screen** (focus-0nm, U-1).
    ///
    /// `.uninvited` by default, and the default is the point: this view exists to be raised by
    /// the app over whatever the person was looking at, which under U-1 is by definition the
    /// thing the app is interrupting them about. An uninvited surface is opaque whatever the
    /// traits say, so a full-screen video or a bright document cannot read through the sentence
    /// explaining itself. The one caller that is genuinely summoned — the popover under the
    /// status item the person clicked — says so.
    ///
    /// The default is deliberately the strict answer rather than the permissive one: forgetting
    /// to state it produces a legible surface, never a translucent one.
    let provenance: SurfaceProvenance

    @Environment(\.appearanceTraits) private var traits
    @Environment(\.shellTextScale) private var textScale
    @ScaledMetric(relativeTo: .body) private var spacing: CGFloat = 12

    public init(
        presentation: QueryPresentation,
        provenance: SurfaceProvenance = .uninvited,
        onAnswer: @escaping (QueryAnswer) -> Void = { _ in }
    ) {
        self.presentation = presentation
        self.provenance = provenance
        self.onAnswer = onAnswer
    }

    private enum LayoutPart { case whole, context, decision }
    private var layoutPart: LayoutPart?

    @ViewBuilder
    public var body: some View {
        switch layoutPart {
        case .whole: column { question; answers }
        case .context: column { question }
        case .decision: column { answers }
        case nil: styledContent
        }
    }

    private var styledContent: some View {
        column { question; answers }
            // The rule lives in this inset, never on top of the words (see `decisionRuleInset`).
            .padding(.leading, DesignTokens.decisionRuleInset)
            .shellSurface(
                DesignTokens.material(for: traits, provenance: provenance),
                in: Rectangle(),
                traits: traits
            )
            .overlay(alignment: .leading) {
                // **The rule is drawn, and it is not the only channel** (focus-0nm). Colour is
                // the fourth channel here as everywhere else: the grammar of the title (R-96v),
                // the action set and the announcement all already say which surface this is, and
                // a person who cannot use colour loses nothing by this rule being absent. So it
                // is hidden from the accessibility tree rather than labelled — a rule with a
                // spoken name would be VoiceOver reading out a decoration.
                if let tint = DesignTokens.decisionRuleTint(for: Self.decisionSurface, traits: traits) {
                    Rectangle()
                        .fill(tint)
                        .frame(width: DesignTokens.decisionRuleWidth)
                        .accessibilityHidden(true)
                }
            }
    }

    public static let decisionSurface: DecisionSurface = .questionPanel

    /// **Which half of this panel is the decision** (focus-din).
    ///
    /// The question, the reason the app is asking and the sentence saying what a click writes are
    /// what the decision is *about*; the three answers are the decision. When the panel has to
    /// give way the first group scrolls and the answers stay in the viewport — a question whose
    /// answers are below the fold is a question nobody was asked, and U-1's whole licence to
    /// interrupt rests on the answer being one click away.
    public var surfaceLayout: DecisionSurfaceLayout {
        DecisionSurfaceLayout(
            whole: AnyView(layoutView(.whole)),
            context: AnyView(layoutView(.context)),
            decision: AnyView(layoutView(.decision))
        )
    }

    // Return a View value; read its Environment only after SwiftUI installs it.
    private func layoutView(_ part: LayoutPart) -> Self {
        var view = self
        view.layoutPart = part
        return view
    }

    /// The one column every rendering of this panel is built in.
    private func column<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.spacing(spacing, scale: textScale)) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(verbatim: presentation.announcement()))
    }

    @ViewBuilder
    private var question: some View {
        if provenance == .uninvited && textScale == .standard {
            CompanionHeader {
                NudgeText(.queryPanelHeading, voice: presentation.voice, role: .title2)
            }
        }

        NudgeText(
            .queryPanelTitle,
            voice: presentation.voice,
            arguments: [presentation.subject.displayName, presentation.task],
            role: provenance == .uninvited ? .title2 : .headline
        )
        .foregroundStyle(DesignTokens.Palette.primaryText)
        .lineLimit(nil)
        .fixedSize(horizontal: false, vertical: true)

        // Why the app is asking. Not an apology and not a justification — a fact about what
        // it knows, which is the only thing that makes "I cannot tell" trustworthy.
        ShellText(resource: presentation.reason.copyResource, role: supportingRole)
            .foregroundStyle(DesignTokens.supportingTextColor(for: traits))
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)

        // The scope, **before** the answer. A person who clicks "Yes" has been told what
        // the click writes.
        NudgeText(.queryPanelScopeApp, voice: presentation.voice, role: supportingRole)
            .foregroundStyle(DesignTokens.supportingTextColor(for: traits))
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var supportingRole: DesignTokens.FontRole {
        provenance == .uninvited ? .callout : .footnote
    }

    private var answers: some View {
        let gap = DesignTokens.spacing(spacing / 2, scale: textScale)
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: gap) {
                ForEach(QueryPresentation.actionOrder, id: \.self) { answer in
                    answerButton(answer, wraps: false)
                }
            }
            // The fallback. It wraps, because at the largest accessibility text size "Not now"
            // measured 371 points inside a 348-point column and reported a frame past the edge of
            // the panel — an answer a person cannot click is an answer they do not have, which is
            // the U-1 defect this whole invariant exists to catch.
            VStack(alignment: .leading, spacing: gap) {
                ForEach(QueryPresentation.actionOrder, id: \.self) { answer in
                    answerButton(answer, wraps: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    /// Prominent, never default — the same ruling the accusation panel records. "Yes, add it"
    /// is the easiest button to find because it is the one that buys future silence, and it is
    /// easy to find by being **drawn** that way rather than by claiming the Return key from
    /// whatever the person happens to be typing into.
    @ViewBuilder
    private func answerButton(_ answer: QueryAnswer, wraps: Bool) -> some View {
        // **The answer reports where it landed** (focus-vpu). A live drive found "Yes, add it /
        // No / Not now" entirely absent at the largest accessibility text size, on a panel that
        // reported itself correctly sized — which is the U-1 defect in its purest form: the app
        // counting a question as asked that nobody could answer.
        if answer == presentation.primaryAnswer {
            plainAnswerButton(answer, wraps: wraps)
                .buttonStyle(CompanionButtonStyle(prominent: true))
                .tint(DesignTokens.Palette.role(.spruce, for: traits))
                .nudgeActionTarget(answer.rawValue)
        } else {
            plainAnswerButton(answer, wraps: wraps)
                .buttonStyle(CompanionButtonStyle())
                .nudgeActionTarget(answer.rawValue)
        }
    }

    private func plainAnswerButton(_ answer: QueryAnswer, wraps: Bool) -> some View {
        Button {
            onAnswer(answer)
        } label: {
            NudgeText(answer.copyKey, voice: presentation.voice, role: .callout)
                // Never truncated: an answer whose words a person cannot read is an answer they
                // cannot choose. The stacked fallback wraps rather than insisting on one line,
                // because an answer drawn past the edge of the panel is one they cannot click.
                .lineLimit(wraps ? nil : 1)
                .fixedSize(horizontal: !wraps, vertical: wraps)
                .padding(.vertical, provenance == .uninvited ? 7 : 0)
                .frame(maxWidth: .infinity)
        }
    }
}
