import FocusCore
import SwiftUI

/// The session, and every verb that can be applied to it (F-98, F-99).
///
/// ## What it draws, and what it refuses to draw
///
/// The phase badge, the elapsed figure, the reasons a paused session is paused, and the verbs
/// the machine would actually accept from here. It draws **no** verb the transition table would
/// reject: a paused session is inert, so it offers neither Detour nor Break, because a button
/// that is refused on press is a button that teaches people the app is unreliable.
///
/// The one rejection worth surfacing is surfaced *before* it can happen. `resumed(cause: .user)`
/// against a session the screen lock paused is rejected `notPausedForThatCause`, so Resume is
/// **disabled with the reasons listed underneath it** while a cause the person cannot clear is
/// still held. A person is entitled to know why the button will not work; they are not entitled
/// to be told it will and then have nothing happen.
///
/// ## There is no clock in here
///
/// `elapsedSeconds` is passed in, computed by whoever owns the injected wall clock — exactly as
/// `TimeboxState` already is. There is no timer object anywhere in this programme, so the
/// figure is a value read at a moment somebody chose, and this view is therefore renderable at a
/// fixed instant in the snapshot lane.
public struct SessionControls: View {
    /// The session, or `nil` when there is none. `nil` is a real answer: sensing runs whether
    /// or not a session does.
    public let session: SessionSnapshot?

    /// How long it has been running on the clock on the wall, or `nil` when nobody has read a
    /// clock. Never computed here.
    public let elapsedSeconds: Double?

    /// The last application that was in front which was **not** this one, as a bundle
    /// identifier and nothing else (F-101).
    ///
    /// Passed in rather than read here: `FocusUI` never asks the system anything. It is a
    /// bundle identifier — never a window title, never a document, never a URL — and the sheet
    /// says so plainly when there is none.
    public let lastActiveBundleID: String?

    /// The mutation host, or `nil` for the read-only cockpit the snapshot lane renders. Every
    /// control is disabled while it is `nil`, so a button can never look live and do nothing.
    public let actions: (any SessionActing)?

    /// **The Now tab's reading of the session** (focus-1rj7): the phase, the elapsed time, the
    /// causes that explain a disabled Resume, and the verbs that change the phase. The notes
    /// and the two endings belong to the Details tab, where the whole session is drawn.
    public let compact: Bool

    @Environment(\.appearanceTraits) private var traits
    @Environment(\.shellTextScale) private var textScale
    @FocusState.Binding private var focus: FocusField?
    @ScaledMetric(relativeTo: .body) private var spacing: CGFloat = 8
    /// The least width a verb glyph claims, so "play" and "pause" make buttons of one size.
    @ScaledMetric(relativeTo: .body) private var glyphWidth: CGFloat = 20

    /// Whether the interruption sheet is up. Stopping is a deliberate act with something worth
    /// recording, so it gets a sheet rather than happening under the pointer.
    @State private var isInterrupting = false

    public init(
        session: SessionSnapshot?,
        elapsedSeconds: Double? = nil,
        lastActiveBundleID: String? = nil,
        actions: (any SessionActing)? = nil,
        compact: Bool = false,
        focus: FocusState<FocusField?>.Binding
    ) {
        self.session = session
        self.elapsedSeconds = elapsedSeconds
        self.lastActiveBundleID = lastActiveBundleID
        self.actions = actions
        self.compact = compact
        self._focus = focus
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            CompanionSectionHeading(key: .sessionHeading, symbol: "waveform.path")
                .foregroundStyle(DesignTokens.Palette.role(.spruce, for: traits))

            if let session {
                running(session)
            } else {
                idle
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(ShellStrings.resource(.sessionHeading)))
        .sheet(isPresented: $isInterrupting) {
            InterruptionSheet(
                lastActiveBundleID: lastActiveBundleID,
                stop: { reason, note in
                    actions?.interruptSession(reason: reason, note: note)
                    isInterrupting = false
                },
                cancel: { isInterrupting = false }
            )
        }
        // **The application the interruption sheet will name** (focus-7ow, F-101).
        //
        // Reported here rather than from the sheet, and that is the honest place: the sheet is
        // built only while a person is interrupting, so a receipt inside it would be a receipt
        // nothing in the programme ever collects. This is the identifier the sheet is about to be
        // handed, on the view that is holding it — so a cockpit that passes down an application
        // which is not installed, or the wrong one, or none, changes what is reported.
        .shellRendered(.lastActiveApp, lastActiveBundleID ?? "none")
    }

