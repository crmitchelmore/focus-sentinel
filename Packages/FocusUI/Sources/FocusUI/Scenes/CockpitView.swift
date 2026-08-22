import FocusCore
import SwiftUI

/// The cockpit: one column, no sidebar, no custom chrome, no analytics.
///
/// Deliberately **not** a `NavigationSplitView`. A sidebar ships in e09, with its last real
/// destination; an empty "Insights" row today would be a surface with nothing behind it.
///
/// The column reads top to bottom in the order the user thinks: what am I doing (the hero),
/// how will I know it is finished (the definition of done), and then the one primary action.
/// Everything below the hero is at `.body` or smaller, which is what makes F-02's "always
/// more prominent than any analytics" structural — see `DesignTokens.FontRole.priorityHero`
/// and `TypeHierarchyTests`.
///
/// Everything that has to survive an accessibility text size is written for it: spacing is
/// `@ScaledMetric`, the header collapses from a row to a column through `ViewThatFits` — the
/// status badge drops to a second line before the hero yields any width — and every label
/// that carries meaning is `lineLimit(nil)` and free to grow vertically.
///
/// The view renders a `CockpitState` and calls a `PriorityActing`, both declared in
/// `FocusCore`. It never opens a store (R-24).
public struct CockpitView: View {
    public let state: CockpitState

    /// The mutation host, or `nil` when none is attached.
    ///
    /// `nil` is not a placeholder: it is the read-only cockpit, which is exactly what the
    /// snapshot lane renders and what the app shows in the moment before its host exists.
    /// Every control that would mutate the store is disabled while it is `nil`, so a button
    /// can never look live and do nothing.
    public let actions: (any PriorityActing)?

    @Environment(\.appearanceTraits) private var traits
    @Environment(\.openSettings) private var openSettings
    @Environment(\.shellTextScale) private var textScale
    @FocusState private var focus: FocusField?

    /// The definition of done, while it is being edited. Committed on Return and on losing
    /// focus; re-seeded whenever the priority underneath it changes.
    @State private var doneWhenDraft: String = ""

    /// Whether the capture field is open while a priority already exists — the "change my
    /// mind" path. With no priority the field is always open, because it is the only thing
    /// the window is for.
    @State private var isCapturing: Bool = false

    @ScaledMetric(relativeTo: .body) private var rowSpacing: CGFloat = 12
    @ScaledMetric(relativeTo: .largeTitle) private var sectionSpacing: CGFloat = 20

