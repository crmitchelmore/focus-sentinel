import FocusCore
import Foundation
import Testing

@testable import FocusUI

/// **No deck, on any surface, ever says the storage key** (focus-ebv).
///
/// The defect this suite exists for shipped with three tests pinning it, and the reason they
/// pinned it is that each was written about **one cell** — one deck, one presentation, one
/// sentence. So this one is written about the whole table instead: every deck crossed with every
/// nudge sentence, asserted in both directions every time.
///
/// Two rules govern how it is written, both learned from the lens that reported focus-ebv:
///
/// * **there is no `guard … else { return }` anywhere in it.** An exemption inside a property is
///   where the next defect lives: `SurfaceRouterTests` skipped its four broken cells on a guard
///   that tested the very property the four cells got wrong;
/// * **every assertion is a pair.** "Contains the name" alone is satisfiable by a sentence that
///   contains the identifier *as well*, which is exactly what a half-applied fix looks like, so
///   the absence of the key is asserted beside the presence of the name.
@Suite("Every deck names the app, and no deck names its bundle identifier")
@MainActor
struct SubjectSentenceTests {
    /// The subjects. The first three have two halves that are **different strings**, which is
    /// what makes the assertions below non-vacuous — a fixture whose display name equalled its
    /// identifier could not tell a fixed sentence from a broken one. The fourth deliberately has
    /// halves that are equal, because that is a real state of the world and it is asserted about
    /// rather than left out.
    static let subjects = [
        NudgeSubject.named("com.apple.Safari", runningName: "Safari")!,
        NudgeSubject.named("com.figma.Desktop", runningName: "Figma")!,
        NudgeSubject.named("com.microsoft.Word", runningName: "Microsoft Word")!,
        // Not running, or running under no name: the sentence falls back to the identifier, and
        // that cell is included rather than exempted — it is the one case in which a nudge is
        // *allowed* to say a bundle identifier, and it must still say something.
        NudgeSubject.named("com.unnamed.Helper")!
    ]

    @Test(
        "every deck's question names the application and not its key",
        .enabled(if: LocalizationLane.catalogsAreCompiled),
        arguments: NudgeVoice.allCases
    )
    func everyDecksQuestion(voice: NudgeVoice) {
        for subject in Self.subjects {
            let sentence = QueryPresentation(
                voice: voice,
                task: "Write the Q3 proposal",
                subject: subject,
                reason: .noNegativeBasis,
                dwelled: .seconds(90)
            ).announcement()

            #expect(!sentence.isEmpty, "\(voice) drew nothing for \(subject.identifier)")
            #expect(
                sentence.contains(subject.displayName),
                "\(voice) did not name \(subject.displayName): \(sentence)"
            )
            // **An equality, not a skip.** The obvious way to write this is "unless the subject
            // has no name, the key must be absent" — and a conditional inside an assertion is
            // precisely the exemption that let four broken cells pass elsewhere. So the claim is
            // made about every cell: the key appears in the sentence exactly when the key *is*
            // the name, which is the one case a nudge may say a bundle identifier out loud.
            #expect(
                sentence.contains(subject.identifier)
                    == (subject.identifier == subject.displayName),
                "\(voice) said the storage key \(subject.identifier): \(sentence)"
            )
        }
    }

    @Test(
        "every deck's accusation names the application and not its key",
        .enabled(if: LocalizationLane.catalogsAreCompiled),
        arguments: NudgeVoice.allCases
    )
    func everyDecksAccusation(voice: NudgeVoice) {
        for subject in Self.subjects {
            let sentence = AccusationPresentation(
                rung: .panel,
                voice: voice,
                task: "Write the Q3 proposal",
                subject: subject,
                dwelled: .seconds(720),
                returnTarget: "Pages"
            ).announcement()

            #expect(!sentence.isEmpty, "\(voice) drew nothing for \(subject.identifier)")
            #expect(
                sentence.contains(subject.displayName),
                "\(voice) did not name \(subject.displayName): \(sentence)"
            )
            // **An equality, not a skip.** The obvious way to write this is "unless the subject
            // has no name, the key must be absent" — and a conditional inside an assertion is
            // precisely the exemption that let four broken cells pass elsewhere. So the claim is
            // made about every cell: the key appears in the sentence exactly when the key *is*
            // the name, which is the one case a nudge may say a bundle identifier out loud.
            #expect(
                sentence.contains(subject.identifier)
                    == (subject.identifier == subject.displayName),
                "\(voice) said the storage key \(subject.identifier): \(sentence)"
            )
        }
    }

    /// Drift across several applications names nobody, in every deck. The absence is asserted
    /// over both halves, because "names nobody" must not quietly mean "names nobody by name".
    @Test(
        "mixed drift names nobody, in every deck",
        .enabled(if: LocalizationLane.catalogsAreCompiled),
        arguments: NudgeVoice.allCases
    )
    func mixedDriftNamesNobody(voice: NudgeVoice) {
        let sentence = AccusationPresentation(
            rung: .panel,
            voice: voice,
            task: "Write the Q3 proposal",
            subject: nil,
            dwelled: .seconds(900),
            returnTarget: "Pages"
        ).announcement()

        #expect(!sentence.isEmpty)
        for subject in Self.subjects {
            #expect(!sentence.contains(subject.displayName))
            #expect(!sentence.contains(subject.identifier))
        }
    }

    /// The popover's Snoozed row is the fourth surface, and it is not a deck line — it is drawn
    /// verbatim. So the value it draws is asserted directly, and so is the value it is keyed by:
    /// two applications may share a display name, and a list keyed on one would lose a row.
    @Test("a snooze row carries the name to draw and the key to cancel by")
    func snoozeRowsCarryBoth() {
        for subject in Self.subjects {
            let row = MenuBarSnooze(subject: subject, remaining: .seconds(305))
            #expect(row.subject.displayName == subject.displayName)
            // The row is identified by the whole subject, not by either half as a string — an
            // `id` of type `String` is a key a view could draw by mistake.
            #expect(row.id == subject)
            #expect(row.id.identifier == subject.identifier)
        }
        // Two applications, one name: the rows must still be two rows.
        let first = NudgeSubject.named("com.first.Editor", runningName: "Editor")!
        let second = NudgeSubject.named("com.second.Editor", runningName: "Editor")!
        let rows = [
            MenuBarSnooze(subject: first, remaining: .seconds(60)),
            MenuBarSnooze(subject: second, remaining: .seconds(60))
        ]
        #expect(Set(rows.map(\.id)).count == 2)
    }
}
