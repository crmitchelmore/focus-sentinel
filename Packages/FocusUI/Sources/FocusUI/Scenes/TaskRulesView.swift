import FocusCore
import SwiftUI

/// Rules scoped to this priority (F-11).
///
/// A rule says one thing: *this app / this site / this word* is related to what I am doing, or
/// it is not, or I have not decided. Scoped to the task, so it cascades away with it, and
/// immediately visible to the store e04's engine will read.
///
/// Three deliberate shapes:
///
/// * **Changing a verdict is a change, not a delete and a re-add.** The row keeps its identity
///   and its place in the list, and the undo journal records one step rather than two.
/// * **`Undecided` is a real answer.** It is never treated as *unrelated* — that distinction
///   is the whole of standing condition 6, and offering only two buttons would quietly erase
///   it.
/// * **Buttons, not menus.** A `Picker` or `Menu` here would be an AppKit-backed control that
///   does not rasterise under `ImageRenderer`, so the committed baselines would be pictures of
///   a placeholder rather than of the pane.
public struct TaskRulesView: View {
    public let rules: [PriorityRuleValue]
    public let add: ((PriorityRuleScope, String, PriorityRuleVerdict) -> Void)?
    public let change: ((UUID, PriorityRuleVerdict) -> Void)?
    public let remove: ((UUID) -> Void)?

    @Environment(\.appearanceTraits) private var traits
    @Environment(\.shellTextScale) private var textScale
    @FocusState.Binding var focus: FocusField?
    @ScaledMetric(relativeTo: .body) private var spacing: CGFloat = 8

    @State private var subject: String = ""
    @State private var scope: PriorityRuleScope = .app

