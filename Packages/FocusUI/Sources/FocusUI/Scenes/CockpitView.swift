import FocusCore
import SwiftUI

/// The cockpit: one column, no sidebar, no custom chrome, no analytics.
///
/// Deliberately **not** a `NavigationSplitView`. A sidebar ships in e09, with its last real
/// destination; an empty "Insights" row today would be a surface with nothing behind it.
///
/// The column reads top to bottom in the order the user thinks: what am I doing (the hero),
/// how will I know it is finished (the definition of done), the verbs that act on it, and then
/// the machinery — the time, on one well; what belongs, on another — with the history and the
/// instrument strip under them (focus-6uya). Every section name is `.sectionHeading`, one step
/// under `largeTitle`, and nothing else is above `.body`, which is what makes F-02's "always
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

    /// The session host, or `nil` when none is attached. Same rule as `actions`: every session
    /// control is disabled while it is `nil`.
    public let sessionActions: (any SessionActing)?

    /// How long the session has been running on the wall clock, read by whoever owns the
    /// injected clock. `nil` when nobody has read one.
    ///
    /// Passed in rather than computed here for the reason the whole programme is built on:
    /// there is no timer object anywhere, and `FocusUI` reads no clock. The figure is a value
    /// somebody chose an instant for, which is what makes this window renderable at a fixed
    /// instant in the snapshot lane.
    public let sessionElapsedSeconds: Double?

    /// The last application in front that was not this one, as a bundle identifier (F-101).
    /// Handed to the interruption sheet and nowhere else.
    public let lastActiveBundleID: String?

    /// Where the File menu's commands arrive. Injectable so a test can drive the cockpit the
    /// way ⌘N does, without a menu bar.
    public let commandCenter: FocusCommandCenter

    @Environment(\.appearanceTraits) private var traits
    @Environment(\.openSettings) private var openSettings
    @Environment(\.shellTextScale) private var textScale
    @FocusState private var focus: FocusField?

    /// The definition of done, while it is being edited. Committed on Return and on losing
    /// focus; re-seeded whenever the priority underneath it changes.
    @State private var doneWhenDraft: String = ""
    @State private var contentWidth: CGFloat = 0

    /// Whether the capture field is open while a priority already exists — the "change my
    /// mind" path. With no priority the field is always open, because it is the only thing
    /// the window is for.
    @State private var isCapturing: Bool = false

    /// Whether the completion sheet is up. Completing is a deliberate act with two things
    /// worth recording, so it gets a sheet rather than happening under the pointer.
    @State private var isCompleting: Bool = false

    /// Whether the priority's own sentence is being corrected in place.
    ///
    /// A different act from capture, and a different verb: this keeps the task, its context
    /// pack and its rules and bumps the revision, where committing the capture field starts a
    /// new commitment and pushes this one into history.
    @State private var isEditingIntent: Bool = false

    /// The sentence while it is being corrected. Seeded from the stored intent when the editor
    /// opens, discarded on Escape.
    @State private var intentDraft: String = ""

    /// Bumped when the File menu's ⌘O arrives, which is how a menu item reaches a sheet that
    /// belongs to a subview.
    @State private var fileImportToken: Int = 0

    @ScaledMetric(relativeTo: .body) private var rowSpacing: CGFloat = 12
    @ScaledMetric(relativeTo: .largeTitle) private var sectionSpacing: CGFloat = 20
    /// The inset of a well's content from its edge, and the radius of that edge.
    @ScaledMetric(relativeTo: .body) private var wellInset: CGFloat = 14
    @ScaledMetric(relativeTo: .body) private var wellRadius: CGFloat = 8

    /// What the view reports when its body is evaluated.
    ///
    /// `nil` for every caller that builds the view out of loose values — the snapshot lane, the
    /// preview, the unit tests — and the composition root's own receipt for the one caller that
    /// matters, the scene in `App/` (focus-2er).
    private let didRender: (@MainActor () -> Void)?

    /// Which issue of the connection this window is drawing from, and where the values it drew
    /// are delivered (focus-h7h). `nil`/`0` for every caller that builds the view out of loose
    /// values — the snapshot lane, the previews, the unit tests.
    private let generation: Int
    private let didDraw: (@MainActor (ShellRenderedValues) -> Void)?

    /// What the footer's one-time launch-at-login offer performs (D-12, focus-odz.4).
    private let onLaunchAtLoginOffer: (LaunchAtLoginOfferAction) -> Void
    /// What the first-run explanation's one button performs (focus-odz.7).
    private let onFirstRunExplanationDismissed: () -> Void

    public init(
        state: CockpitState,
        actions: (any PriorityActing)? = nil,
        sessionActions: (any SessionActing)? = nil,
        sessionElapsedSeconds: Double? = nil,
        lastActiveBundleID: String? = nil,
        onLaunchAtLoginOffer: @escaping (LaunchAtLoginOfferAction) -> Void = { _ in },
        onFirstRunExplanationDismissed: @escaping () -> Void = {},
        commandCenter: FocusCommandCenter = .shared
    ) {
        self.state = state
        self.actions = actions
        self.sessionActions = sessionActions
        self.sessionElapsedSeconds = sessionElapsedSeconds
        self.lastActiveBundleID = lastActiveBundleID
        self.onLaunchAtLoginOffer = onLaunchAtLoginOffer
        self.onFirstRunExplanationDismissed = onFirstRunExplanationDismissed
        self.commandCenter = commandCenter
        self.didRender = nil
        self.generation = 0
        self.didDraw = nil
    }

    /// **The application scene's initialiser, and the only one it can reach** (focus-2er).
    ///
    /// One argument instead of five, because five arguments read off the composition root are
    /// five independently guttable one-line no-ops in a file no test bundle can import — and all
    /// five survived a nineteen-stage gate byte for byte. `CockpitConnection` is assembled in
    /// `FocusHost`, where `AppCompositionTests` asserts it field by field, and cannot be
    /// fabricated in a scene: it needs the app's one `PriorityActing` and its one
    /// `SessionActing`.
    public init(connection: CockpitConnection, commandCenter: FocusCommandCenter = .shared) {
        self.state = connection.state
        self.actions = connection.actions
        self.sessionActions = connection.sessionActions
        self.sessionElapsedSeconds = connection.sessionElapsedSeconds
        self.lastActiveBundleID = connection.lastActiveBundleID
        self.onLaunchAtLoginOffer = connection.onLaunchAtLoginOffer
        self.onFirstRunExplanationDismissed = connection.onFirstRunExplanationDismissed
        self.commandCenter = commandCenter
        self.didRender = connection.didRender
        self.generation = connection.generation
        self.didDraw = connection.didDraw
    }

    /// Every verb this window can perform, built from the host and the current priority.
    ///
    /// The view draws these and `CockpitActionsTests` drives them, so "reachable from the
    /// cockpit" is a checked property rather than a claim — see `CockpitWiring`.
    private var wiring: CockpitWiring {
        CockpitWiring(actions: actions, priority: state.priority)
    }

    public var body: some View {
        // The far end of the scene's one wire (focus-2er). A connection that never reached a
        // view body reports nothing, so a scene that asked the composition root and then drew
        // something else is caught by the same assertion that catches a scene that never asked.
        // Idempotent: the root records it in a `Set`, and this view holds no state it could
        // disturb.
        let _ = didRender?()
        VStack(alignment: .leading, spacing: sectionSpacing) {
            CompanionHeader { ShellText(.cockpitWindowTitle, role: .title2) }
            // **One derivation, two consumers** (focus-7ow). The banner is on the screen exactly
            // when this is not `nil`, and that is exactly what the receipt reports — so a
            // mutation that shows the start-of-day ritual when it should not, or never shows it
            // when it should, changes the reported value with it. It was drawn from
            // `state.showsRitualPrompt` and reported nowhere.
            let ritualDismissal = state.showsRitualPrompt ? wiring.dismissRitual : nil
            if let dismissRitual = ritualDismissal {
                RitualBanner(
                    answer: {
                        dismissRitual()
                        isCapturing = true
                        focus = .cockpitCaptureField
                    },
                    dismiss: dismissRitual,
                    focus: $focus
                )
            }
            VStack(alignment: .leading, spacing: rowSpacing) {
            header
                .shellRendered(.ritualBanner, ritualDismissal == nil ? "hidden" : "shown")
                // **The sections that only exist while there is a commitment still report**
                // (focus-7ow). A field nobody reported is indistinguishable from a section
                // somebody deleted, so a cockpit with nothing committed to says so in the same
                // vocabulary the composition root expects it in.
                //
                // A **background** rather than a sibling in the column, and that is measured: a
                // zero-height `Color.clear` is still a `VStack` child and still takes the stack's
                // spacing, which moved every committed cockpit baseline by 20 points. A
                // background proposes no size and is exactly how `shellRendered(_:_:)` itself
                // reaches the preference channel.
                .background(absentCommitmentReceipts)

            if let priority = state.priority {
                // **The commitment zone** (focus-6uya): the definition of done and the verbs
                // that act on the priority, directly under the hero. The verbs used to sit
                // between the rules pane and the history, an orphan row a long way from the
                // thing they finish, change or clear.
                doneWhenSection(priority)
                primaryActions(priority)
            }

            }
            .companionSurface(accent: state.priority != nil)

            if showsCapture {
                capture
            }

            if let priority = state.priority {
                let columns = contentWidth >= 800 && textScale == .standard
                    ? AnyLayout(HStackLayout(alignment: .top, spacing: sectionSpacing))
                    : AnyLayout(VStackLayout(alignment: .leading, spacing: sectionSpacing))
                columns {
                    well {
                        timeboxSection(priority)
                        Divider()
                        sessionSection
                    }
                    well {
                        contextSection(priority)
                        Divider()
                        rulesSection(priority)
                    }
                }

            }

            RecentPrioritiesView(rows: state.recent, activate: wiring.activate)
                // **What is in the rows, not only how many** (focus-7ow). `recentCount` alone was
                // satisfied by a list of the right length holding somebody else's history, and it
                // was reported from the column rather than from the list that draws it.
                .shellRendered(.recentCount, state.recent.count)
                .shellRendered(.recentDigest, ShellValueDigest.describe(state.recent))

            // **The instrument strip** (focus-6uya): the store line, what is being watched, the
            // switch and the way to Settings, on the same inset ground as the wells but tighter,
            // so it reads as the window's status bar rather than as a sixth section.
            well(spacing: rowSpacing / 2, washed: false) {
                footer
            }

            Spacer(minLength: 0)
        }
        .padding(sectionSpacing)
        .frame(minWidth: 420, minHeight: 260, alignment: .topLeading)
        .background(DesignTokens.Palette.role(.inlay, for: traits))
        .buttonStyle(CompanionButtonStyle())
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { contentWidth = $0 }
        .background {
            // Empty history deliberately draws no section, so its EmptyView cannot
            // publish preferences. Record that absence without adding a layout child;
            // populated history still reports from the list that actually draws it.
            if state.recent.isEmpty {
                Color.clear
                    .shellRendered(.recentCount, 0)
                    .shellRendered(.recentDigest, ShellValueDigest.describe(state.recent))
            }
        }
        // **The traits this window resolved out of its own environment** (focus-h7h).
        //
        // Read here rather than taken from the connection, and that is the whole point: this is
        // the far end of the scene's `.appearanceTraits(composition.appearanceTraits(for:))`
        // injection, which is a separate wire from the connection and was separately guttable.
        // A window that asked the composition root for the live traits and then injected
        // `AppearanceTraits.systemDefault` fires the receipt and ignores dark mode and every
        // accessibility setting; this is the value that says which of the two happened.
        .shellRendered(.appearanceTraits, traits.renderedDescription)
        .defaultFocus($focus, showsCapture ? .cockpitCaptureField : .cockpitDoneWhen)
        // The window is named for the app; the group is too, so VoiceOver announces what it
        // has landed in before reading the priority out of it.
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(ShellStrings.resource(.cockpitHeading)))
        .onAppear { commandCenter.register(perform(_:)) }
        .onDisappear { commandCenter.unregister() }
        // **One statement, not an `.onAppear` beside an `.onChange` doing the same thing**
        // (focus-zrs). The draft is an edit buffer — a second representation of
        // `state.priority?.doneWhen`, which is the point of it — and it was seeded from *three*
        // places: here on appear, here on a new commitment, and below on a new definition of
        // done. Round 3 of this epic removed exactly this shape from `FocusSentinelApp` and it
        // was still here. `initial: true` is the appear, so the buffer has one seeding rule per
        // reason it needs re-seeding and no fourth place for the two to drift apart in.
        .onChange(of: state.priority?.id, initial: true) {
            doneWhenDraft = state.priority?.doneWhen ?? ""
            // A different commitment is not the one that was being re-worded.
            isEditingIntent = false
        }
        .onChange(of: state.priority?.doneWhen) { doneWhenDraft = state.priority?.doneWhen ?? "" }
        // The one and only surface an incoming `focus://` URL can reach. There is no path from
        // here to a store mutation that does not go through a person pressing Replace.
        .sheet(isPresented: handoffPresentation) {
            if let request = state.pendingHandoff {
                HandoffConfirmationSheet(
                    request: request,
                    current: state.priority,
                    replace: { wiring.acceptHandoff?(request) },
                    cancel: { wiring.cancelHandoff?() }
                )
            }
        }
        // **The store did not open, and nobody has been told** (focus-tzj.4).
        //
        // Presented from the state rather than from a local `@State`, for `handoffPresentation`'s
        // reason: the acknowledgement belongs to the host — it is what lifts the capture refusal
        // — and a local mirror could disagree with it. There is no dismissal that is not the
        // button: the binding's setter routes every route out of the sheet through the same verb.
        .sheet(isPresented: storeFailurePresentation) {
            StoreUnavailableSheet(
                storeLocation: state.storeLocation,
                acknowledge: { wiring.acknowledgeStoreFailure?() }
            )
        }
        // **The one screen that says what this app looks at** (focus-odz.7).
        //
        // Presented from the state rather than from a local `@State`, for `storeFailurePresentation`'s
        // reason: whether it is owed is the host's fact, written into the store, and a local mirror
        // could disagree with it. It is a sheet on the cockpit, so it can only ever appear over a
        // window somebody opened — nothing on the nudge path can raise it, which is what keeps an
        // explanation from becoming an interruption.
        .sheet(isPresented: firstRunPresentation) {
            FirstRunSheet(
                storeLocation: state.storeLocation,
                dismiss: onFirstRunExplanationDismissed
            )
        }
        .sheet(isPresented: $isCompleting) {
            if let priority = state.priority {
                CompletionSheet(
                    intent: priority.intent,
                    complete: { shipped, restartPoint in
                        wiring.complete?(shipped, restartPoint)
                        isCompleting = false
                    },
                    cancel: { isCompleting = false }
                )
            }
        }
        // **The three values the column carries but no single subview owns** (focus-h7h).
        //
        // The recents row and the handoff sheet are drawn from `state`, and the two mutation
        // hosts decide whether every control in the window is live or disabled — a cockpit handed
        // `actions: nil` looks finished and does nothing, which is a defect no receipt can see.
        // The handoff is reported by the **task it names** rather than by a `Bool`, because the
        // self-check drives a handoff carrying a sentence no person would type: a placeholder has
        // no way to be carrying that.
        .shellRendered(.handoffTask, state.pendingHandoff?.task ?? "")
        .shellRendered(.handoffDetail, ShellValueDigest.describe(state.pendingHandoff))
        .shellRendered(
            .mutationHostsAttached,
            "\(actions != nil ? "priority" : "-")/\(sessionActions != nil ? "session" : "-")"
        )
        // …and the collection point. The generation is injected here so every reporting site
        // below is stamped with the connection it was drawn from, and the values arrive at the
        // composition root through the one closure only the root can supply.
        .shellRenderReport(generation: generation, didDraw)
    }

    // MARK: - The File menu

    /// Carry out a command that arrived from the menu bar (F-90, F-145).
    ///
    /// Each one lands on the surface that already does the job, so a key equivalent and a
    /// click are the same code path rather than two implementations of the same idea.
    ///
    /// ⌘O with no priority is the one that needs explaining: there is nothing to attach
    /// context *to* until there is a commitment, so it asks for one rather than opening a file
    /// panel whose result would have nowhere to go.
    /// **The world as this window can see it** (focus-6uf).
    ///
    /// Built from `state`, which is the same value the cockpit's own controls are drawn from, so
    /// the menu item and the button it duplicates are answering one question about one reading.
    ///
    /// `hasOpenNudge` is `false` and that is a statement rather than a placeholder: the four e05
    /// verbs are not the cockpit's — they act on whatever nudge surface is on screen, which this
    /// window knows nothing about and should not — so this surface offers none of them, which is
    /// exactly what the exhaustive switch's `break` already did for them.
    private var commandWorld: ShellCommandWorld {
        ShellCommandWorld(
            hasPriority: state.priority != nil,
            sessionPhase: state.session?.phase,
            hasOpenNudge: false
        )
    }

    private func perform(_ command: PriorityCommand) {
        // **The guards are one predicate now, and the menu keeps it too** (focus-6uf).
        //
        // Every `case` below used to re-state its own condition — `state.priority != nil`,
        // `state.session == nil`, `session.phase != .paused` — and the menu item that sends the
        // command stated none of them, so all thirteen items were permanently enabled and these
        // verbs silently returned. `PriorityCommand.isAvailable(in:)` is the one place that rule
        // lives; `ShellActionButton` disables on it, and this refuses on it, so a key equivalent
        // that reached a stale menu still cannot perform a verb the app would reject.
        //
        // It is asked once, at the top, rather than per case: a `case` added without a guard is
        // exactly how six of these became silent no-ops, and a rule stated at the door cannot be
        // forgotten by the next arm.
        //
        // `addFilesToContext` is deliberately below it and not gated by it: with no commitment it
        // opens the capture field rather than a file panel whose result would have nowhere to go,
        // which is an effect and not a no-op, and `isAvailable(in:)` says so.
        guard command.isAvailable(in: commandWorld) else { return }
        switch command {
        case .newPriority:
            isCapturing = true
            focus = .cockpitCaptureField
        case .completePriority:
            isCompleting = true
        case .addFilesToContext:
            guard state.priority != nil else {
                isCapturing = true
                focus = .cockpitCaptureField
                return
            }
            fileImportToken &+= 1

        // The four e03 verbs. Each lands on the same host the cockpit's own control calls, so a
        // key equivalent and a click are one code path rather than two implementations of the
        // same idea — and the machine's own rules are the predicate above rather than three
        // conditions written out here.
        case .startSession:
            sessionActions?.startSession(kind: .openEnded, plannedSeconds: nil, deadlineAt: nil)
        case .pauseSession:
            sessionActions?.pauseSession()
        case .completeSession:
            sessionActions?.completeSession()
        case .pauseSensing:
            sessionActions?.setSensingPaused(!state.sensing.isPausedByUser)

        // The four e05 verbs are not the cockpit's. They act on whatever nudge surface is on
        // screen, which the cockpit knows nothing about and should not: `FocusCommandCenter`
        // delivers every command to the nudge loop as well, and that is where they land.
        //
        // Listed one by one rather than caught by a `default:` — the exhaustive switch is what
        // tells the next epic that added a command that the cockpit has an opinion to form
        // about it, and a `default:` would silently form the opinion "ignore it".
        case .thisIsRelevant, .snoozeNudge, .hideOverlays, .showMenuBar,
             .answerYes, .answerNo, .answerNotNow:
            break
        }
    }

    /// Whether the handoff sheet is up.
    ///
    /// Derived from the state rather than stored: the pending handoff belongs to the host, so
    /// dismissing the sheet by any route — the buttons, Escape, the window — has to tell the
    /// host, and a local `@State` mirror could disagree with it.
    /// Whether the store-failure sheet is up (focus-tzj.4).
    ///
    /// `set` routes **every** way out of the sheet — the button, the window, anything AppKit
    /// does — through the same acknowledgement, because the sheet's whole job is to have been
    /// read, and a route out that did not record that would leave the capture refusal in force
    /// with nothing on screen to explain it.
    private var storeFailurePresentation: Binding<Bool> {
        Binding(
            get: { state.storeFailureNeedsAcknowledgement },
            set: { presented in
                if !presented { wiring.acknowledgeStoreFailure?() }
            }
        )
    }

    /// **The first-run explanation's presentation** (focus-odz.7).
    ///
    /// The same shape as the store-failure sheet's, and for the same reason: every route out of
    /// the sheet — the button, a click outside, a system dismissal — goes through the one verb, so
    /// the app cannot end up believing it has explained itself when nobody saw the screen.
    private var firstRunPresentation: Binding<Bool> {
        Binding(
            get: { state.showsFirstRunExplanation },
            set: { presented in
                if !presented { onFirstRunExplanationDismissed() }
            }
        )
    }

    private var handoffPresentation: Binding<Bool> {
        Binding(
            get: { state.pendingHandoff != nil },
            set: { presented in
                if !presented { wiring.cancelHandoff?() }
            }
        )
    }

    // MARK: - The hero

    /// The priority, with the status stated under it.
    ///
    /// **The badge is demoted, and the demotion is the point** (focus-w41, direction §5.1). It was
    /// a decorated chip on the hero's baseline, which made the app's verdict a second object of
    /// the same weight as the person's own sentence — `D02` shows the result, a red warning
    /// triangle sharing the top line with the priority. It is now the compact style, on its own
    /// line beneath the hero, which is where the canvas puts it: a supporting statement about the
    /// sentence rather than a rival to it.
    ///
    /// `ViewThatFits` is gone with the chip. It existed to decide which of two same-weight objects
    /// gave way when the line was tight, and there is no longer a contest to arbitrate: the hero
    /// has the width, always, and wraps to as many lines as the sentence needs.
    private var header: some View {
        VStack(alignment: .leading, spacing: rowSpacing / 2) {
            hero
            StatusBadge(status: state.status, style: .compact)
        }
        // **The two values at the top of the window, reported from where they are drawn**
        // (focus-h7h). A cockpit handed a frozen placeholder draws a hero with no sentence in it
        // and a badge that says `uncertain` for ever, and both of those are values the
        // composition root can hold its own answer up beside.
        .shellRendered(.priorityIntent, state.priority?.intent ?? "")
        .shellRendered(.status, state.status.rawValue)
        // **The whole commitment beside the sentence** (focus-7ow). `priorityIntent` is one field
        // of twelve, and a window handed somebody else's timebox, context items and rules draws
        // the same hero. Derived by `Mirror`, so a thirteenth field is in this string the day it
        // is added and nobody has to remember to widen an enumeration.
        .shellRendered(.priorityDetail, ShellValueDigest.describe(state.priority))
    }

    /// **What the commitment sections report when there is no commitment** (focus-7ow).
    ///
    /// A zero-height reporter rather than nothing at all. `ShellRenderFidelity` reads a field the
    /// window never mentioned as `unreportedFields` — the same reading a deleted section
    /// produces — so a cockpit with nothing committed to has to say so in the vocabulary the
    /// composition root expects it in, or "correct" and "gutted" would be one answer.
    @ViewBuilder
    private var absentCommitmentReceipts: some View {
        if state.priority == nil {
            Color.clear
                .shellRendered(.priorityDoneWhen, ShellRenderedValues.noCommitment)
                .shellRendered(.sessionPhase, ShellRenderedValues.noCommitment)
                .shellRendered(.sessionDetail, ShellRenderedValues.noCommitment)
                .shellRendered(.sessionElapsedSeconds, ShellRenderedValues.noCommitment)
                .shellRendered(.lastActiveApp, ShellRenderedValues.noCommitment)
        }
    }

    /// The priority itself — read as a hero, or corrected in place at the same size.
    ///
    /// The editor replaces the hero rather than sitting beside it: the sentence must not move
    /// or change size when someone starts fixing a typo in it, because the thing they are
    /// editing is the largest object on the screen and it should stay exactly where it is.
    @ViewBuilder
    private var hero: some View {
        if isEditingIntent, let priority = state.priority, wiring.editIntent != nil {
            PriorityIntentEditor(
                draft: $intentDraft,
                commit: { commitIntent(priority) },
                cancel: { isEditingIntent = false },
                focus: $focus
            )
        } else {
            PriorityHeroView(intent: state.priority?.intent)
        }
    }

    /// Open the in-place editor on the sentence that is there now.
    private func beginEditingIntent(_ priority: PrioritySnapshot) {
        intentDraft = priority.intent
        isEditingIntent = true
        focus = .cockpitEditIntent
    }

    /// Commit the corrected sentence.
    ///
    /// An emptied field is not a command to erase the commitment — it is a slip — so it closes
    /// the editor and changes nothing. An unchanged sentence writes nothing either, because an
    /// undo step that undoes nothing is a step the user has to take twice.
    private func commitIntent(_ priority: PrioritySnapshot) {
        isEditingIntent = false
        guard
            let corrected = CockpitWiring.correction(intentDraft, replacing: priority.intent)
        else {
            return
        }
        wiring.editIntent?(corrected)
    }

    // MARK: - Definition of done (F-08)

    /// One optional line, directly under the hero, editable in place.
    ///
    /// Optional at capture and optional forever: an empty definition of done is a legitimate
    /// answer, so there is no validation here and nothing is ever refused. The field commits
    /// on Return and on losing focus, because a person who types a sentence and then clicks
    /// elsewhere has not asked to throw it away.
    ///
    /// ## The heading belongs to the value, not to the section (focus-0ai)
    ///
    /// The caption was drawn unconditionally and the read-only branch under it drew
    /// `priority.doneWhen ?? ""`, so a commitment with no definition of done rendered a caption
    /// with nothing beneath it — the app appearing to hold something it does not.
    /// `NudgeSubject`'s doctrine names this exact shape: *"a nudge that renders an empty string
    /// is worse than one that renders an identifier — the empty string is a bug the person is
    /// asked to answer."*
    ///
    /// **The two branches answer it differently, and that asymmetry is the fix rather than an
    /// inconsistency.** The editable branch has somewhere to put the answer — the field's own
    /// prompt, which invites the person to write one — so its caption is a control's label and
    /// stays. The read-only branch has nowhere, so with nothing to show it shows nothing at all.
    @ViewBuilder
    private func doneWhenSection(_ priority: PrioritySnapshot) -> some View {
        VStack(alignment: .leading, spacing: rowSpacing / 3) {
            if actions == nil {
                // Read-only: the value, not a control. See `showsCapture` for why a cockpit
                // with no host draws no fields. Nothing at all when there is no value, heading
                // included (focus-0ai).
                if let doneWhen = CockpitWiring.doneWhenToDraw(priority.doneWhen) {
                    CompanionSectionHeading(key: .priorityDoneWhenLabel, symbol: "checkmark.seal")
                        .foregroundStyle(DesignTokens.Palette.role(.spruce, for: traits))

                    Text(verbatim: doneWhen)
                        .font(DesignTokens.font(.body, scale: textScale))
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                CompanionSectionHeading(key: .priorityDoneWhenLabel, symbol: "checkmark.seal")
                    .foregroundStyle(DesignTokens.Palette.role(.spruce, for: traits))

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
        // **The definition of done, reported from the section that draws it** (focus-7ow, F-08).
        //
        // The value the section was handed, not `doneWhenDraft`: the draft is `@State` seeded
        // from it and edited by a person, and reporting the draft would make the reading a race
        // against `onAppear` rather than a statement about what the window was given.
        .shellRendered(.priorityDoneWhen, priority.doneWhen ?? "")
    }

    private func commitDoneWhen(_ priority: PrioritySnapshot) {
        let trimmed = doneWhenDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let stored = trimmed.isEmpty ? nil : trimmed
        guard stored != priority.doneWhen else { return }
        wiring.editDoneWhen?(stored)
    }

    // MARK: - Actions

    /// One primary action, and nothing that competes with it.
    ///
    /// Complete is the default action whenever there is something to complete — it is the
    /// only thing a person does *to* a priority that ends it. Clear is beside it because
    /// putting the priority down is not the same as finishing it, and an app that only offers
    /// "done" teaches people to lie to it.
    // MARK: - Timebox (F-12)

    private func timeboxSection(_ priority: PrioritySnapshot) -> some View {
        TimeboxControl(
            timeboxSeconds: priority.timeboxSeconds,
            state: priority.timebox,
            choose: wiring.setTimebox,
            focus: $focus
        )
    }

    // MARK: - The session (F-98, F-99, F-101)

    /// The session runs *inside* the timebox, so it is drawn directly under it.
    ///
    /// It is shown only where there is a priority, because a session is always about one: the
    /// store starts it on the active task, and offering to start one with nothing committed to
    /// would be offering to time nothing.
    private var sessionSection: some View {
        SessionControls(
            session: state.session,
            elapsedSeconds: sessionElapsedSeconds,
            lastActiveBundleID: lastActiveBundleID,
            actions: sessionActions,
            focus: $focus
        )
        // **The figure the timer is reading, and the phase beside it** (focus-h7h).
        //
        // `"none"` rather than `""` for an absent figure, because a session timer that reads
        // nothing and one that reads zero are different defects and one spelling for both would
        // make them the same reading. Whole seconds: the wall clock moves between the moment the
        // connection was built and the moment the reading is taken, and a comparison to the
        // millisecond would fail on the passage of time rather than on a defect.
        .shellRendered(
            .sessionElapsedSeconds,
            sessionElapsedSeconds.map { String(Int($0)) } ?? "none"
        )
        .shellRendered(.sessionPhase, state.session?.phase.rawValue ?? "none")
        // The whole session beside the phase: a badge drawing `focus` for somebody else's
        // session, started at another time and with another timebox, is the same phase
        // (focus-7ow).
        .shellRendered(.sessionDetail, ShellValueDigest.describe(state.session))
    }

    // MARK: - Per-task rules (F-11)

    private func rulesSection(_ priority: PrioritySnapshot) -> some View {
        TaskRulesView(
            rules: priority.rules,
            add: wiring.addRule,
            change: wiring.changeRule,
            remove: wiring.removeRule,
            focus: $focus
        )
    }

    // MARK: - Context pack (F-09)

    /// What is on the desk for this priority: apps, sites, keywords and files.
    ///
    /// It sits below the definition of done and above the actions, at `.callout` and smaller,
    /// so it can never compete with the hero for the eye.
    private func contextSection(_ priority: PrioritySnapshot) -> some View {
        ContextChipRow(
            items: priority.contextItems,
            add: wiring.addContext,
            remove: wiring.removeContext,
            importFilesToken: fileImportToken,
            focus: $focus
        )
    }

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
                wiring.setPriority?(intent, doneWhen)
                isCapturing = false
            },
            isEnabled: actions != nil,
            fieldFocus: .cockpitCaptureField,
            buttonFocus: .cockpitSetPriority,
            focus: $focus
        )
    }

    private func primaryActions(_ priority: PrioritySnapshot) -> some View {
        // The row wraps rather than shrinking its labels. A fourth verb does not fit beside
        // the other three at the default window width — measured, in the committed baseline —
        // and a button reading "Complete Pri…" is a control the user has to guess at, which is
        // the same failure F-147 forbids for the priority itself. So the layout is offered
        // three ways and takes the widest one that fits whole: one line, two, or one verb per
        // line at the largest text sizes.
        //
        // No `Spacer` inside the candidates: a spacer that can compress to zero makes the
        // first candidate "fit" at every width, and the row then truncates instead of
        // wrapping. The alignment is done by the frame around the choice.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: rowSpacing) {
                completeButton
                changeButton
                fixWordingButton(priority)
                clearButton
            }
            VStack(alignment: .leading, spacing: rowSpacing) {
                HStack(spacing: rowSpacing) {
                    completeButton
                    changeButton
                }
                HStack(spacing: rowSpacing) {
                    fixWordingButton(priority)
                    clearButton
                }
            }
            VStack(alignment: .leading, spacing: rowSpacing) {
                completeButton
                changeButton
                fixWordingButton(priority)
                clearButton
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Finish the priority. The most important thing a person does *to* a commitment — and
    /// deliberately **not** the cockpit's default button.
    ///
    /// Return is the key that commits whatever sentence is in whatever field has focus, and
    /// this window is full of fields: the capture field, the definition of done, the keyword
    /// field, the rule subject. Making Complete the window's default action put finishing the
    /// work one stray Return away from typing — and it was not hypothetical. The evidence lane
    /// drove capture with two Returns; the first committed the sentence, the second closed the
    /// capture field, promoted this button to default and opened the completion sheet, which is
    /// the sheet that `cockpit-priority.png` and `context-chips.png` were both pictures of.
    /// One more Return there would have completed the priority with two empty fields.
    ///
    /// `CommandRegistry` already stated the rule this restores — "finishing the thing you are
    /// working on must not be one modifier away from typing", which is why Complete Priority is
    /// ⌃⌘⏎ rather than ⌘⏎ — and binding plain Return here contradicted it outright. So
    /// completion is reachable by click, by ⌃⌘⏎, and by the File menu item; by no bare
    /// keystroke at all. `DefaultActionContractTests` holds the whole package to that.
    private var completeButton: some View {
        Button {
            isCompleting = true
        } label: {
            ShellText(.priorityActionComplete)
        }
        .focused($focus, equals: .cockpitComplete)
        .disabled(actions == nil)
    }

    /// Replace the commitment with a new one, through the capture field.
    @ViewBuilder
    private var changeButton: some View {
        if !showsCapture {
            Button {
                isCapturing = true
                focus = .cockpitCaptureField
            } label: {
                ShellText(.priorityActionChange)
            }
            .disabled(actions == nil)
        }
    }

    /// Correct the wording of the commitment that is already there.
    ///
    /// Not the same act as replacing it, and the store has two verbs for that reason: this one
    /// keeps the task and its whole context pack and bumps the revision, where Change Priority
    /// starts a new commitment and pushes this one into history.
    @ViewBuilder
    private func fixWordingButton(_ priority: PrioritySnapshot) -> some View {
        if !isEditingIntent {
            Button {
                beginEditingIntent(priority)
            } label: {
                ShellText(.priorityActionEditIntent)
            }
            .disabled(wiring.editIntent == nil)
        }
    }

    /// Put the priority down without completing or deleting anything.
    private var clearButton: some View {
        Button {
            wiring.clear?()
        } label: {
            ShellText(.priorityActionClear)
        }
        .disabled(actions == nil)
    }

    // MARK: - What the app can honestly say about itself

    /// Two quiet truths at the bottom — whether anything is being saved, and what is actually
    /// being watched — the switch that changes the second, and the route to Settings.
    ///
    /// All of it is `.footnote` or smaller. Settings was e01's most prominent control and is
    /// deliberately demoted here: it is a route, not an action, and nothing in this window may
    /// compete with the priority for the eye.
    ///
    /// **The sensing line used to lie.** e01 drew one string —
    /// `shell.cockpit.sensing.unavailable` — whatever was happening underneath it, changing only
    /// the glyph between an open eye and a closed one. So the shell said "no activity source is
    /// running" while it was observing, and said exactly the same thing while it was switched
    /// off. `SensingStatusView` replaces it with the three sentences those three states
    /// actually deserve, and lists by name any capability that is not available — because a
    /// person reading a status line is owed the parts of it that are missing.
    private var footer: some View {
        VStack(alignment: .leading, spacing: rowSpacing / 2) {
            // **One derivation, three consumers** (focus-7ow): the glyph, the sentence, and the
            // receipt. This line told the person their store was unavailable when it was fine —
            // a boolean flip, drawn from `state.storeIsReady`, reported nowhere, and invisible to
            // the whole nineteen-stage gate. Reporting the **string key the label was actually
            // given** rather than the flag it came from is what binds the receipt to the screen:
            // a mutation to either ternary changes `storeLine`, and `storeLine` is what is said.
            //
            // **Three states, not two** (focus-tzj.4). This was a ternary on `storeIsReady`,
            // which `PriorityHost` computed as `storeOpened && writeFailure == nil` — so *"the
            // store never opened and nothing you type today will exist tomorrow"* and *"that one
            // save did not go through"* were the same eight-point grey sentence. They are told
            // apart here, in the order of severity, and the one that costs a day's work also
            // raises a sheet.
            let storeLine: (image: String, key: ShellStringKey) =
                if !state.storeOpened {
                    (image: "exclamationmark.triangle.fill", key: .cockpitStoreUnavailable)
                } else if state.lastWriteFailed {
                    (image: "exclamationmark.arrow.circlepath", key: .cockpitStoreWriteFailed)
                } else {
                    (image: "internaldrive.fill", key: .cockpitStoreReady)
                }
            detail(systemImage: storeLine.image, key: storeLine.key)
                .shellRendered(.storeStatus, storeLine.key.rawValue)
                // The offer's conjunction, reported from the footer that draws it (focus-odz.4).
                .shellRendered(
                    .launchAtLoginOffer,
                    state.showsLaunchAtLoginOffer ? "shown" : "hidden"
                )
                // …and whether the first-run explanation is up (focus-odz.7). Reported from the
                // window that presents it, so "shown on the wrong launch" and "never shown at
                // all" are two readings rather than one silence.
                .shellRendered(
                    .firstRunExplanation,
                    state.showsFirstRunExplanation ? "shown" : "hidden"
                )

            SensingStatusView(
                summary: state.sensing,
                capabilities: state.capabilities,
                showsReducedCapabilities: true
            )
            // The whole summary behind the sentence. `sensingSummary` is a projection of six
            // facts and five of them could move without it changing (focus-7ow).
            .shellRendered(.sensingDetail, ShellValueDigest.describe(state.sensing))
            // The capability table the footer's reduced list is drawn from. Reported whole
            // rather than as the list it happened to name, so a matrix nobody probed — twelve
            // `notRequested` rows, and therefore an empty reduced list because nothing is
            // *watching* — is a different value rather than the same absence (focus-h7h).
            .shellRendered(.capabilityStates, state.capabilities.renderedDescription)

            // Shown only where a host can act on it, for the same measured reason the capture
            // field is: an AppKit-backed control does not rasterise under `ImageRenderer` — a
            // switch draws SwiftUI's yellow "unrenderable view" placeholder whatever appearance
            // is injected — so a read-only render would commit a picture of a broken control
            // and call it a baseline. A disabled switch would be worse than none in the app
            // too: the status line above already says whether anything is being watched.
            if let host = sessionActions {
                PauseSwitch(
                    isWatching: !state.sensing.isPausedByUser,
                    setWatching: { watching in host.setSensingPaused(!watching) },
                    focus: $focus
                )
            }

            launchAtLoginOffer

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

    /// **The one-time offer to open at login** (D-12, focus-odz.4).
    ///
    /// It appears in the footer after a first completed session and never again, in either
    /// direction: accepting and declining both record the asking. Whether it appears at all is
    /// `state.showsLaunchAtLoginOffer`, which the host decides through
    /// `LaunchAtLoginOffer.shouldOffer` — the view asks no question and remembers nothing.
    ///
    /// **Never a first-launch prompt**, which is the half D-12 is most about: an app that asks to
    /// be added to Login Items before it has been any use is asking for a commitment it has not
    /// earned. And never a modal: it is a line in a footer somebody can ignore, beside the line
    /// that tells them where their data lives.
    ///
    /// The receipt is on the whole row and reports the **conjunction** the footer drew, in
    /// `ritualBanner`'s shape and for its reason: an offer that appears when it should not is a
    /// row asking for something already declined, and one that never appears is a feature nobody
    /// can find.
    @ViewBuilder
    private var launchAtLoginOffer: some View {
        if state.showsLaunchAtLoginOffer {
            HStack(spacing: rowSpacing / 2) {
                ShellText(.cockpitLaunchAtLoginOffer, role: .footnote)
                    .foregroundStyle(DesignTokens.supportingTextColor(for: traits))

                Button {
                    onLaunchAtLoginOffer(.accept)
                } label: {
                    ShellText(.cockpitLaunchAtLoginAccept, role: .footnote)
                }

                Button {
                    onLaunchAtLoginOffer(.dismiss)
                } label: {
                    ShellText(.cockpitLaunchAtLoginDismiss, role: .footnote)
                }
            }
        }
    }

    /// Working groups share the same furniture as settings and the popover.
    private func well<Content: View>(
        spacing: CGFloat? = nil,
        washed: Bool = true,
        @ViewBuilder _ content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: spacing ?? sectionSpacing) {
            content()
        }
        .companionSurface()
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
