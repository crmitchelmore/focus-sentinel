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
            ShellText(.priorityRulesHeading, role: .caption)
                .foregroundStyle(DesignTokens.supportingTextColor(for: traits))

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
                .accessibilityLabel(Text(ShellStrings.resource(Self.scopeKey(rule.scope))))

            // The subject is the user's own material — a bundle identifier, an origin, a word.
            Text(verbatim: rule.subject)
                .font(DesignTokens.font(.callout, scale: textScale))
                .lineLimit(1)

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
                .disabled(change == nil)
                .accessibilityLabel(Text(ShellStrings.resource(Self.verdictKey(verdict))))
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
            HStack(spacing: spacing / 2) {
                ForEach(Self.authorableScopes) { candidate in
                    Button {
                        scope = candidate
                    } label: {
                        ShellText(Self.scopeKey(candidate), role: .caption)
                    }
                    .buttonStyle(.bordered)
                    .tint(scope == candidate ? DesignTokens.Palette.accent(for: traits) : nil)
                }

                Spacer(minLength: 0)
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

                Button { addRule(.relevant) } label: {
                    ShellText(.priorityRulesActionAddRelated, role: .callout)
                }
                .disabled(trimmedSubject.isEmpty)

                Button { addRule(.unrelated) } label: {
                    ShellText(.priorityRulesActionAddUnrelated, role: .callout)
                }
                .disabled(trimmedSubject.isEmpty)

                Spacer(minLength: 0)
            }
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
    /// long a rule lives, and it is set by the code paths that make a rule temporary.
    static let authorableScopes: [PriorityRuleScope] = [.app, .domain, .titleToken]

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
    /// Total on `decisiveDispositions` by construction — `isDecisive` is exactly
    /// *"`ruleVerdict` is not `nil`"* — and `RelevanceSeedTests` already asserts the round trip
    /// is the identity on `allCases`. The `preconditionFailure` is unreachable and says so:
    /// a crash here would mean the two definitions had come apart, which is a programming error
    /// rather than a runtime condition.
    nonisolated static func verdict(of disposition: AppRuleDisposition) -> PriorityRuleVerdict {
        guard let verdict = disposition.ruleVerdict else {
            preconditionFailure("\(disposition.rawValue) is not a stored rule verdict")
        }
        return verdict
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