    public init(
        rules: [PriorityRuleValue],
        add: ((PriorityRuleScope, String, PriorityRuleVerdict) -> Void)? = nil,
        change: ((UUID, PriorityRuleVerdict) -> Void)? = nil,
        remove: ((UUID) -> Void)? = nil,
        focus: FocusState<FocusField?>.Binding
    ) {
        self.rules = rules
        self.add = add
        self.change = change
        self.remove = remove
        self._focus = focus
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            CompanionSectionHeading(key: .priorityRulesHeading, symbol: "line.3.horizontal.decrease")
                .foregroundStyle(DesignTokens.Palette.role(.spruce, for: traits))

            if rules.isEmpty {
                ShellText(.priorityRulesEmpty, role: .callout)
                    .foregroundStyle(DesignTokens.supportingTextColor(for: traits))
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(rules) { rule in
                    row(rule)
                }
            }

            if add != nil {
                composer
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - One rule

    private func row(_ rule: PriorityRuleValue) -> some View {
        HStack(spacing: spacing) {
            Image(systemName: rule.scope.symbolName)
                .foregroundStyle(DesignTokens.supportingTextColor(for: traits))
                .accessibilityLabel(Text(ShellStrings.resource(Self.scopeKey(for: rule))))

            // The subject is the user's own material — a bundle identifier, an origin, a word —
            // and only the last of those three is already something to read. `rule.subject` is
            // the key the cascade matches on and stays untouched; this row draws the other half
            // (focus-7zr). It was the key, so the list said `com.apple.Safari` and
            // `https://news.example.com` beside a chip row saying `Safari` and
            // `docs.example.com` — one window, one kind of thing, two names for it.
            Text(verbatim: SubjectDisplay.name(of: rule))
                .font(DesignTokens.font(.callout, scale: textScale))
                .lineLimit(1)

            // **A retired row says so, in words** (e07a). A word-shaped title-token rule is a
            // promise the product does not keep — nothing in the shipping app produces a title
            // word — so a stored one is drawn as what it is: kept, deletable, and no longer
            // read. An item rule (issue #24) is the same scope and is live, so it is not. Its verdict
            // controls are withdrawn below; a picker over a rule nothing reads would be a knob
            // wired to nothing.
            if rule.isRetired {
                ShellText(.priorityRulesScopeRetired, role: .caption)
                    .foregroundStyle(DesignTokens.supportingTextColor(for: traits))
                    .lineLimit(1)
            } else if !rule.scope.isObserved {
                // Kept and deletable if a future build cannot observe this scope.
                ShellText(.priorityRulesScopeUnobserved, role: .caption)
                    .foregroundStyle(DesignTokens.supportingTextColor(for: traits))
                    .lineLimit(1)
                    .shellHelp(.priorityRulesScopeUnobservedHelp)
            }

            Spacer(minLength: spacing)

            // **The picker is F-130's disposition vocabulary, not a private list of three.**
            //
            // The four dispositions the registry names map totally and reversibly onto the
            // shipped rule vocabulary with no schema change (plan R-64): three are stored
            // verdicts and the fourth — *interpret by context* — is the **absence of a row**,
            // which is why it is the control below rather than a fourth button here. Driving
            // the loop from `AppRuleDisposition` is what keeps that mapping a property of the
            // surface rather than a coincidence: a fifth disposition would appear here, and a
            // disposition that stopped being decisive would leave.
            ForEach(Self.decisiveDispositions) { disposition in
                let verdict = Self.verdict(of: disposition)
                Button {
                    change?(rule.id, verdict)
                } label: {
                    Image(systemName: verdict.symbolName)
                        .symbolVariant(rule.verdict == verdict ? .fill : .none)
                }
                // `.plain`, not `.borderless`: the borderless style is AppKit-backed and
                // draws SwiftUI's unrenderable-view placeholder under `ImageRenderer`, which
                // would make the committed baselines pictures of a broken control.
                .buttonStyle(.plain)
                .foregroundStyle(
                    rule.verdict == verdict
                        ? DesignTokens.Palette.primaryText
                        : DesignTokens.supportingTextColor(for: traits)
                )
                .disabled(change == nil || Self.isInert(rule))
                // A `.plain` button draws no disabled state of its own, and a control that looks
                // live and does nothing is the silent nothing this pane exists to avoid — so a
                // retired row's controls are dimmed as well as withdrawn.
                .opacity(Self.isInert(rule) ? 0.35 : 1)
                .accessibilityLabel(Text(ShellStrings.resource(Self.verdictKey(verdict))))
                // The checkmark symbol supplies a selected trait even when its rule is not
                // related. Override that inferred state before announcing the actual verdict.
                .accessibilityRemoveTraits(rule.verdict == verdict ? [] : [.isSelected])
                .accessibilityAddTraits(rule.verdict == verdict ? [.isSelected] : [])
                // The disposition's own name, from `FocusCore`'s catalog. The glyph and the
                // short verdict word are what the row has room for; this is where the four
                // dispositions are named in full, without costing the row a pixel.
                .help(Text(disposition.labelResource))
            }

            if let remove {
                Button {
                    remove(rule.id)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(DesignTokens.supportingTextColor(for: traits))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(ShellStrings.resource(.priorityRulesActionRemove)))
                // Removing the row **is** `interpretByContext`: with no rule about this subject
                // the cascade falls through to the heuristic, which is exactly what "interpret
                // by context" means. Naming it here is what makes the fourth disposition
                // reachable rather than implied.
                .help(Text(AppRuleDisposition.interpretByContext.labelResource))
            }
        }
    }

    // MARK: - Authoring one

    private var composer: some View {
        VStack(alignment: .leading, spacing: spacing / 2) {
            // One scope is not a choice, so a lone scope draws no picker (focus-6ji4).
            if Self.authorableScopes.count > 1 {
                scopePicker
            }

            HStack(spacing: spacing) {
                TextField(
                    text: $subject,
                    prompt: Text(ShellStrings.resource(.priorityRulesSubjectPrompt))
                ) {
                    ShellText(.priorityRulesSubjectPrompt)
                }
                .labelsHidden()
                .font(DesignTokens.font(.callout, scale: textScale))
                .focused($focus, equals: .cockpitRuleSubject)
                .onSubmit { addRule(.relevant) }
                .accessibilityLabel(Text(ShellStrings.resource(.priorityRulesSubjectPrompt)))
                .shellHelp(.priorityRulesSubjectPromptHelp)

                Button { addRule(.relevant) } label: {
                    ShellText(.priorityRulesActionAddRelated, role: .callout)
                }
                .disabled(trimmedSubject.isEmpty)
                .shellHelp(
                    .priorityRulesActionAddRelatedHelp,
                    disabled: .priorityRulesSubjectDisabledHelp,
                    when: trimmedSubject.isEmpty
                )

                Button { addRule(.unrelated) } label: {
                    ShellText(.priorityRulesActionAddUnrelated, role: .callout)
                }
                .disabled(trimmedSubject.isEmpty)
                .shellHelp(
                    .priorityRulesActionAddUnrelatedHelp,
                    disabled: .priorityRulesSubjectDisabledHelp,
                    when: trimmedSubject.isEmpty
                )

                Spacer(minLength: 0)
            }
        }
    }

    private var scopePicker: some View {
        HStack(spacing: spacing / 2) {
            ForEach(Self.authorableScopes) { candidate in
                Button {
                    scope = candidate
                } label: {
                    ShellText(Self.scopeKey(candidate), role: .caption)
                }
                .buttonStyle(.bordered)
                .tint(scope == candidate ? DesignTokens.Palette.accent(for: traits) : nil)
                // Tooltips from the catalog (focus-8ski); the verdict glyphs above carry
                // `FocusCore`'s disposition names and are left as they are.
                .shellHelp(.priorityRulesScopeHelp)
            }

            Spacer(minLength: 0)
        }
    }

    private var trimmedSubject: String {
        subject.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func addRule(_ verdict: PriorityRuleVerdict) {
        guard !trimmedSubject.isEmpty else { return }
        add?(scope, normalisedSubject, verdict)
        subject = ""
    }

    /// A subject is stored normalised, so that a rule written by hand and one learned from a
    /// real observation are the same rule.
    ///
    /// A site is reduced to its origin — never a full URL, never a path (SC-3) — and a word is
    /// lowercased. A bundle identifier is left exactly as typed, because case is part of it.
    private var normalisedSubject: String {
        switch scope {
        case .domain:
            OriginNormalizer.normalize(trimmedSubject) ?? trimmedSubject.lowercased()
        case .titleToken, .session:
            trimmedSubject.lowercased()
        case .app:
            trimmedSubject
        }
    }

    /// The scopes a person can author by hand. `.session` is not one of them: it describes how
    /// long a rule lives, and it is set by the code paths that make a rule temporary. And since
    /// e07a `.titleToken` is not one of them either: it was offered for the whole of e04–e06 and
    /// could never match, because nothing in the shipping app produces a title token (PD-1) — an
    /// authoring affordance for a rule nothing reads is a lie in a button. Derived from the
    /// vocabulary rather than written out, so a scope that retires leaves this list the same day.
    ///
    /// `.domain` is withdrawn on the same argument while the shipping app reads no site
    /// (focus-6ji4, `ShippingObservation`): a site rule is stored and can never match. It comes
    /// back by itself the day `isObserved` says it can.
    static let authorableScopes: [PriorityRuleScope] = PriorityRuleScope.allCases.filter {
        $0 != .session && !$0.isRetired && $0.isObserved
    }

    /// Whether a stored rule is drawn read-only: retired (a word-shaped title-token row, not an
    /// item one — issue #24), or of a scope not observable in this version. Its verdict controls
    /// are withdrawn; its remove control stays.
    static func isInert(_ rule: PriorityRuleValue) -> Bool {
        rule.isRetired || !rule.scope.isObserved
    }

    /// The dispositions that are a stored row, in `AppRuleDisposition.allCases` order.
    ///
    /// `interpretByContext` is excluded because it is *not* a row: it is the absence of one,
    /// and the row's remove control is how a person reaches it. Filtered from `allCases`
    /// through `isDecisive` rather than written out, so the two can never disagree about which
    /// dispositions the store can hold.
    nonisolated static var decisiveDispositions: [AppRuleDisposition] {
        AppRuleDisposition.allCases.filter(\.isDecisive)
    }

    /// The verdict a decisive disposition is stored as.
    ///
    /// **An exhaustive `switch` with no `default`, and that is the repair** (focus-tzj.7). This
    /// was a `guard let … else { preconditionFailure(…) }` on `ruleVerdict`, justified by the
    /// two definitions agreeing today. What such a guard buys is a **runtime crash** on the day
    /// somebody adds a fifth disposition: the compiler says nothing, every test that does not
    /// happen to reach the new case stays green, and the app traps in front of a person who
    /// opened the Rules pane. Written as a fold over the cases, the same day's work is a build
    /// error in this file, which is where the decision belongs.
    ///
    /// `.interpretByContext` is the one case that stores no verdict, and it answers `.uncertain`
    /// — the verdict whose whole meaning is *"ask"*, which is what interpreting by context is.
    /// It is unreachable from the pane (`decisiveDispositions` excludes it) and it is a real
    /// answer rather than a trap, so a future caller that forgets the filter gets a question
    /// rather than a crash.
    nonisolated static func verdict(of disposition: AppRuleDisposition) -> PriorityRuleVerdict {
        switch disposition {
        case .alwaysRelevant: .relevant
        case .alwaysDistracting: .unrelated
        case .askEachTime: .uncertain
        case .interpretByContext: .uncertain
        }
    }

    /// The scope label for one stored row: an item selected inside an application (issue #24)
    /// is a `.titleToken` row, and is called what it is rather than "word in a title".
    static func scopeKey(for rule: PriorityRuleValue) -> ShellStringKey {
        rule.isSelectedItem ? .priorityRulesScopeSelectedItem : scopeKey(rule.scope)
    }

    static func scopeKey(_ scope: PriorityRuleScope) -> ShellStringKey {
        switch scope {
        case .app: .priorityRulesScopeApp
        case .domain: .priorityRulesScopeDomain
        case .titleToken: .priorityRulesScopeTitleToken
        case .session: .priorityRulesScopeSession
        }
    }

    static func verdictKey(_ verdict: PriorityRuleVerdict) -> ShellStringKey {
        switch verdict {
        case .relevant: .priorityRulesVerdictRelevant
        case .unrelated: .priorityRulesVerdictUnrelated
        case .uncertain: .priorityRulesVerdictUncertain
        }
    }
}
