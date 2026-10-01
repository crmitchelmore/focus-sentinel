import FocusCore
import SwiftUI

/// Where a person says, in one sentence, what they are trying to do.
///
/// One field, one button, and a strip that only ever appears to *help*. The rules it keeps
/// are the ones F-07 and R-20 are made of:
///
/// * **Set Priority is never disabled by validation and never refuses.** The only thing that
///   disables it is an empty field — there is nothing to commit — or a missing mutation host.
///   A vague sentence does not disable anything.
/// * **The first press of a vague sentence explains instead of committing.** The refinement
///   strip appears with the finding, one rewrite made of the user's own words, and a
///   pre-filled definition of done. Focus stays in the field, so a second Return commits the
///   original sentence unchanged: two keystrokes, worst case, and nothing the user wrote is
///   ever thrown away.
/// * **Refine is available before that**, on demand, whenever the validator has something to
///   say — which is F-18's shipped, always-present, deterministic half.
/// * **Outside English the surface is silent.** `IntentValidator` returns `notAssessable` and
///   neither the strip nor the Refine button appears at all.
///
/// The same view is used by the cockpit and by the global quick-capture panel; the caller
/// supplies the two focus identities so each surface keeps its own Tab order.
public struct CaptureFieldView: View {
    /// Commit: the sentence exactly as typed, and a definition of done if the user took the
    /// suggested one.
    public let commit: (String, String?) -> Void
    /// A second way to commit, bound to ⌘Return, or `nil` where the surface has only one.
    ///
    /// The quick-capture panel is the surface that has two: Return sets the priority, and
    /// ⌘Return sets it *and* puts the user back in the app the hot key interrupted. It goes
    /// through the same validation path as Return, so a vague sentence is explained rather
    /// than committed by either.
    public let alternateCommit: ((String, String?) -> Void)?
    /// Whether a mutation host is attached. A button that looks live and does nothing is
    /// worse than a disabled one.
    public let isEnabled: Bool
    /// The Tab identity of the text field in the surrounding surface.
    public let fieldFocus: FocusField
    /// The Tab identity of the Set Priority button.
    public let buttonFocus: FocusField

    @FocusState.Binding var focus: FocusField?

    @Environment(\.locale) private var locale
    @Environment(\.shellTextScale) private var textScale
    @ScaledMetric(relativeTo: .body) private var spacing: CGFloat = 12

    /// The sentence being typed.
    @State private var text: String = ""
    /// The definition of done, set only by taking the strip's suggestion. Capture itself asks
    /// for one field, not two.
    @State private var doneWhen: String?
    /// The sentence the strip has already been offered for.
    ///
    /// Keyed on the *text* rather than held as a flag, so the state is a pure function of
    /// what is in the field: editing the sentence earns a fresh explanation, and the second
    /// press of an unchanged sentence commits it. A boolean would have to be reset from an
    /// `onChange`, which runs *after* the assignment that set it and would undo it.
    @State private var offeredFor: String?
    /// The sentence the user dismissed the strip for.
    @State private var dismissedFor: String?

    public init(
        commit: @escaping (String, String?) -> Void,
        alternateCommit: ((String, String?) -> Void)? = nil,
        isEnabled: Bool,
        fieldFocus: FocusField,
        buttonFocus: FocusField,
        focus: FocusState<FocusField?>.Binding
    ) {
        self.commit = commit
        self.alternateCommit = alternateCommit
        self.isEnabled = isEnabled
        self.fieldFocus = fieldFocus
        self.buttonFocus = buttonFocus
        self._focus = focus
    }

    /// What the deterministic validator makes of what is typed right now.
    ///
    /// Recomputed on every keystroke, which costs nothing: the validator is a pure function
    /// over a lexicon, with no clock, no store and no model behind it.
    private var assessment: IntentAssessment {
        IntentValidator.assess(text, locale: locale)
    }

    private var trimmed: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Whether there is anything worth saying about what is typed.
    ///
    /// An empty field is not vague, it is empty: the validator reports `tooShort` for it, and
    /// offering to refine nothing would be noise rather than help.
    private var hasAdviceToOffer: Bool {
        !trimmed.isEmpty && assessment.hasSomethingToSay
    }

