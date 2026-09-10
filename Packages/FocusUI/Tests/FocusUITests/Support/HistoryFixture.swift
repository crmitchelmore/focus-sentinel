import FocusCore
import Foundation

/// **One day with one of every row**, so a picture of History shows every shape the surface can
/// draw rather than whichever shapes the machine that recorded it happened to have.
///
/// Fixed identifiers and a fixed instant, exactly as the schema fixtures are: a baseline whose
/// content depends on the clock is a baseline that has to be re-recorded every day. The subjects
/// are **system applications** for the same reason: `SubjectDisplay` resolves an installed name
/// and falls back to the bundle identifier, so a decoy the recording machine happened to have
/// registered would give a different picture from one that did not.
///
/// It is built through `DayHistory`'s public initialiser rather than through `build(…)`, because
/// `build(…)` needs a store and `FocusUI` holds no SwiftData — which is the boundary this whole
/// surface depends on. What the builder does is asserted by `DayHistoryTests` in `FocusCore` and
/// by the self-check's seeded ledger in the shipping binary; what this lane asserts is the
/// drawing.
enum HistoryFixture {
    /// 2026-01-01T09:00:00Z, and every row a fixed number of minutes after it.
    static let reference = Date(timeIntervalSince1970: 1_767_258_000)
    static let priorityID = UUID(uuidString: "60606060-6060-4060-8060-606060606060")!

    static func at(_ minutes: Int) -> Date {
        reference.addingTimeInterval(Double(minutes) * 60)
    }

    static let day = DayHistory(
        day: LocalDay(year: 2026, month: 1, day: 1),
        entries: [
            .session(
                HistorySession(
                    id: UUID(uuidString: "61616161-6161-4161-8161-616161616161")!,
                    startedAt: at(0),
                    endedAt: nil,
                    kind: .countdown,
                    phase: .focus,
                    priorityID: priorityID,
                    transitions: []
                )
            ),
            .silence(
                HistorySilence(
                    id: UUID(uuidString: "62626262-6262-4262-8262-626262626262")!,
                    at: at(5),
                    subject: "com.apple.TextEdit",
                    subjectKind: .app,
                    dwellSeconds: 420,
                    priorityID: priorityID,
                    correction: .offered(
                        HistorySubject(identifier: "com.apple.TextEdit", kind: .app),
                        priorityID: priorityID
                    )
                )
            ),
            .question(
                HistoryQuestion(
                    id: UUID(uuidString: "63636363-6363-4363-8363-636363636363")!,
                    askedAt: at(12),
                    answeredAt: at(13),
                    subject: "com.apple.Notes",
                    subjectKind: .app,
                    reason: .mixedUseApplication,
                    outcome: .answeredRelevant,
                    priorityID: priorityID
                )
            ),
            .intervention(
                HistoryIntervention(
                    id: UUID(uuidString: "64646464-6464-4464-8464-646464646464")!,
                    at: at(31),
                    kind: .accusation,
                    rung: .panel,
                    subject: "com.apple.Mail",
                    subjectKind: .app,
                    surface: .panel,
                    disposition: .delivered,
                    outcome: .dismissed,
                    originatingAnswer: nil,
                    explanationKinds: [.userRule, .sustainedDwell],
                    priorityID: priorityID
                )
            ),
            // The withdrawn half, so the picture shows the sentence that takes a button's place
            // (R-88) beside a row that still has one.
            .silence(
                HistorySilence(
                    id: UUID(uuidString: "65656565-6565-4565-8565-656565656565")!,
                    at: at(44),
                    subject: "https://news.example",
                    subjectKind: .domain,
                    dwellSeconds: 180,
                    priorityID: priorityID,
                    correction: .withdrawn(.originSubject)
                )
            ),
            // A row from before schema v7: the app did not record why, and the surface says
            // *not recorded* rather than *no reasons*.
            .intervention(
                HistoryIntervention(
                    id: UUID(uuidString: "66666666-6666-4666-8666-666666666666")!,
                    at: at(58),
                    kind: .query,
                    rung: nil,
                    subject: "com.apple.Safari",
                    subjectKind: .app,
                    surface: .popoverBadge,
                    disposition: .unopened,
                    outcome: nil,
                    originatingAnswer: .no,
                    explanationKinds: nil,
                    priorityID: priorityID
                )
            )
        ],
        priorityWording: [priorityID: "Write the quarterly proposal for Dana"]
    )
}