    public init(state: CockpitState, actions: (any PriorityActing)? = nil) {
        self.state = state
        self.actions = actions
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: sectionSpacing) {
            header

            if let priority = state.priority {
                doneWhenSection(priority)
            }

            if showsCapture {
                capture
            }

            if let priority = state.priority {
                primaryActions(priority)
            }

            footer

            Spacer(minLength: 0)
        }
        .padding(sectionSpacing)
        .frame(minWidth: 420, minHeight: 260, alignment: .topLeading)
        .background(DesignTokens.Palette.windowBackground)
        .defaultFocus($focus, .cockpitOpenSettings)
        // The window is named for the app; the group is too, so VoiceOver announces what it
        // has landed in before reading the priority out of it.
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(ShellStrings.resource(.cockpitHeading)))
        .onAppear { doneWhenDraft = state.priority?.doneWhen ?? "" }
        .onChange(of: state.priority?.id) { doneWhenDraft = state.priority?.doneWhen ?? "" }
        .onChange(of: state.priority?.doneWhen) { doneWhenDraft = state.priority?.doneWhen ?? "" }
    }

    // MARK: - The hero

    /// The priority and the status badge, side by side while both fit.
    ///
    /// `ViewThatFits` tries the row first and falls back to the column, so what gives way
    /// under pressure is the *badge's* place on the line — never the hero's width. The hero
    /// is therefore free to wrap to as many lines as the sentence needs.
    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: rowSpacing) {
                hero
                Spacer(minLength: rowSpacing)
                StatusBadge(status: state.status)
            }
            VStack(alignment: .leading, spacing: rowSpacing) {
                hero
                StatusBadge(status: state.status)
            }
        }
    }

    private var hero: some View {
        PriorityHeroView(intent: state.priority?.intent)
    }

    // MARK: - Definition of done (F-08)

    /// One optional line, directly under the hero, editable in place.
    ///
    /// Optional at capture and optional forever: an empty definition of done is a legitimate
    /// answer, so there is no validation here and nothing is ever refused. The field commits
    /// on Return and on losing focus, because a person who types a sentence and then clicks
    /// elsewhere has not asked to throw it away.
    @ViewBuilder
    private func doneWhenSection(_ priority: PrioritySnapshot) -> some View {
        VStack(alignment: .leading, spacing: rowSpacing / 3) {
            ShellText(.priorityDoneWhenLabel, role: .caption)
                .foregroundStyle(DesignTokens.supportingTextColor(for: traits))

            if actions == nil {
                // Read-only: the value, not a control. See `showsCapture` for why a cockpit
                // with no host draws no fields.
                Text(verbatim: priority.doneWhen ?? "")
                    .font(DesignTokens.font(.body, scale: textScale))
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                TextField(
                    text: $doneWhenDraft,
                    prompt: Text(ShellStrings.resource(.priorityDoneWhenPrompt))
                ) {
                    ShellText(.priorityDoneWhenLabel)
                }
                .labelsHidden()
                .font(DesignTokens.font(.body, scale: textScale))
                .focused($focus, equals: .cockpitDoneWhen)
                .onSubmit { commitDoneWhen(priority) }
                .onChange(of: focus) { _, newValue in
                    if newValue != .cockpitDoneWhen { commitDoneWhen(priority) }
                }
                .accessibilityLabel(Text(ShellStrings.resource(.priorityDoneWhenLabel)))
            }
        }
    }

    private func commitDoneWhen(_ priority: PrioritySnapshot) {
        let trimmed = doneWhenDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let stored = trimmed.isEmpty ? nil : trimmed
        guard stored != priority.doneWhen else { return }
        actions?.editDoneWhen(taskID: priority.id, to: stored)
    }

    // MARK: - Actions

    /// One primary action, and nothing that competes with it.
    ///
    /// Complete is the default action whenever there is something to complete — it is the
    /// only thing a person does *to* a priority that ends it. Clear is beside it because
    /// putting the priority down is not the same as finishing it, and an app that only offers
    /// "done" teaches people to lie to it.
    /// The capture field is always open when there is nothing to work on — that is the only
    /// thing an empty cockpit is for — and opens on demand when there is.
    ///
    /// With no mutation host it is not shown at all, rather than shown disabled: a field a
    /// person can type a sentence into that then goes nowhere is worse than no field. That is
    /// also what keeps the committed baselines honest — measured on this machine, an
    /// AppKit-backed `TextField` does not rasterise under `ImageRenderer` and draws SwiftUI's
    /// yellow "unrenderable view" placeholder, so a read-only render is a picture of the
    /// cockpit rather than a picture of a broken control.
    private var showsCapture: Bool {
        actions != nil && (state.priority == nil || isCapturing)
    }

    /// One sentence in, one priority out.
    ///
    /// Committing while a priority already exists **replaces** it: a second activation
    /// replaces, never queues (F-02), and the replaced task keeps every word, context item
    /// and rule it had, because the store re-points a pointer rather than deleting a row.
    private var capture: some View {
        CaptureFieldView(
            commit: { intent, doneWhen in
                actions?.setPriority(intent: intent, doneWhen: doneWhen)
                isCapturing = false
            },
            isEnabled: actions != nil,
            fieldFocus: .cockpitCaptureField,
            buttonFocus: .cockpitSetPriority,
            focus: $focus
        )
    }

    private func primaryActions(_ priority: PrioritySnapshot) -> some View {
        HStack(spacing: rowSpacing) {
            Button {
                actions?.complete(taskID: priority.id, shipped: nil, restartPoint: nil)
            } label: {
                ShellText(.priorityActionComplete)
            }
            // Return belongs to whichever surface the user is actually in: while the capture
            // field is open, its own submit is the primary gesture, and two default actions
            // in one window is a coin toss the user has to lose to find out about.
            .keyboardShortcut(showsCapture ? nil : .defaultAction)
            .focused($focus, equals: .cockpitComplete)
            .disabled(actions == nil)

            if !showsCapture {
                Button {
                    isCapturing = true
                    focus = .cockpitCaptureField
                } label: {
                    ShellText(.priorityActionChange)
                }
                .disabled(actions == nil)
            }

            Button {
                actions?.clear()
            } label: {
                ShellText(.priorityActionClear)
            }
            .disabled(actions == nil)

            Spacer(minLength: 0)
        }
    }

    // MARK: - What the app can honestly say about itself

    /// Two quiet lines at the bottom — whether anything is being saved, and whether anything
    /// is being observed — and the route to Settings.
    ///
    /// All three are `.footnote` or a plain link. Settings was e01's most prominent control
    /// and is deliberately demoted here: it is a route, not an action, and nothing in this
    /// window may compete with the priority for the eye.
    private var footer: some View {
        VStack(alignment: .leading, spacing: rowSpacing / 2) {
            detail(
                systemImage: state.storeIsReady
                    ? "internaldrive.fill"
                    : "exclamationmark.triangle.fill",
                key: state.storeIsReady ? .cockpitStoreReady : .cockpitStoreUnavailable
            )
            detail(
                systemImage: state.isObservingActivity ? "eye" : "eye.slash",
                key: .cockpitSensingUnavailable
            )

            Button {
                openSettings()
            } label: {
                ShellText(.cockpitOpenSettings, role: .footnote)
            }
            // Deliberately the system's own button style. `.link` is AppKit-backed and does
            // not rasterise under `ImageRenderer` — measured on this machine, it renders as
            // SwiftUI's yellow "unrenderable view" placeholder — so a link here would mean
            // committing a picture of a broken render and calling it a baseline.
            .focused($focus, equals: .cockpitOpenSettings)
        }
    }

    /// One supporting line: a glyph, then text that is free to wrap as far as it needs to.
    private func detail(systemImage: String, key: ShellStringKey) -> some View {
        Label {
            ShellText(key, role: .footnote)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: systemImage)
        }
        .foregroundStyle(DesignTokens.supportingTextColor(for: traits))
    }
}