    /// Whether the strip is on screen right now — derived, never stored.
    private var showsRefinement: Bool {
        hasAdviceToOffer && offeredFor == trimmed && dismissedFor != trimmed
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: spacing / 2) {
            HStack(spacing: spacing) {
                TextField(
                    text: $text,
                    prompt: Text(ShellStrings.resource(.captureFieldPrompt))
                ) {
                    ShellText(.captureFieldLabel)
                }
                .labelsHidden()
                .font(DesignTokens.font(.body, scale: textScale))
                .focused($focus, equals: fieldFocus)
                .disabled(!isEnabled)
                .onSubmit(attemptCommit)
                .accessibilityLabel(Text(ShellStrings.resource(.captureFieldLabel)))
                // Tooltips from the catalog (focus-8ski); a disabled control says why.
                .shellHelp(.captureFieldLabelHelp)

                if hasAdviceToOffer && !showsRefinement {
                    Button {
                        offeredFor = trimmed
                        dismissedFor = nil
                    } label: {
                        ShellText(.captureActionRefine)
                    }
                    .shellHelp(.captureActionRefineHelp)
                }

                Button(action: attemptCommit) {
                    ShellText(.captureActionSet)
                }
                .buttonStyle(.borderedProminent)
                .focused($focus, equals: buttonFocus)
                // Emptiness, and nothing else. A vague sentence is explained, never blocked.
                .disabled(!isEnabled || trimmed.isEmpty)
                .shellHelp(
                    .captureActionSetHelp,
                    disabled: .captureActionSetDisabledHelp,
                    when: !isEnabled || trimmed.isEmpty
                )
            }

            if showsRefinement {
                RefinementStrip(
                    assessment: assessment,
                    apply: apply(rewrite:doneWhen:),
                    dismiss: { dismissedFor = trimmed }
                )
            }
        }
        .background(alternateCommitShortcut)
    }

    /// ⌘Return, where the surface has a second way to commit.
    ///
    /// Zero-opacity rather than `.hidden()`: a hidden view is out of the interaction system
    /// and its key equivalent stops being registered, which would make the shortcut the panel
    /// advertises a lie. Hit testing is off so it can never be clicked by accident, and it
    /// sits in `.background` so it takes no space.
    @ViewBuilder
    private var alternateCommitShortcut: some View {
        if alternateCommit != nil {
            Button {
                attemptCommit(alternate: true)
            } label: {
                EmptyView()
            }
            .keyboardShortcut(.return, modifiers: .command)
            .opacity(0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    // MARK: - Behaviour

    private func attemptCommit() {
        attemptCommit(alternate: false)
    }

    /// Explain once; commit on the next press.
    private func attemptCommit(alternate: Bool) {
        guard isEnabled, !trimmed.isEmpty else { return }

        if hasAdviceToOffer && offeredFor != trimmed {
            offeredFor = trimmed
            dismissedFor = nil
            // Focus deliberately stays in the field: the promise is that pressing Return a
            // second time commits the user's own words. Moving focus to the suggestion would
            // make the *suggestion* the easy path, which is the opposite of the promise.
            focus = fieldFocus
            return
        }

        if alternate, let alternateCommit {
            alternateCommit(trimmed, doneWhen)
        } else {
            commit(trimmed, doneWhen)
        }
        reset()
    }

    /// Take the suggestion into the field. It is still only text in a field — nothing is
    /// committed until the user says so.
    private func apply(rewrite: String, doneWhen suggestedDoneWhen: String?) {
        let rewritten = rewrite.trimmingCharacters(in: .whitespacesAndNewlines)
        text = rewrite
        doneWhen = suggestedDoneWhen
        // The suggestion has been seen and taken, so the strip closes and a Return now
        // commits rather than explaining the same sentence back at the user.
        offeredFor = rewritten
        dismissedFor = rewritten
        focus = fieldFocus
    }

    private func reset() {
        text = ""
        doneWhen = nil
        offeredFor = nil
        dismissedFor = nil
    }
}
