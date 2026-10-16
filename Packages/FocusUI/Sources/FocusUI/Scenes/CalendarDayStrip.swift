import FocusCore
import SwiftUI

/// **Today's busy time, as one thin line** (focus-ext).
///
/// A track across the working day, a block for each busy stretch — from the calendar and from
/// every outside source — and a tick at now. Blocks that are over are drawn fainter. The first
/// and last hours are written under the ends; nothing else is, because the line under the
/// presets already names the meeting that matters next. Draws nothing when nothing was read or
/// today has no busy time.
struct CalendarDayStrip: View {
    let day: CalendarDay

    @Environment(\.appearanceTraits) private var traits
    @Environment(\.shellTextScale) private var textScale
    @Environment(\.locale) private var locale
    @Environment(\.timeZone) private var timeZone

    private static let trackHeight: CGFloat = 6
    private static let tickHeight: CGFloat = 12

    var body: some View {
        if day.hasBusyTime, let span = day.span {
            VStack(spacing: 2) {
                GeometryReader { geometry in
                    let width = geometry.size.width
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(DesignTokens.Palette.role(.mist, for: traits).opacity(0.35))
                            .frame(height: Self.trackHeight)
                        ForEach(Array(day.segments.enumerated()), id: \.offset) { _, segment in
                            Capsule()
                                .fill(DesignTokens.supportingTextColor(for: traits).opacity(segment.isPast ? 0.3 : 0.75))
                                .frame(width: max(2, (segment.end - segment.start) * width), height: Self.trackHeight)
                                .offset(x: segment.start * width)
                        }
                        if let now = day.nowFraction {
                            Capsule()
                                .fill(DesignTokens.Palette.role(.spruce, for: traits))
                                .frame(width: 2, height: Self.tickHeight)
                                .offset(x: min(max(0, now * width - 1), width - 2))
                        }
                    }
                    .frame(height: Self.tickHeight)
                }
                .frame(height: Self.tickHeight)

                HStack {
                    Text(verbatim: span.start.formatted(clock))
                    Spacer(minLength: 0)
                    Text(verbatim: span.end.formatted(clock))
                }
                .font(DesignTokens.font(.footnote, scale: textScale))
                .foregroundStyle(DesignTokens.supportingTextColor(for: traits))
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(ShellStrings.string(.priorityTimeboxDay, argument: accessibleRanges)))
            .shellHelp(.priorityTimeboxDayHelp)
        }
    }

    /// A clock time in the person's own format — "14:30" or "2:30 PM" — which is data.
    private var clock: Date.FormatStyle {
        Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, timeZone: timeZone)
    }

    /// "09:00 – 09:30, 14:00 – 15:00": each busy block as a clock-time range, which is data.
    private var accessibleRanges: String {
        day.busy
            .map { "\($0.start.formatted(clock)) – \($0.end.formatted(clock))" }
            .formatted(.list(type: .and, width: .narrow))
    }
}
