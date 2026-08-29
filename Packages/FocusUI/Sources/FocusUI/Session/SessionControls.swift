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

    @Environment(\.appearanceTraits) private var traits
    @FocusState.Binding private var focus: FocusField?
    @ScaledMetric(relativeTo: .body) private var spacing: CGFloat = 8

    /// Whether the interruption sheet is up. Stopping is a deliberate act with something worth
    /// recording, so it gets a sheet rather than happening under the pointer.
    @State private var isInterrupting = false

    public init(
        session: SessionSnapshot?,
        elapsedSeconds: Double? = nil,
        lastActiveBundleID: String? = nil,
        actions: (any SessionActing)? = nil,
        focus: FocusState<FocusField?>.Binding
    ) {
        self.session = session
        self.elapsedSeconds = elapsedSeconds
        self.lastActiveBundleID = lastActiveBundleID
        self.actions = actions
        self._focus = focus
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            ShellText(.sessionHeading, role: .caption)
                .foregroundStyle(DesignTokens.supportingTextColor(for: traits))

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

                if let elapsedSeconds {
                    ShellText(
                        .sessionElapsed,
                        role: .callout,
                        argument: Self.format(elapsedSeconds)
                    )
                    .foregroundStyle(DesignTokens.supportingTextColor(for: traits))
                }

                Spacer(minLength: 0)
            }

            causes(session)
            notes(session)
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

    /// Exactly the verbs the machine would accept from this phase, and no others.
    @ViewBuilder
    private func verbs(_ session: SessionSnapshot) -> some View {
        let row = HStack(spacing: spacing) { verbButtons(session) }
        let column = VStack(alignment: .leading, spacing: spacing) { verbButtons(session) }

        // The same discipline the priority actions use: the row wraps to a column rather than
        // letting a label truncate. A button reading "Stop and Say…" is a control a person has
        // to guess at.
        ViewThatFits(in: .horizontal) {
            row
            column
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func verbButtons(_ session: SessionSnapshot) -> some View {
        switch session.phase {
        case .focus:
            primaryButton(.sessionActionPause) { actions?.pauseSession() }
            button(.sessionActionBreakStart) { actions?.startBreak(reason: .user) }
            button(.sessionActionDetourStart) { actions?.startDetour(reason: .user) }
            interruptButton
            completeButton

        case .intentionalDetour:
            primaryButton(.sessionActionPause) { actions?.pauseSession() }
            button(.sessionActionDetourEnd) { actions?.endDetour() }
            // Legal only from focus, so the host ends the detour first and the machine records
            // two transitions — which is what keeps the timeline honest about what happened.
            button(.sessionActionBreakStart) { actions?.startBreak(reason: .user) }
            interruptButton
            completeButton

        case .onBreak:
            primaryButton(.sessionActionPause) { actions?.pauseSession() }
            button(.sessionActionBreakEnd) { actions?.endBreak() }
            interruptButton
            completeButton

        case .paused:
            // Disabled, with the reasons listed above it, whenever a cause the person did not
            // set is still held — because the machine would reject the resume.
            primaryButton(.sessionActionResume, isEnabled: session.userMayResume) {
                actions?.resumeSession()
            }
            interruptButton
            completeButton

        case .interrupted, .complete:
            // Terminal is terminal. The only thing left to do is begin again.
            startButton
        }
    }

    private var startButton: some View {
        primaryButton(.sessionActionStart) {
            actions?.startSession(kind: .openEnded, plannedSeconds: nil, deadlineAt: nil)
        }
    }

    private var interruptButton: some View {
        button(.sessionActionInterrupt) { isInterrupting = true }
    }

    private var completeButton: some View {
        button(.sessionActionComplete) { actions?.completeSession() }
    }

    /// The one button in this section that carries the surface's declared focus identity.
    ///
    /// One identity for the control, not one per verb: the traversal model names the session
    /// control, and Tab lands on whichever verb is primary in the phase the session is actually
    /// in — Start, Pause or Resume.
    private func primaryButton(
        _ key: ShellStringKey,
        isEnabled: Bool = true,
        perform: @escaping () -> Void
    ) -> some View {
        Button(action: perform) {
            ShellText(key, role: .callout)
        }
        .buttonStyle(.bordered)
        .tint(DesignTokens.Palette.accent(for: traits))
        .focused($focus, equals: .cockpitSessionPrimary)
        .disabled(actions == nil || !isEnabled)
    }

    private func button(
        _ key: ShellStringKey,
        perform: @escaping () -> Void
    ) -> some View {
        Button(action: perform) {
            ShellText(key, role: .callout)
        }
        .buttonStyle(.bordered)
        .disabled(actions == nil)
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
