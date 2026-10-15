import FocusCore
import Foundation

/// **What an agent needs to know, without the activity log.**
///
/// The full export carries every activity event the app recorded. An agent asking "what is Chris
/// focused on?" needs none of it, so these summaries name the priority, the session and the
/// minutes, and leave the event stream in the export where the person chose to put it.
public struct PrioritySummary: Codable, Sendable, Equatable {
    public let id: String
    public let intent: String
    public let doneWhen: String?
    /// The work-os issue number, when the intent starts `#<n> ` as `todo.py focus` writes it.
    public let issue: Int?
    public let createdAt: Date
    public let completedAt: Date?
    public let shipped: String?
    public let restartPoint: String?
}

public struct SessionSummary: Codable, Sendable, Equatable {
    public let id: String
    public let priorityID: String?
    public let issue: Int?
    public let intent: String?
    public let startedAt: Date
    public let endedAt: Date?
    public let phase: String
    public let kind: String
    public let plannedSeconds: Int?
    /// Seconds spent in the `focus` phase only: breaks, pauses, detours and interruptions excluded.
    public let focusedSeconds: Int
}

public struct StatusSummary: Codable, Sendable, Equatable {
    public let generatedAt: Date
    public let priority: PrioritySummary?
    public let session: SessionSummary?
    public let today: Today

    public struct Today: Codable, Sendable, Equatable {
        public let sessions: Int
        public let focusedSeconds: Int
    }
}

public enum Summaries {
    public static func issueNumber(in intent: String) -> Int? {
        guard intent.hasPrefix("#") else { return nil }
        let digits = intent.dropFirst().prefix(while: \.isNumber)
        guard !digits.isEmpty else { return nil }
        let rest = intent.dropFirst(1 + digits.count)
        guard rest.first.map({ !$0.isLetter && !$0.isNumber && $0 != "_" }) ?? true else { return nil }
        return Int(digits)
    }

    /// Mirrors work-os `focused_seconds`: the phase before the first transition is that
    /// transition's `fromRaw`, or `focus` if the session never changed phase.
    public static func focusedSeconds(
        _ session: StoreExport.Session,
        transitions: [StoreExport.SessionTransition],
        now: Date
    ) -> Int {
        let start = session.startedAt
        let end = session.endedAt ?? now
        let rows = transitions.sorted { $0.at < $1.at }
        var phase = rows.first?.fromRaw ?? "focus"
        var cursor = start
        var total: TimeInterval = 0
        for row in rows {
            let at = min(max(row.at, start), end)
            if phase == "focus" { total += at.timeIntervalSince(cursor) }
            phase = row.toRaw
            cursor = at
        }
        if phase == "focus" { total += end.timeIntervalSince(cursor) }
        return max(Int(total.rounded()), 0)
    }

    public static func priority(_ p: StoreExport.Priority) -> PrioritySummary {
        PrioritySummary(
            id: p.id,
            intent: p.intent,
            doneWhen: p.doneWhen,
            issue: issueNumber(in: p.intent),
            createdAt: p.createdAt,
            completedAt: p.completedAt,
            shipped: p.shipped,
            restartPoint: p.restartPoint
        )
    }

    public static func sessions(
        in document: StoreExport.Document,
        since: Date? = nil,
        issue: Int? = nil,
        now: Date
    ) -> [SessionSummary] {
        let priorities = Dictionary(uniqueKeysWithValues: document.priorities.map { ($0.id, $0) })
        let transitions = Dictionary(grouping: document.sessionTransitions) { $0.sessionID ?? "" }
        return document.sessions
            .filter { session in since.map { session.startedAt >= $0 } ?? true }
            .map { s -> SessionSummary in
                let p = s.taskID.flatMap { priorities[$0] }
                return SessionSummary(
                    id: s.id,
                    priorityID: s.taskID,
                    issue: p.flatMap { issueNumber(in: $0.intent) },
                    intent: p?.intent,
                    startedAt: s.startedAt,
                    endedAt: s.endedAt,
                    phase: s.phaseRaw,
                    kind: s.kindRaw,
                    plannedSeconds: s.plannedSeconds,
                    focusedSeconds: focusedSeconds(s, transitions: transitions[s.id] ?? [], now: now)
                )
            }
            .filter { issue == nil || $0.issue == issue }
            .sorted { $0.startedAt < $1.startedAt }
    }

    public static func status(
        _ reading: StoreReading,
        now: Date,
        calendar: Calendar = .current
    ) -> StatusSummary {
        let document = reading.document
        let priority = reading.activePriorityID
            .flatMap { id in document.priorities.first { $0.id == id } }
            .map(Self.priority)
        let all = sessions(in: document, now: now)
        let open = all.last { $0.endedAt == nil }
        let today = all.filter { calendar.isDate($0.startedAt, inSameDayAs: now) }
        return StatusSummary(
            generatedAt: now,
            priority: priority,
            session: open,
            today: .init(sessions: today.count, focusedSeconds: today.reduce(0) { $0 + $1.focusedSeconds })
        )
    }

    public static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}
