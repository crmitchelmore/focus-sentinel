import FocusCore
import SwiftUI

/// **What the app did today and why it said so, row by row** (F-104, focus-tee.5).
///
/// ## What it draws, and what it will not
///
/// One row per thing that happened: an interruption with the surface it reached and what the
/// person did about it, a question with the app's own reason for asking and the person's own
/// answer, a session, and — the row this surface exists for — an interval the app **watched go
/// past and said nothing about**.
///
/// There is **no score, no streak, no total distracted time and no per-day tally**, and there is
/// nowhere in this file for one to be added. Ruling D-01 settled that outcome analytics is the
/// sole analytics philosophy; a count of somebody's day is a number they can be judged by
/// whatever it is labelled. `DayHistory.countsByKind` exists and is published in the self-check
/// so a gate can say the ledger is not empty — this view does not read it.
///
/// ## Why it is a window and not a sidebar row
///
/// `ShellWindow` has three cases and no split view, and `ShellActionEffect` has no "select
/// destination" member. Adding one, plus the availability totality fold it would need, is
/// uncosted work the epic review left to e09b. History is reached from the View menu — ⌃⌘D,
/// listed in the Keyboard Shortcuts window like every other bound verb — which is the route that
/// exists today. A cockpit button is deferred for a separate reason: `FocusTraversal` commits
/// the cockpit's keyboard order as a pinned list, and a new focusable control there is a change
/// to that order rather than to this surface.
///
/// ## FocusUI holds no SwiftData
///
/// This takes a `DayHistory` — a value `FocusHost` builds by reading the stores — exactly as the
/// cockpit takes its snapshot. `check-boundaries.sh` forbids `import SwiftData` here, and the
/// reason is the one this view depends on: a surface that could fetch is a surface whose test
/// would need a store.
public struct HistoryView: View {
    private let history: DayHistory
    /// What the person's disagreement does. `nil` in a snapshot or a preview, which is what
    /// makes the rendering lane a rendering lane: it draws the affordance without a store to
    /// write to, and the assertions about *what* it writes belong to `FocusCore`'s own tests.
    private let correct: (@MainActor (HistorySilence) -> Void)?
    /// The rows a correction has already been written for, so the button becomes a sentence
    /// rather than staying live and inviting a second identical rule.
    private let corrected: Set<UUID>

    @Environment(\.appearanceTraits) private var traits
    @ScaledMetric(relativeTo: .body) private var spacing: CGFloat = 12

    public init(
        history: DayHistory,
        corrected: Set<UUID> = [],
        correct: (@MainActor (HistorySilence) -> Void)? = nil
    ) {
        self.history = history
        self.corrected = corrected
        self.correct = correct
    }

    public var body: some View {
        ScrollView {
            HistoryContent(history: history, corrected: corrected, correct: correct)
        }
        .frame(minWidth: 380, minHeight: 260)
        .background(DesignTokens.Palette.windowBackground(for: traits))
    }
}

/// The ledger's content, without the window's scrolling — the thing the snapshot lane measures,
/// for `ShortcutsHelpContent`'s reason: measuring a scroll view's fixed frame learns nothing
/// about the content that must not clip.
struct HistoryContent: View {
    let history: DayHistory
    let corrected: Set<UUID>
    let correct: (@MainActor (HistorySilence) -> Void)?

    @Environment(\.appearanceTraits) private var traits
    @ScaledMetric(relativeTo: .body) private var spacing: CGFloat = 12

