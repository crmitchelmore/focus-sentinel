import FocusCore
import SwiftUI

/// The cockpit: one column, no sidebar, no custom chrome, no analytics.
///
/// Deliberately **not** a `NavigationSplitView`. A sidebar ships in e09, with its last real
/// destination; an empty "Insights" row today would be a surface with nothing behind it.
///
/// **Two destinations, Now and History** (focus-g9iw). Now is the only home of the current
/// priority and its session, and it changes with what the person is doing: *planning* while no
/// session is open — the priority being set up, with the standing priorities beside the capture
/// field — and *working* while one runs or is paused, when the task, its timer and its verbs have
/// the column to themselves. History is the past: earlier priorities to pick up again and the
/// route to the day's record. What belongs to a priority — its context and its rules — is
/// configured in a sheet opened from Now rather than a tab of its own.
///
/// Now reads top to bottom in the order the user thinks: what am I doing (the hero), how will I
/// know it is finished (the definition of done), the verbs that act on it, and then the machinery
/// — the time, on one well; what counts as this work, behind *Configure context…* — with the
/// instrument strip under every destination (focus-6uya). Every section name is `.sectionHeading`, one step
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
    @Environment(\.openWindow) private var openWindow
    @Environment(\.shellTextScale) private var textScale
    /// The task mirror's board, injected by the app; absent in every snapshot fixture.
    @Environment(TaskBoardModel.self) private var taskBoard: TaskBoardModel?
    @FocusState private var focus: FocusField?

    /// The definition of done, while it is being edited. Committed on Return and on losing
    /// focus; re-seeded whenever the priority underneath it changes.
    @State private var doneWhenDraft: String = ""

    /// The priority explicitly being replaced. Selecting another priority closes capture.
    @State private var capturePriorityID: UUID?
    /// Whether the capture field, when it commits, keeps the current priority's desk
    /// (focus-1rj7). Set by the "New Priority, Same Context…" verb and cleared with the field.
    @State private var isKeepingContext: Bool = false
    /// Which destination is open (focus-1rj7, focus-g9iw). The initial value is the view's
    /// argument, so the snapshot lane can photograph each; the app always opens on Now.
    @State private var tab: CockpitTab
    @Namespace private var tabLozengeSpace

    /// Whether the completion sheet is up. Completing is a deliberate act with two things
    /// worth recording, so it gets a sheet rather than happening under the pointer.
    @State private var isCompleting: Bool = false

    /// Bumped when the File menu's ⌘O arrives while the context sheet is already up, which is
    /// how a menu item reaches a file panel that belongs to a view inside that sheet.
    @State private var fileImportToken: Int = 0

    /// **Whether the context sheet is up** (focus-g9iw). Opened by *Configure context…* and by
    /// ⌘O; the priority's context and rules are configured there rather than on a tab.
    @State private var isConfiguringContext: Bool = false
    /// Whether the sheet should open its file panel as soon as it appears — ⌘O's route, so the
    /// key reaches the same panel the sheet's own *Add Files…* opens.
    @State private var importsFilesOnContextOpen: Bool = false

    /// **Whether the walkthrough was asked for** (focus-u6de).
    ///
    /// Local rather than a host fact, and that is the difference between the two showings. The
    /// first one is owed by the store and written into it; this one is a person pressing a
    /// button, changes nothing, and is forgotten with the window. The sheet is the same view
    /// either way, presented from `walkthroughPresentation`, which reads both.
    @State private var isReplayingWalkthrough: Bool = false

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
    /// What the walkthrough sheet's Continue performs after the sheet is down (focus-u6de): the
    /// root opens the tour panel beside this window.
    private let onWalkthroughContinued: () -> Void

    public init(
        state: CockpitState,
        actions: (any PriorityActing)? = nil,
        sessionActions: (any SessionActing)? = nil,
        sessionElapsedSeconds: Double? = nil,
        lastActiveBundleID: String? = nil,
        onLaunchAtLoginOffer: @escaping (LaunchAtLoginOfferAction) -> Void = { _ in },
        onFirstRunExplanationDismissed: @escaping () -> Void = {},
        onWalkthroughContinued: @escaping () -> Void = {},
        commandCenter: FocusCommandCenter = .shared,
        tab: CockpitTab = .now
    ) {
        self.state = state
        self.actions = actions
        self.sessionActions = sessionActions
        self.sessionElapsedSeconds = sessionElapsedSeconds
        self.lastActiveBundleID = lastActiveBundleID
        self.onLaunchAtLoginOffer = onLaunchAtLoginOffer
        self.onFirstRunExplanationDismissed = onFirstRunExplanationDismissed
        self.onWalkthroughContinued = onWalkthroughContinued
        self.commandCenter = commandCenter
        self.didRender = nil
        self.generation = 0
        self.didDraw = nil
        self._tab = State(initialValue: tab)
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
        self.onWalkthroughContinued = connection.onWalkthroughContinued
        self.commandCenter = commandCenter
        self.didRender = connection.didRender
        self.generation = connection.generation
        self.didDraw = connection.didDraw
        self._tab = State(initialValue: .now)
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

            // **The destinations** (focus-1rj7, focus-g9iw), directly under the window's name:
            // Now, which holds the priority and its session, and History, which holds the past.
            tabBar

            switch tab {
            case .now:
                nowDestination
            case .history:
                historyDestination
            case .tasks:
                TasksPane(model: taskBoard, priority: state.priority?.id)
            }

            // **The instrument strip** (focus-6uya), on both destinations: the store line, what
            // is being watched, the switch and the way to Settings — the window's status bar.
            well(spacing: rowSpacing / 2, washed: false) {
                footer
            }

            Spacer(minLength: 0)
        }
        // **What the destination that is not open would have reported** (focus-1rj7). A section
        // on the other destination is not on the screen, and a field nobody reported is
        // indistinguishable from a section somebody deleted — so the values those sections would
        // draw are reported here, from the same state, through a background that proposes no
        // size. The open destination's own sections report from where they are drawn.
        .background(hiddenTabReceipts)
        // A **background** rather than a sibling in the column, and that is measured: a
        // zero-height `Color.clear` is still a `VStack` child and still takes the stack's
        // spacing, which moved every committed cockpit baseline by 20 points.
        .background(absentCommitmentReceipts)
        .padding(sectionSpacing)
        .frame(minWidth: 420, minHeight: 260, alignment: .topLeading)
        .contentGround(traits)
        .buttonStyle(CompanionButtonStyle())
        .background {
            // No earlier priorities deliberately draws no section, so its EmptyView cannot
            // publish preferences. Record that absence without adding a layout child; a
            // populated list still reports from where it is drawn.
            if state.earlierPriorities.isEmpty {
                Color.clear
                    .shellRendered(.recentCount, 0)
                    .shellRendered(.recentDigest, ShellValueDigest.describe(state.earlierPriorities))
            }
            if state.standing.isEmpty {
                Color.clear
                    .shellRendered(.standingCount, 0)
                    .shellRendered(.standingDigest, ShellValueDigest.describe(state.standing))
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
        // The window is named for the app; the group is too, so VoiceOver announces what it
        // has landed in before reading the priority out of it.
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(ShellStrings.resource(.cockpitHeading)))
        // `perform(_:)` captures this view value, and with it `state` as it was when registered.
        // Re-registered on every new state (and, via `initial: true`, on appear) so a menu
        // command is judged against what is on screen rather than the cockpit as it first appeared.
        .onChange(of: state, initial: true) { commandCenter.register(perform(_:)) }
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
            capturePriorityID = nil
            isKeepingContext = false
            // A sheet's pending input must not move to a different priority.
            isConfiguringContext = false
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
                    cancel: { wiring.cancelHandoff?() },
                    currentStanding: state.standing
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
        // **The one screen that says what this app looks at, and then what it does**
        // (focus-odz.7, focus-u6de).
        //
        // The first showing is presented from the state rather than from a local `@State`, for
        // `storeFailurePresentation`'s reason: whether it is owed is the host's fact, written into
        // the store, and a local mirror could disagree with it. A replay is the local flag, because
        // a replay is owed by nobody. It is a sheet on the cockpit either way, so it can only ever
        // appear over a window somebody opened or asked for — nothing on the nudge path can raise
        // it, which is what keeps an explanation from becoming an interruption.
        .sheet(isPresented: walkthroughPresentation) {
            WalkthroughSheet(
                storeLocation: state.storeLocation,
                // Continue: the sheet goes down and the tour comes up beside the window.
                dismiss: {
                    dismissWalkthrough()
                    onWalkthroughContinued()
                },
                escapeDismisses: !state.showsFirstRunExplanation,
                // Escape on a replay: down, and no tour.
                cancel: dismissWalkthrough
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
        // **What counts as work on this priority** (focus-g9iw): its context and its rules, in a
        // bounded sheet rather than on a tab that repeated half of Now around them.
        .sheet(isPresented: $isConfiguringContext, onDismiss: { importsFilesOnContextOpen = false }) {
            if let priority = state.priority {
                ContextSheet(
                    intent: priority.intent,
                    contextItems: priority.contextItems,
                    rules: priority.rules,
                    addContext: wiring.addContext,
                    removeContext: wiring.removeContext,
                    addRule: wiring.addRule,
                    changeRule: wiring.changeRule,
                    removeRule: wiring.removeRule,
                    importRequest: fileImportToken,
                    importsOnOpen: importsFilesOnContextOpen,
                    done: { isConfiguringContext = false }
                )
            }
        }
        // **The three values the column carries but no single subview owns** (focus-h7h).
        //
        // The history rows and the handoff sheet are drawn from `state`, and the two mutation
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
            beginCapture()
        case .completePriority:
            isCompleting = true
        case .addFilesToContext:
            guard state.priority != nil else {
                beginCapture()
                return
            }
            // The files land in the context sheet, which is where the desk is configured
            // (focus-g9iw): bump its panel when it is already up, open it with the panel when not.
            if isConfiguringContext {
                fileImportToken &+= 1
            } else {
                importsFilesOnContextOpen = true
                tab = .now
                isConfiguringContext = true
            }

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

        // The walkthrough, asked for (focus-u6de). The centre has already brought this window
        // forward; the sheet goes up over it, on its first page, and writes nothing.
        case .showWalkthrough:
            isReplayingWalkthrough = true

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

    /// **The walkthrough's presentation** (focus-odz.7, focus-u6de).
    ///
    /// The same shape as the store-failure sheet's, and for the same reason: every route out of
    /// the sheet — the button, a click outside, a system dismissal — goes through the one verb, so
    /// the app cannot end up believing it has explained itself when nobody saw the screen. Up
    /// while either showing is owed; a way out settles both.
    private var walkthroughPresentation: Binding<Bool> {
        Binding(
            get: { state.showsFirstRunExplanation || isReplayingWalkthrough },
            set: { presented in
                if !presented { dismissWalkthrough() }
            }
        )
    }

    /// Every route out of the walkthrough. The first showing's dismissal is the host's verb; a
    /// replay's is this window's own flag. Both, when both are up, so nothing is left owing.
    private func dismissWalkthrough() {
        isReplayingWalkthrough = false
        if state.showsFirstRunExplanation { onFirstRunExplanationDismissed() }
    }

    private var handoffPresentation: Binding<Bool> {
        Binding(
            get: { state.pendingHandoff != nil },
            set: { presented in
                if !presented { wiring.cancelHandoff?() }
            }
        )
    }

    // MARK: - Now and History (focus-g9iw)

    /// **Now: planning, or working** (focus-g9iw).
    ///
    /// One destination with two moods rather than two tabs, because the change between them is
    /// the person's own verb — starting or finishing a session — and a tab that moved under them
    /// when they pressed Start would be the app rearranging the room.
    ///
    /// - **Planning** (no open session): the priority, how it will be known to be done, its verbs
    ///   and its timebox, with the standing priorities offered beside the capture field — the
    ///   things a person chooses between before the clock starts.
    /// - **Working** (a session running or paused): the same column without the standing list,
    ///   so the task, its timer and the session's verbs have the eye. *Change priority* is the one
    ///   deliberate route back to the list.
    ///
    /// The session section follows an open session as well as the priority (see
    /// `CockpitState.drawsSession`), and is drawn here once, in full: there is no second copy
    /// of the session's verbs anywhere in the window.
    @ViewBuilder
    private var nowDestination: some View {
        header
            .companionSurface(accent: state.priority != nil)

        if let priority = state.priority {
            doneWhenSection(priority)
            primaryActions
        }

        if showsCapture {
            capture
                .walkthroughAnchor(.captureField)
                .transition(traits.reduceMotion ? .identity : .opacity.combined(with: .move(edge: .top)))
            // The choices sit with the field that makes a new one.
            if standingIsDrawn { standingSection }
        }

        if drawsSession {
            well {
                // The session runs inside the timebox, so the box is drawn directly above it.
                if let priority = state.priority { timeboxSection(priority) }
                sessionSection
            }
        }

        if let priority = state.priority {
            configureContextRow(priority)
            PinnedTasksSection(model: taskBoard, priority: priority.id)
        }

        // Planning with a priority set: the standing priorities stay in reach, under the
        // priority's own sections, for the person deciding what to start on.
        if standingIsDrawn && !showsCapture { standingSection }
    }

    /// **History: the past, and nothing else** (focus-g9iw).
    ///
    /// Earlier priorities, each one press from becoming current again, and the route to the
    /// day's full record. The current priority, its session and the standing priorities are all
    /// Now's; repeating them here is what made the old tabs hard to tell apart.
    @ViewBuilder
    private var historyDestination: some View {
        // The list sits on a card like Now's sections; an empty history draws nothing, so it
        // gets no empty card either.
        let recent = RecentPrioritiesView(
            rows: state.earlierPriorities,
            activate: wiring.activate.map { activate in
                { id in
                    activate(id)
                    tab = .now
                }
            }
        )
            // **What is in the rows, not only how many** (focus-7ow).
            .shellRendered(.recentCount, state.earlierPriorities.count)
            .shellRendered(.recentDigest, ShellValueDigest.describe(state.earlierPriorities))
        if state.earlierPriorities.isEmpty {
            recent
        } else {
            well { recent }
        }
        openHistoryButton
    }

    /// Whether Now's mood is planning or working, read off the session.
    private var nowMode: CockpitWiring.NowMode {
        CockpitWiring.nowMode(session: state.session)
    }

    /// Whether the session section is on Now — see `CockpitState.drawsSession`.
    private var drawsSession: Bool { state.drawsSession }

    /// Whether the standing priorities are drawn on the open destination.
    private var standingIsDrawn: Bool {
        tab == .now && CockpitWiring.showsStanding(
            mode: nowMode,
            captureShown: showsCapture,
            hasStanding: !state.standing.isEmpty
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
    ///
    /// The definition of done goes with the priority; the session's four fields go with the
    /// session section, which is still drawn for a session left open after the priority was put
    /// down (focus-g9iw) — so they report `noCommitment` only when there is neither.
    @ViewBuilder
    private var absentCommitmentReceipts: some View {
        if state.priority == nil {
            Color.clear
                .shellRendered(.priorityDoneWhen, ShellRenderedValues.noCommitment)
        }
        if !drawsSession {
            Color.clear
                .shellRendered(.sessionPhase, ShellRenderedValues.noCommitment)
                .shellRendered(.sessionDetail, ShellRenderedValues.noCommitment)
                .shellRendered(.sessionElapsedSeconds, ShellRenderedValues.noCommitment)
                .shellRendered(.lastActiveApp, ShellRenderedValues.noCommitment)
        }
    }

    /// The title is directly editable; a new task gets its own draft and pending autosave.
    @ViewBuilder
    private var hero: some View {
        if let priority = state.priority, wiring.editIntent != nil {
            PriorityIntentEditor(
                intent: priority.intent,
                save: wiring.autosaveIntent,
                focus: $focus
            )
            .id(priority.id)
        } else {
            PriorityHeroView(intent: state.priority?.intent)
        }
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
                .shellHelp(.priorityDoneWhenLabelHelp)
                .walkthroughAnchor(.doneWhenField)
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
            calendar: priority.calendar,
            day: priority.calendarDay,
            choose: wiring.setTimebox,
            focus: $focus
        )
        .walkthroughAnchor(.timeboxControl)
    }

    // MARK: - The session (F-98, F-99, F-101)

    /// The session runs *inside* the timebox, so it is drawn directly under it.
    ///
    /// Drawn where there is a priority, because a session is about one — and also where a
    /// session is still open with none (focus-g9iw): putting the priority down does not end the
    /// session, so hiding its timer would hide the one thing still running. Every verb is here,
    /// once: start, pause, resume, break, the session notes and both endings.
    ///
    /// A session belongs to the task it started on. When that is not the priority on screen the
    /// controls say so under their heading, rather than letting the timer read as this
    /// priority's — see `CockpitWiring.sessionOwnership`.
    private var sessionSection: some View {
        SessionControls(
            session: state.session,
            elapsedSeconds: sessionElapsedSeconds,
            lastActiveBundleID: lastActiveBundleID,
            actions: sessionActions,
            ownershipNote: CockpitWiring.ownershipKey(
                CockpitWiring.sessionOwnership(priority: state.priority, session: state.session)
            ),
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
        .walkthroughAnchor(.sessionControls)
    }

    // MARK: - Context and rules (F-09, F-11)

    /// **The route to what counts as work on this priority** (focus-g9iw).
    ///
    /// The context pack and the per-task rules used to be a tab of their own, drawn beside a
    /// second copy of the session, and it was hard to say what that tab was for. They are one
    /// idea — what this priority looks like on this Mac — so they are one sheet, reached by one
    /// sliders button, with a line under it saying how much is configured so a person can see at
    /// a glance whether anything is there without opening it.
    private func configureContextRow(_ priority: PrioritySnapshot) -> some View {
        VStack(alignment: .leading, spacing: rowSpacing / 3) {
            Button {
                isConfiguringContext = true
            } label: {
                Label {
                    ShellText(.cockpitConfigureContext)
                } icon: {
                    Image(systemName: "slider.horizontal.3")
                }
            }
            .focused($focus, equals: .cockpitConfigureContext)
            .disabled(actions == nil)
            .shellHelp(.cockpitConfigureContextHelp)
            .walkthroughAnchor(.configureContext)

            contextSummary(priority)
                .foregroundStyle(DesignTokens.supportingTextColor(for: traits))
        }
    }

    /// How much is configured, as counts — never the items themselves, which are the sheet's.
    @ViewBuilder
    private func contextSummary(_ priority: PrioritySnapshot) -> some View {
        let items = priority.contextItems.count
        let rules = priority.rules.count
        if items == 0 && rules == 0 {
            ShellText(.cockpitContextSummaryEmpty, role: .footnote)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            ShellText(
                .cockpitContextSummary,
                role: .footnote,
                arguments: [items.formatted(), rules.formatted()]
            )
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
        }
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
    /// The standing priorities, drawn on Now while planning, and while working only once
    /// *Change priority* has opened the capture field (focus-g9iw; see
    /// `CockpitWiring.showsStanding`). They report from where they are drawn;
    /// `hiddenTabReceipts` covers the rest.
    private var standingSection: some View {
        StandingPrioritiesView(rows: state.standing, activate: wiring.activate)
            .shellRendered(.standingCount, state.standing.count)
            .shellRendered(.standingDigest, ShellValueDigest.describe(state.standing))
    }

    private var showsCapture: Bool {
        wiring.showsCapture(requestedFor: capturePriorityID)
    }

    /// Focus the inserted field once its reveal transition has finished.
    private func beginCapture() {
        beginCapturing(keepingContext: false)
    }

    /// One sentence in, one priority out.
    ///
    /// Committing while a priority already exists **replaces** it: a second activation
    /// replaces, never queues (F-02), and the replaced task keeps every word, context item
    /// and rule it had, because the store re-points a pointer rather than deleting a row.
    private var capture: some View {
        CaptureFieldView(
            commit: { intent, doneWhen in
                if isKeepingContext, let keep = wiring.setPriorityKeepingContext {
                    keep(intent, doneWhen)
                } else {
                    wiring.setPriority?(intent, doneWhen)
                }
                capturePriorityID = nil
                isKeepingContext = false
            },
            isEnabled: actions != nil,
            fieldFocus: .cockpitCaptureField,
            buttonFocus: .cockpitSetPriority,
            focus: $focus
        )
    }

    private var primaryActions: some View {
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
                sameContextButton
                clearButton
            }
            VStack(alignment: .leading, spacing: rowSpacing) {
                HStack(spacing: rowSpacing) {
                    completeButton
                    changeButton
                    sameContextButton
                }
                clearButton
            }
            VStack(alignment: .leading, spacing: rowSpacing) {
                HStack(spacing: rowSpacing) {
                    completeButton
                    changeButton
                }
                sameContextButton
                clearButton
            }
            VStack(alignment: .leading, spacing: rowSpacing) {
                completeButton
                changeButton
                sameContextButton
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
        // Every control carries a tooltip from the catalog (focus-8ski); see `ShellHelp`.
        .shellHelp(.priorityActionCompleteHelp)
    }

    /// Replace the commitment with a new one, through the capture field.
    @ViewBuilder
    private var changeButton: some View {
        if !showsCapture {
            Button {
                beginCapturing(keepingContext: false)
            } label: {
                ShellText(.priorityActionChange)
            }
            .disabled(actions == nil)
            .shellHelp(.priorityActionChangeHelp)
            .walkthroughAnchor(.changePriorityButton)
        }
    }

    /// **A new priority on the same desk** (focus-1rj7): a different job, the same apps, sites,
    /// keywords, files and verdicts. Opens the capture field with the desk marked to be kept;
    /// the copy happens in the host, in one transaction, when the sentence is committed.
    @ViewBuilder
    private var sameContextButton: some View {
        if !showsCapture {
            Button {
                beginCapturing(keepingContext: true)
            } label: {
                ShellText(.priorityActionSameContext)
            }
            .focused($focus, equals: .cockpitSameContext)
            .disabled(wiring.setPriorityKeepingContext == nil)
            .shellHelp(.priorityActionSameContextHelp)
        }
    }

    /// Open the capture field, and put the caret in it once its reveal has finished.
    ///
    /// `keepingContext` is what the "New Priority, Same Context…" verb sets (focus-1rj7); the
    /// animated reveal and completion-timed focus are the companion round's (focus-oqsx).
    private func beginCapturing(keepingContext: Bool) {
        isKeepingContext = keepingContext
        tab = .now
        guard !showsCapture else {
            focus = .cockpitCaptureField
            return
        }
        withAnimation(DesignTokens.animation(for: traits), completionCriteria: .removed) {
            capturePriorityID = state.priority?.id
        } completion: {
            focus = .cockpitCaptureField
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
        .shellHelp(.priorityActionClearHelp)
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
            .shellHelp(.cockpitOpenSettingsHelp)
            .walkthroughAnchor(.openSettingsButton)
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
    /// The receipt reports the **conjunction** the footer drew, for a two-sided reason: an offer
    /// that appears when it should not is a row asking for something already declined, and one
    /// that never appears is a feature nobody can find.
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
                .shellHelp(.cockpitLaunchAtLoginAcceptHelp)

                Button {
                    onLaunchAtLoginOffer(.dismiss)
                } label: {
                    ShellText(.cockpitLaunchAtLoginDismiss, role: .footnote)
                }
                .shellHelp(.cockpitLaunchAtLoginDismissHelp)
            }
        }
    }

    // MARK: - The destinations (focus-1rj7, focus-g9iw)

    /// **A segmented switcher on a glass track** — the cockpit's one custom glass element,
    /// because it is the window's navigation (`Design/LiquidGlass.md`). The track is
    /// regular, untinted glass; the open destination is an opaque pane-coloured thumb with a soft
    /// lift and primary ink, which slides between the tabs. No word ever sits on tinted glass.
    /// With glass off the track is the opaque ground with a hairline, and under Reduce Motion the
    /// thumb moves without animating.
    ///
    /// Drawn by hand rather than as a `Picker` or a `TabView`, for two measured reasons: a
    /// segmented `Picker` is AppKit-backed and rasterises under `ImageRenderer` as the yellow
    /// "unrenderable view" placeholder, which would put a yellow bar in every cockpit baseline;
    /// and a macOS `TabView` builds only the selected pane, which is exactly the shape that
    /// loses receipts (see `ShellRenderedField.settingsTab`). Plain buttons and a switch keep
    /// the whole column one SwiftUI tree the lane can photograph and the audit can read.
    private var tabBar: some View {
        let track = Capsule(style: .continuous)
        let glass = DesignTokens.drawsGlass(for: traits)
        let firm = DesignTokens.emphasis(for: traits).promotesSecondaryText
        return GlassEffectContainer(spacing: rowSpacing) {
            HStack(spacing: rowSpacing / 4) {
                ForEach(CockpitTab.allCases) { candidate in
                    tabButton(candidate)
                }
            }
            .padding(rowSpacing / 4)
            .background {
                if glass {
                    Color.clear.glassEffect(.regular, in: track)
                } else {
                    track.fill(DesignTokens.Palette.role(DesignTokens.groundRole(for: traits), for: traits))
                }
            }
            .overlay(track.strokeBorder(
                DesignTokens.Palette.role(.mist, for: traits).opacity(firm ? 1 : (glass ? 0 : 0.3)),
                lineWidth: firm ? 2 : 1
            ))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func tabLozenge(isOpen: Bool) -> some View {
        let lozenge = Capsule(style: .continuous)
        if isOpen {
            lozenge
                .fill(DesignTokens.Palette.role(DesignTokens.paneRole(for: traits), for: traits))
                .overlay(lozenge.strokeBorder(
                    DesignTokens.Palette.role(DesignTokens.emphasis(for: traits).promotesSecondaryText
                        ? .slate : .mist, for: traits)
                        .opacity(DesignTokens.emphasis(for: traits).promotesSecondaryText ? 1 : 0.18),
                    lineWidth: DesignTokens.emphasis(for: traits).promotesSecondaryText ? 2 : 1
                ))
                .shadow(
                    color: DesignTokens.Palette.role(.slate, for: traits).opacity(0.14),
                    radius: 4,
                    y: 1
                )
                .matchedGeometryEffect(id: "cockpit.tab.lozenge", in: tabLozengeSpace)
        }
    }

    @ViewBuilder
    private func tabButton(_ candidate: CockpitTab) -> some View {
        let isOpen = candidate == tab
        let button = Button {
            if tab == .now, candidate != .now, let priority = state.priority {
                commitDoneWhen(priority)
            }
            withAnimation(DesignTokens.liquidAnimation(for: traits)) {
                tab = candidate
            }
        } label: {
            ShellText(candidate.titleKey, role: .headline)
                .foregroundStyle(
                    isOpen
                        ? DesignTokens.Palette.role(.slate, for: traits)
                        : DesignTokens.supportingTextColor(for: traits)
                )
                .padding(.horizontal, sectionSpacing * 0.8)
                .padding(.vertical, rowSpacing / 2)
                .background { tabLozenge(isOpen: isOpen) }
                .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOpen ? [.isSelected] : [])
        .shellHelp(Self.tabHelpKey(candidate))
        // One focus identity for the bar, carried by the open tab (see `FocusField.cockpitTabs`).
        if isOpen {
            button.focused($focus, equals: .cockpitTabs)
        } else {
            button
        }
    }

    /// What each destination's tooltip says it holds (focus-8ski).
    private static func tabHelpKey(_ tab: CockpitTab) -> ShellStringKey {
        switch tab {
        case .now: .cockpitTabNowHelp
        case .history: .cockpitTabHistoryHelp
        case .tasks: .cockpitTabTasksHelp
        }
    }

    /// History's route to the day's full record: the window `HistoryView` draws.
    private var openHistoryButton: some View {
        Button {
            openWindow(id: ShellWindow.history.id)
        } label: {
            ShellText(.cockpitOpenHistory, role: .callout)
        }
        .focused($focus, equals: .cockpitOpenHistory)
        .shellHelp(.cockpitOpenHistoryHelp)
    }

    /// The receipts of the sections on the destination that is not open (focus-1rj7, focus-g9iw).
    ///
    /// With History open, everything Now draws — the hero, the status, the definition of done
    /// and the session — reports from here. With no commitment and no session,
    /// `absentCommitmentReceipts` already reports those fields as `noCommitment`, on both.
    @ViewBuilder
    private var hiddenTabReceipts: some View {
        if tab != .history {
            Color.clear
                .shellRendered(.recentCount, state.earlierPriorities.count)
                .shellRendered(.recentDigest, ShellValueDigest.describe(state.earlierPriorities))
        }
        if !state.standing.isEmpty && !standingIsDrawn {
            Color.clear
                .shellRendered(.standingCount, state.standing.count)
                .shellRendered(.standingDigest, ShellValueDigest.describe(state.standing))
        }
        if tab != .now {
            Color.clear
                .shellRendered(.priorityIntent, state.priority?.intent ?? "")
                .shellRendered(.status, state.status.rawValue)
                .shellRendered(.priorityDetail, ShellValueDigest.describe(state.priority))
            if let priority = state.priority {
                Color.clear
                    .shellRendered(.priorityDoneWhen, priority.doneWhen ?? "")
            }
            if drawsSession {
                Color.clear
                    .shellRendered(
                        .sessionElapsedSeconds,
                        sessionElapsedSeconds.map { String(Int($0)) } ?? "none"
                    )
                    .shellRendered(.sessionPhase, state.session?.phase.rawValue ?? "none")
                    .shellRendered(.sessionDetail, ShellValueDigest.describe(state.session))
                    .shellRendered(.lastActiveApp, lastActiveBundleID ?? "none")
            }
        }
    }

    /// **A well: one zone of the column on its own card** (focus-6uya), the same opaque pane
    /// Settings uses (`companionSurface`), so working groups share one piece of furniture.
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