    // MARK: - No session

    private var idle: some View {
        VStack(alignment: .leading, spacing: spacing) {
            ShellText(.sessionNone, role: .callout)
                .foregroundStyle(DesignTokens.supportingTextColor(for: traits))
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)

            startButton
        }
    }

    // MARK: - A session

    @ViewBuilder
    private func running(_ session: SessionSnapshot) -> some View {
        VStack(alignment: .leading, spacing: spacing) {
            HStack(alignment: .firstTextBaseline, spacing: spacing) {
                SessionPhaseBadge(phase: session.phase)
                    .id(session.phase)
                    .transition(traits.reduceMotion ? .identity : .opacity)

                if let elapsedSeconds {
                    Text(verbatim: Self.format(elapsedSeconds))
                        .font(DesignTokens.font(.largeTitle, scale: textScale).monospacedDigit())
                        .contentTransition(traits.reduceMotion ? .identity : .numericText())
                        .animation(DesignTokens.animation(for: traits), value: Self.format(elapsedSeconds))
                        .foregroundStyle(DesignTokens.Palette.role(.spruce, for: traits))
                        .accessibilityLabel(Text(ShellStrings.string(.sessionElapsed, argument: Self.format(elapsedSeconds))))
                }

                Spacer(minLength: 0)
            }
            .padding(.vertical, spacing)
            .animation(DesignTokens.animation(for: traits), value: session.phase)

            causes(session)
            if !compact { notes(session) }
            verbs(session)
        }
    }

    /// Why a paused session is paused, one reason per line, with the pause the person cannot
    /// clear stated as plainly as the one they can.
    @ViewBuilder
    private func causes(_ session: SessionSnapshot) -> some View {
        if !session.pauseCauses.isEmpty {
            VStack(alignment: .leading, spacing: spacing / 3) {
                ShellText(.sessionCauseHeading, role: .caption)
                    .foregroundStyle(DesignTokens.supportingTextColor(for: traits))

                // Sorted, because `PauseReason` is `Comparable` for exactly this reason: a set
                // drawn in hash order would reorder itself between two renders of the same
                // state, which would make the surface look alive when nothing had changed.
                ForEach(session.pauseCauses.sorted(), id: \.self) { cause in
                    Label {
                        ShellText(SessionPhaseBadge.labelKey(for: cause), role: .callout)
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "circle.fill")
                            .font(DesignTokens.font(.caption))
                    }
                }

                if !session.causesTheUserCannotClear.isEmpty {
                    ShellText(.sessionResumeBlocked, role: .footnote)
                        .foregroundStyle(DesignTokens.supportingTextColor(for: traits))
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// What restoring this session had to say about it — a reboot, a long absence, or a clock
    /// that moved while it ran.
    ///
    /// Shown rather than swallowed. The elapsed figure above is still the wall-clock one,
    /// because a timebox is a promise about the clock on the wall; telling somebody the clock
    /// changed is better than showing them a number the app already knows is suspect.
    @ViewBuilder
    private func notes(_ session: SessionSnapshot) -> some View {
        if !session.notes.isEmpty {
            VStack(alignment: .leading, spacing: spacing / 3) {
                ForEach(session.notes.sorted(by: { $0.rawValue < $1.rawValue }), id: \.self) { note in
                    Label {
                        ShellText(SessionPhaseBadge.labelKey(for: note), role: .footnote)
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "clock.arrow.circlepath")
                    }
                    .foregroundStyle(DesignTokens.supportingTextColor(for: traits))
                }
            }
        }
    }

    /// Exactly the verbs the machine would accept from this phase, and no others —
    /// **grouped by what they cost** (focus-w41, direction §5.1).
    ///
    /// `D02` shows what this looked like before: one row of identically weighted lozenges in
    /// which "Pause Session", "Finish Session" and "25 min" were all the same object. Pausing a
    /// session and ending one are not the same act and must not read as one, so the row now has
    /// three registers, in the order the canvas puts them:
    ///
    /// - **The one thing you are most likely to want**, filled in the person's own accent:
    ///   Pause while it runs, Resume while it is held, Start when there is none.
    /// - **The two ways of stepping out and coming back**, bordered and secondary: a detour and
    ///   a break. They change what the session *is* without ending it.
    /// - **The ways it ends**, at the trailing edge, drawn as plain links rather than buttons.
    ///   A link is not a lesser control — it is a control that does not invite the pointer, which
    ///   is the correct posture for the two verbs that cannot be undone.
    ///
    /// Nothing is added, removed or renamed: the same verbs the transition table accepts, in the
    /// same phases, with the same keys. `FocusTraversal`'s pinned order is therefore unchanged —
    /// `cockpitSessionPrimary` is still the section's one focus identity and still lands on
    /// whichever verb is primary in the phase the session is in.
    @ViewBuilder
    private func verbs(_ session: SessionSnapshot) -> some View {
        let row = HStack(spacing: spacing) {
            verbButtons(session)
            // The shelf between the reversible verbs and the terminal ones. It is the whole of
            // the grouping in the wide case: consequence reads as distance.
            if session.phase.offersAnEnding, !compact {
                Spacer(minLength: spacing)
                endings
            }
        }
        let column = VStack(alignment: .leading, spacing: spacing) {
            verbButtons(session)
            if session.phase.offersAnEnding, !compact { endings }
        }

        // The same discipline the priority actions use: the row wraps to a column rather than
        // letting a label truncate. A button reading "Stop and Say…" is a control a person has
        // to guess at.
        ViewThatFits(in: .horizontal) {
            row
            column
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The two verbs that end a session, drawn as links at the trailing edge.
    @ViewBuilder
    private var endings: some View {
        HStack(spacing: spacing) {
            linkButton(.sessionActionInterrupt, symbol: "stop.fill", help: .sessionActionInterruptHelp) {
                isInterrupting = true
            }
            linkButton(.sessionActionComplete, symbol: "checkmark", help: .sessionActionCompleteHelp) {
                actions?.completeSession()
            }
        }
    }

    @ViewBuilder
    private func verbButtons(_ session: SessionSnapshot) -> some View {
        switch session.phase {
        case .focus:
            primaryButton(.sessionActionPause, symbol: "pause.fill", help: .sessionActionPauseHelp) {
                actions?.pauseSession()
            }
            button(.sessionActionBreakStart, symbol: "cup.and.saucer.fill", help: .sessionActionBreakStartHelp) {
                actions?.startBreak(reason: .user)
            }
            button(.sessionActionDetourStart, symbol: "arrow.triangle.branch", help: .sessionActionDetourStartHelp) {
                actions?.startDetour(reason: .user)
            }

        case .intentionalDetour:
            primaryButton(.sessionActionPause, symbol: "pause.fill", help: .sessionActionPauseHelp) {
                actions?.pauseSession()
            }
            button(.sessionActionDetourEnd, symbol: "arrow.uturn.left", help: .sessionActionDetourEndHelp) {
                actions?.endDetour()
            }
            // Legal only from focus, so the host ends the detour first and the machine records
            // two transitions — which is what keeps the timeline honest about what happened.
            button(.sessionActionBreakStart, symbol: "cup.and.saucer.fill", help: .sessionActionBreakStartHelp) {
                actions?.startBreak(reason: .user)
            }

        case .onBreak:
            primaryButton(.sessionActionPause, symbol: "pause.fill", help: .sessionActionPauseHelp) {
                actions?.pauseSession()
            }
            button(.sessionActionBreakEnd, symbol: "arrow.uturn.left", help: .sessionActionBreakEndHelp) {
                actions?.endBreak()
            }

        case .paused:
            // Disabled, with the reasons listed above it, whenever a cause the person did not
            // set is still held — because the machine would reject the resume. The tooltip on
            // the disabled control says the same thing the footnote does (focus-8ski).
            primaryButton(
                .sessionActionResume,
                symbol: "play.fill",
                help: .sessionActionResumeHelp,
                disabledHelp: .sessionResumeBlocked,
                isEnabled: session.userMayResume
            ) {
                actions?.resumeSession()
            }

        case .interrupted, .complete:
            // Terminal is terminal. The only thing left to do is begin again.
            startButton
        }
    }

    private var startButton: some View {
        primaryButton(.sessionActionStart, symbol: "play.fill", help: .sessionActionStartHelp) {
            actions?.startSession(kind: .openEnded, plannedSeconds: nil, deadlineAt: nil)
        }
    }

    /// **The verbs are glyphs, and the sentence is in the tooltip** (focus-8ski).
    ///
    /// Each button draws an SF Symbol and nothing else; the catalog label the button used to
    /// draw is now its accessibility label, so VoiceOver and the keyboard-reachability tests
    /// read the same verb they always did, and the tooltip carries the label *and* what
    /// pressing it changes. The glyph is drawn at the callout size the label was, so the
    /// buttons keep the height of the row they sit in.
    private func glyph(_ symbol: String, labelled key: ShellStringKey) -> some View {
        Image(systemName: symbol)
            .font(DesignTokens.font(.callout, scale: textScale).weight(.semibold))
            .frame(minWidth: glyphWidth)
            .accessibilityLabel(Text(ShellStrings.resource(key)))
    }

    /// The one button in this section that carries the surface's declared focus identity.
    ///
    /// One identity for the control, not one per verb: the traversal model names the session
    /// control, and Tab lands on whichever verb is primary in the phase the session is actually
    /// in — Start, Pause or Resume.
    private func primaryButton(
        _ key: ShellStringKey,
        symbol: String,
        help: ShellStringKey,
        disabledHelp: ShellStringKey? = nil,
        isEnabled: Bool = true,
        perform: @escaping () -> Void
    ) -> some View {
        Button(action: perform) {
            glyph(symbol, labelled: key)
        }
        // **Filled, not merely tinted** (focus-w41). `.bordered` with a tint drew the primary
        // verb as the same object as the four beside it in a slightly different colour, which is
        // the flattening `D02` shows. `.borderedProminent` is the platform's own way of saying
        // "this one", and the fill is the person's accent rather than a hue the app chose.
        .buttonStyle(CompanionButtonStyle(prominent: true))
        .tint(DesignTokens.Palette.accent(for: traits))
        .focused($focus, equals: .cockpitSessionPrimary)
        .disabled(actions == nil || !isEnabled)
        .shellHelp(help, disabled: disabledHelp ?? help, when: !isEnabled)
    }

    private func button(
        _ key: ShellStringKey,
        symbol: String,
        help: ShellStringKey,
        perform: @escaping () -> Void
    ) -> some View {
        Button(action: perform) {
            glyph(symbol, labelled: key)
        }
        .buttonStyle(CompanionButtonStyle())
        .disabled(actions == nil)
        .shellHelp(help)
    }

    /// A verb that ends the session: drawn in the person's accent, at the trailing edge.
    ///
    /// Not a *lesser* control. It does not invite the pointer the way the primary lozenge does,
    /// and the two verbs it draws — stop and say why, and finish — are the two that cannot be
    /// undone. They stay full-sized, full-contrast and fully keyboard-reachable; what they lose
    /// is the visual claim on being pressed next.
    private func linkButton(
        _ key: ShellStringKey,
        symbol: String,
        help: ShellStringKey,
        perform: @escaping () -> Void
    ) -> some View {
        Button(action: perform) {
            glyph(symbol, labelled: key)
        }
        .buttonStyle(CompanionButtonStyle())
        .tint(DesignTokens.Palette.accent(for: traits))
        .disabled(actions == nil)
        .shellHelp(help)
    }

    // MARK: - Formatting

    /// The elapsed figure, as data rather than prose.
    ///
    /// `Duration.UnitsFormatStyle` throughout, never minutes interpolated into a sentence, so
    /// the units read correctly in a locale that does not write them the way English does. Under
    /// a minute the zero is *shown* — "0 min" is a truthful answer for a session six seconds
    /// old, and an empty string is not.
    nonisolated static func format(_ seconds: Double) -> String {
        let whole = max(0, Int(seconds.rounded()))
        let duration = Duration.seconds(whole)
        guard whole >= 60 else {
            return duration.formatted(
                .units(allowed: [.minutes], width: .abbreviated, zeroValueUnits: .show(length: 1))
            )
        }
        return duration.formatted(
            .units(allowed: [.hours, .minutes], width: .abbreviated, zeroValueUnits: .hide)
        )
    }
}

extension SessionPhase {
    /// Whether a session in this phase can still be ended from the cockpit.
    ///
    /// Four of the six can: a running, detoured, paused or resting session is a session, and the
    /// two verbs that end one apply to all four. `interrupted` and `complete` are already ended —
    /// offering to end them again would be a control that is refused on press, which is exactly
    /// what this view refuses to draw.
    ///
    /// Declared here rather than inlined at the two call sites in `verbs(_:)` so the row and the
    /// column cannot disagree about it: a wrapped layout that dropped the endings would be a
    /// window in which the only way to finish a session is to make it wider.
    var offersAnEnding: Bool {
        switch self {
        case .focus, .intentionalDetour, .onBreak, .paused: true
        case .interrupted, .complete: false
        }
    }
}
