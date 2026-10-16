import FocusCore
import SwiftUI

/// One optional duration on the priority, and where it has got to (F-12).
///
/// Four choices — 25, 50, 90 minutes, or None — and no scheduling machinery of any kind
/// (Court). The state is a pure function of the timebox, its start and the wall clock, so
/// nothing has to fire for the number to be right.
///
/// **Every duration is rendered through `Duration.UnitsFormatStyle`**, never by interpolating
/// minutes into a string. That is what makes "1 hr, 5 min" read correctly in a locale that
/// does not write it the way English does. The presets allow minutes only, because they are
/// *named* in minutes and a button reading "1 hr, 30 min" makes a person do arithmetic to
/// recognise the choice they are being offered.
///
/// The elapsed readout is drawn at `.callout`. Nothing here competes with the hero.
///
/// **A focus block may not be scheduled into a meeting** (focus-cal). When the person switched
/// their calendar on, a preset that would still be running when the next meeting starts is
/// disabled and says why, every preset is disabled during a meeting, and an *Until the meeting*
/// choice offers the room that is left. With the calendar unread — every install that did not
/// switch it on — the control draws exactly what it drew before.
public struct TimeboxControl: View {
    public let timeboxSeconds: Int?
    public let state: TimeboxState
    /// What the person's calendar says about the time from now on. `.unread` draws nothing.
    public let calendar: CalendarOutlook
    /// Today's busy time, drawn as a strip under the calendar's line (focus-ext). `.unread` draws nothing.
    public let day: CalendarDay
    /// Choose a timebox, or `nil` for none. `nil` here means "no mutation host attached".
    public let choose: ((Int?) -> Void)?

    @Environment(\.appearanceTraits) private var traits
    @Environment(\.shellTextScale) private var textScale
    @FocusState.Binding var focus: FocusField?
    @ScaledMetric(relativeTo: .body) private var spacing: CGFloat = 8