    var body: some View {
        VStack(alignment: .leading, spacing: spacing * 2) {
            VStack(alignment: .leading, spacing: spacing / 2) {
                ShellText(.historyHeading, role: .title2)
                    .fontWeight(.semibold)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)

                ShellText(.historyIntroduction, role: .callout)
                    .foregroundStyle(DesignTokens.supportingTextColor(for: traits))
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)

                // **The label that stops the surface making a claim it cannot support.** A
                // priority's words at the moment of a judgement are gone — `revision` counts
                // edits and keeps no prior text — so what is drawn beside a row is today's
                // wording, and saying so is the difference between a record and an implication.
                ShellText(.historyWordingNote, role: .caption)
                    .foregroundStyle(DesignTokens.supportingTextColor(for: traits))
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if history.entries.isEmpty {
                ShellText(.historyEmpty, role: .callout)
                    .foregroundStyle(DesignTokens.supportingTextColor(for: traits))
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(alignment: .leading, spacing: spacing) {
                    // **Newest first.** The value keeps the order the day happened in, because
                    // that is the order the causes run in; a person reading their day back
                    // starts from what just happened.
                    ForEach(history.entries.reversed()) { entry in
                        HistoryRow(
                            entry: entry,
                            wording: history.priorityWording,
                            corrected: corrected,
                            correct: correct
                        )
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(spacing * 2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// One row of the ledger.
struct HistoryRow: View {
    let entry: HistoryEntry
    let wording: [UUID: String]
    let corrected: Set<UUID>
    let correct: (@MainActor (HistorySilence) -> Void)?

    @Environment(\.appearanceTraits) private var traits
    @Environment(\.shellTextScale) private var textScale
    @ScaledMetric(relativeTo: .body) private var spacing: CGFloat = 12

    var body: some View {
        VStack(alignment: .leading, spacing: spacing / 3) {
            HStack(alignment: .firstTextBaseline, spacing: spacing) {
                ShellText(label, role: .headline)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                // The clock reading is data, not prose: `verbatim` is the explicit way to draw
                // something a catalog must never see, and a monospaced digit keeps the column
                // from shuffling as the minute changes.
                Text(verbatim: Self.time.string(from: entry.at))
                    .font(DesignTokens.font(.caption, scale: textScale))
                    .monospacedDigit()
                    .foregroundStyle(DesignTokens.supportingTextColor(for: traits))
            }

            if let subject {
                Text(verbatim: subject)
                    .font(DesignTokens.font(.body, scale: textScale))
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }

            detail

            if let priorityID, let intent = wording[priorityID] {
                HStack(alignment: .firstTextBaseline, spacing: spacing / 2) {
                    ShellText(.historyUnderLabel, role: .caption)
                        .foregroundStyle(DesignTokens.supportingTextColor(for: traits))
                    Text(verbatim: intent)
                        .font(DesignTokens.font(.caption, scale: textScale))
                        .foregroundStyle(DesignTokens.supportingTextColor(for: traits))
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The time of day, in the person's own locale. Fixed to one formatter rather than one per
    /// row: a `DateFormatter` per row on a long day is measurable, and the format is the same.
    static let time: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    private var label: ShellStringKey {
        switch entry {
        case .intervention(let value): value.kind == .query ? .historyRowQuestion : .historyRowAccusation
        case .question: .historyRowQuestion
        case .session: .historyRowSession
        case .silence: .historyRowSilence
        }
    }

    /// The subject as a person calls it, never the bundle key. `SubjectDisplay` refuses the
    /// lookup for an origin by shape, so a site is drawn as a site.
    private var subject: String? {
        switch entry {
        case .intervention(let value):
            value.subject.isEmpty
                ? nil
                : SubjectDisplay.name(of: value.subject, resolvingApplication: value.subjectKind == .app)
        case .question(let value):
            SubjectDisplay.name(of: value.subject, resolvingApplication: value.subjectKind == .app)
        case .session:
            nil
        case .silence(let value):
            SubjectDisplay.name(of: value.subject, resolvingApplication: value.subjectKind == .app)
        }
    }

    private var priorityID: UUID? {
        switch entry {
        case .intervention(let value): value.priorityID
        case .question(let value): value.priorityID
        case .session(let value): value.priorityID
        case .silence(let value): value.priorityID
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch entry {
        case .intervention(let value):
            VStack(alignment: .leading, spacing: spacing / 4) {
                ShellText(resource: value.disposition.historyCopyResource, role: .caption)
                    .foregroundStyle(DesignTokens.supportingTextColor(for: traits))
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                // `nil` where the interruption reached no surface — every deferral and every
                // suppression — which the stored empty string already says.
                if let surface = value.surface {
                    ShellText(resource: surface.historyCopyResource, role: .caption)
                        .foregroundStyle(DesignTokens.supportingTextColor(for: traits))
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let outcome = value.outcome {
                    labelled(.historyOutcomeLabel, resource: outcome.historyCopyResource)
                }
                reasons(value.explanationKinds)
            }

        case .question(let value):
            VStack(alignment: .leading, spacing: spacing / 4) {
                // The one place in the ledger where the *why* was written down at the time
                // rather than reconstructed: `AskedQuestion.reasonRaw` is a stored
                // `QueryableUncertainty`.
                labelled(.verdictReasonsLabel, resource: value.reason.copyResource)
                labelled(.historyAnswerLabel, resource: value.outcome.historyCopyResource)
            }

        case .session:
            EmptyView()

        case .silence(let value):
            correction(for: value)
        }
    }

    /// The explanation kinds, or the sentence that says the app did not record any.
    ///
    /// The label is the verdict inspector's own `Why`, reused rather than duplicated: the two
    /// surfaces are saying the same thing about the same vocabulary, and a second key with the
    /// same word is a second place for it to be translated differently.
    ///
    /// `nil` and `[]` are drawn differently on purpose. `nil` is *"not recorded"* — every row
    /// written before schema v7, and every path that had no explanation to hand. An empty list
    /// would be a claim about the verdict, and the store keeps them apart so the surface can.
    @ViewBuilder
    private func reasons(_ kinds: [ExplanationClauseKind]?) -> some View {
        if let kinds, !kinds.isEmpty {
            ForEach(kinds, id: \.self) { kind in
                labelled(.verdictReasonsLabel, resource: kind.copyResource)
            }
        } else if kinds == nil {
            labelled(.verdictReasonsLabel, key: .historyReasonNotRecorded)
        }
    }

    /// The affordance, or the sentence saying why there is not one (R-88).
    @ViewBuilder
    private func correction(for silence: HistorySilence) -> some View {
        if corrected.contains(silence.id) {
            ShellText(.historyCorrectionWritten, role: .caption)
                .foregroundStyle(DesignTokens.supportingTextColor(for: traits))
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
        } else if case .withdrawn(let reason) = silence.correction {
            // Never a greyed-out control. A button a person cannot account for is worse than no
            // button, so the reason takes the button's place.
            ShellText(resource: reason.copyResource, role: .caption)
                .foregroundStyle(DesignTokens.supportingTextColor(for: traits))
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Button {
                correct?(silence)
            } label: {
                ShellText(.historyCorrectAction, role: .caption)
            }
            .buttonStyle(.bordered)
            .disabled(correct == nil)
        }
    }

    @ViewBuilder
    private func labelled(_ key: ShellStringKey, resource: LocalizedStringResource) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: spacing / 2) {
            ShellText(key, role: .caption)
                .foregroundStyle(DesignTokens.supportingTextColor(for: traits))
            ShellText(resource: resource, role: .caption)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func labelled(_ key: ShellStringKey, key value: ShellStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: spacing / 2) {
            ShellText(key, role: .caption)
                .foregroundStyle(DesignTokens.supportingTextColor(for: traits))
            ShellText(value, role: .caption)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