    public init(
        timeboxSeconds: Int?,
        state: TimeboxState,
        calendar: CalendarOutlook = .unread,
        day: CalendarDay = .unread,
        choose: ((Int?) -> Void)? = nil,
        focus: FocusState<FocusField?>.Binding
    ) {
        self.timeboxSeconds = timeboxSeconds
        self.state = state
        self.calendar = calendar
        self.day = day
        self.choose = choose
        self._focus = focus
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: spacing / 2) {
            HStack(spacing: spacing) {
                CompanionSectionHeading(key: .priorityTimeboxLabel, symbol: "timer")
                    .foregroundStyle(DesignTokens.Palette.role(.spruce, for: traits))

                if let readoutKey, let duration = state.duration {
                    Label {
                        ShellText(readoutKey, role: .callout, argument: Self.format(duration))
                    } icon: {
                        Image(systemName: state.isOvertime ? "exclamationmark.circle" : "timer")
                    }
                    // The remaining time in the app's own hue (focus-6uya): a reading, not a
                    // warning, so it is Spruce and never Kiln. Overtime keeps the system's
                    // orange, which is the one colour a person already reads as "past it".
                    .foregroundStyle(
                        state.isOvertime
                            ? Color(nsColor: .systemOrange)
                            : DesignTokens.Palette.role(.spruce, for: traits)
                    )
                }

                Spacer(minLength: 0)
            }

            HStack(spacing: spacing) {
                ForEach(Array(TimeboxState.presetSeconds.enumerated()), id: \.element) { index, seconds in
                    presetButton(seconds: seconds, isFirst: index == 0)
                }

                if let room = untilTheMeetingSeconds {
                    untilTheMeetingButton(seconds: room)
                }

                Button {
                    choose?(nil)
                } label: {
                    ShellText(.priorityTimeboxNone, role: .callout)
                }
                .buttonStyle(CompanionButtonStyle())
                .disabled(choose == nil || timeboxSeconds == nil)
                // Tooltips from the catalog (focus-8ski); a disabled control says why.
                .shellHelp(
                    .priorityTimeboxNoneHelp,
                    disabled: .priorityTimeboxNoneDisabledHelp,
                    when: choose == nil || timeboxSeconds == nil
                )

                Spacer(minLength: 0)
            }

            if let calendarLine {
                Label {
                    ShellText(calendarLine.key, role: .footnote, argument: calendarLine.time)
                } icon: {
                    Image(systemName: "calendar")
                }
                .foregroundStyle(DesignTokens.supportingTextColor(for: traits))
            }

            CalendarDayStrip(day: day)
        }
    }

    /// One preset. Only the first carries a declared focus identity — the traversal model
    /// names the control, not each of its four buttons.
    @ViewBuilder
    private func presetButton(seconds: Int, isFirst: Bool) -> some View {
        let button = Button {
            // Choosing the timebox you already have clears it. A control with no way back is
            // a control people learn not to touch.
            choose?(timeboxSeconds == seconds ? nil : seconds)
        } label: {
            // The label is a formatted duration, which is data rather than prose: it must
            // never be routed through a String Catalog.
            Text(verbatim: Self.formatPreset(.seconds(seconds)))
                .font(DesignTokens.font(.callout, scale: textScale))
        }
        .buttonStyle(CompanionButtonStyle())
        .tint(timeboxSeconds == seconds ? DesignTokens.Palette.accent(for: traits) : nil)
        .disabled(choose == nil || refusal(for: seconds) != nil)
        // After `.disabled`, so the reason shows on the control that is off (focus-8ski).
        .shellHelp(
            .priorityTimeboxPresetHelp,
            disabled: refusalHelpKey(for: seconds),
            when: refusal(for: seconds) != nil
        )

        if isFirst {
            button.focused($focus, equals: .cockpitTimebox)
        } else {
            button
        }
    }

    /// Why choosing `seconds` now would be refused, or `nil`. Choosing the timebox already set
    /// clears it, and clearing is never refused.
    private func refusal(for seconds: Int) -> TimeboxRefusal? {
        guard timeboxSeconds != seconds else { return nil }
        return calendar.refusal(forTimeboxSeconds: seconds)
    }

    private func refusalHelpKey(for seconds: Int) -> ShellStringKey {
        switch refusal(for: seconds) {
        case .duringMeeting: .priorityTimeboxDuringMeetingHelp
        case .runsIntoMeeting, nil: .priorityTimeboxRunsIntoMeetingHelp
        }
    }

    /// The room before the next meeting, offered when it is worth offering: there is a meeting
    /// ahead, at least one preset would run into it, and the room is not already a preset.
    private var untilTheMeetingSeconds: Int? {
        guard let room = calendar.roomBeforeMeetingSeconds,
              !TimeboxState.presetSeconds.contains(room),
              TimeboxState.presetSeconds.contains(where: { refusal(for: $0) != nil })
        else { return nil }
        return room
    }

    private func untilTheMeetingButton(seconds: Int) -> some View {
        Button {
            choose?(timeboxSeconds == seconds ? nil : seconds)
        } label: {
            ShellText(.priorityTimeboxUntilMeeting, role: .callout)
        }
        .buttonStyle(CompanionButtonStyle())
        .tint(timeboxSeconds == seconds ? DesignTokens.Palette.accent(for: traits) : nil)
        .disabled(choose == nil)
        .shellHelp(.priorityTimeboxUntilMeetingHelp)
    }

    /// The calendar's one line under the presets: when the meeting under way ends, or when the
    /// next one starts. Nothing when the calendar is unread or clear.
    private var calendarLine: (key: ShellStringKey, time: String)? {
        switch calendar {
        case .unread, .clear:
            nil
        case .inMeeting(let endsAt, _):
            (.priorityTimeboxInMeeting, Self.formatTime(endsAt))
        case .meetingAhead(let startsAt, _):
            (.priorityTimeboxNextMeeting, Self.formatTime(startsAt))
        }
    }

    /// A clock time in the person's own format — "14:30" or "2:30 PM" — which is data.
    static func formatTime(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    private var readoutKey: ShellStringKey? {
        switch state {
        case .none: nil
        case .running: .priorityTimeboxRemaining
        case .overtime: .priorityTimeboxOvertime
        }
    }

    /// The readout: how much of the box is left, or how far past it we are.
    ///
    /// Hours are allowed because a box can be overrun by more than one.
    static func format(_ duration: Duration) -> String {
        duration.formatted(
            .units(allowed: [.hours, .minutes], width: .abbreviated, zeroValueUnits: .hide)
        )
    }

    /// A preset's own label.
    ///
    /// Minutes only, deliberately: the three presets are *named* in minutes — 25, 50, 90 —
    /// and a button reading "1 hr, 30 min" makes the user do arithmetic to recognise the
    /// choice they are being offered. Still `Duration.UnitsFormatStyle`, so the unit is
    /// whatever the locale calls a minute.
    static func formatPreset(_ duration: Duration) -> String {
        duration.formatted(.units(allowed: [.minutes], width: .abbreviated))
    }
}
