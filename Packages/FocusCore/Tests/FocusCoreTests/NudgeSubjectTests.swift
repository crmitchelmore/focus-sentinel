import Foundation
import Testing

@testable import FocusCore

/// **The sentence names the app; the rule stays keyed on the identifier** (focus-ebv).
///
/// The defect this suite is written against shipped on four user-visible surfaces and had three
/// tests *pinning* it, so the assertions here are deliberately made over the whole input space
/// rather than over the case that was reported: every shape an identifier arrives in, crossed
/// with every shape a name arrives in, with the two halves checked separately every time.
@Suite("A nudge subject has a key and a name, and they are not the same thing")
struct NudgeSubjectTests {
    /// An explanation that names nothing, so `QuerySubject.derive(…)` falls to the judged
    /// activation — the `noNegativeBasis` shape, which is 32 of the corpus's 72 uncertain
    /// verdicts (P-138) and therefore the ordinary case rather than an edge one.
    static func explanation() -> Explanation {
        Explanation.make(
            stage: .heuristic,
            band: .low,
            clauses: [.insufficientEvidence(reason: .noNegativeBasis)],
            stamp: .current
        )
    }

    /// Every shape an identifier can arrive in, and what each one means.
    static let identifiers = [
        "com.apple.Safari",
        "com.figma.Desktop",
        "https://docs.google.com",
        "https://example.com:8443"
    ]

    /// Every shape a looked-up name can arrive in. Three of the five are absences.
    static let names: [String?] = [nil, "", "   ", "Safari", " Safari "]

    // MARK: - The two halves, and the fact that they are two

    @Test("the identifier half is the key it was handed, trimmed and never touched otherwise")
    func identifierIsTheKey() throws {
        for identifier in Self.identifiers {
            for name in Self.names {
                let subject = try #require(NudgeSubject.named(identifier, runningName: name))
                #expect(
                    subject.identifier == identifier,
                    "\(identifier) with name \(name ?? "nil") lost its key"
                )
            }
        }
    }

    @Test("a running application's own name is what the sentence says")
    func nameWins() throws {
        let subject = try #require(
            NudgeSubject.named("com.apple.Safari", runningName: "Safari")
        )
        #expect(subject.displayName == "Safari")
        // The whole of focus-ebv in one line: the two halves differ, and the sentence takes the
        // one a person recognises.
        #expect(subject.identifier == "com.apple.Safari")
        #expect(subject.displayName != subject.identifier)
    }

    @Test("a name arrives trimmed, because a leading space is a layout defect in a headline")
    func nameIsTrimmed() throws {
        let subject = try #require(
            NudgeSubject.named("com.apple.Safari", runningName: " Safari ")
        )
        #expect(subject.displayName == "Safari")
    }

    // MARK: - Never an empty sentence

    /// The ruling the bead asked for out loud: an app that is gone, or running under no name at
    /// all, renders its identifier. Ugly, honest, and answerable — which an empty headline is
    /// not.
    @Test("with no name to be had, the sentence falls back to the identifier and never to nothing")
    func fallsBackToTheIdentifier() throws {
        for name in [nil, "", "   ", "\n\t "] as [String?] {
            let subject = try #require(
                NudgeSubject.named("com.figma.Desktop", runningName: name)
            )
            #expect(subject.displayName == "com.figma.Desktop")
        }
    }

    @Test("no reachable subject renders an empty sentence, over the whole input space")
    func neverEmpty() throws {
        for identifier in Self.identifiers {
            for name in Self.names {
                let subject = try #require(NudgeSubject.named(identifier, runningName: name))
                #expect(
                    !subject.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    "\(identifier) with name \(name ?? "nil") rendered an empty sentence"
                )
                #expect(!subject.identifier.isEmpty)
            }
        }
    }

    // MARK: - Nobody to name

    /// e04's mixed mandate carries `""`, and a nudge over drift that named nobody must go on
    /// naming nobody. All three absences answer the same way.
    @Test("an absent identifier names nobody rather than being invented")
    func absentIdentifierIsNil() {
        for identifier in [nil, "", "   ", "\n"] as [String?] {
            #expect(NudgeSubject.named(identifier, runningName: "Safari") == nil)
        }
    }

    // MARK: - An origin is derived, never looked up

    /// The chip row draws *"docs.google.com"* for this origin (`ContextItemValue`), and before
    /// this type the nudge beside it drew the scheme too. One function decides it now.
    @Test("an origin's sentence is its host, the same word the context chip draws")
    func originsRenderTheirHost() throws {
        let plain = try #require(NudgeSubject.named("https://docs.google.com"))
        #expect(plain.displayName == "docs.google.com")
        #expect(plain.identifier == "https://docs.google.com")

        let ported = try #require(NudgeSubject.named("https://example.com:8443"))
        #expect(ported.displayName == "example.com:8443")
    }

    /// An origin has no application to have a localised name, so a name handed in beside one is
    /// evidence about something else and is not allowed to rename a site.
    @Test("an origin ignores a localised name, because no application owns it")
    func originsIgnoreALookedUpName() throws {
        let subject = try #require(
            NudgeSubject.named("https://docs.google.com", runningName: "Safari")
        )
        #expect(subject.displayName == "docs.google.com")
    }

    @Test("the origin discriminator is the one QuerySubject decides .domain by")
    func oneDiscriminator() throws {
        for identifier in Self.identifiers {
            let subject = try #require(
                QuerySubject.derive(judgedSubject: identifier, explanation: Self.explanation())
            )
            #expect((subject.kind == .domain) == NudgeSubject.isOrigin(identifier))
        }
    }

    // MARK: - The total route, for the type that guarantees a nameable identifier

    @Test("a query subject is always nameable, so of(_:) needs no failure case")
    func ofAQuerySubjectIsTotal() throws {
        let query = try #require(
            QuerySubject.derive(
                judgedSubject: "  com.apple.Safari  ",
                explanation: Self.explanation()
            )
        )
        #expect(NudgeSubject.of(query, runningName: "Safari").displayName == "Safari")
        #expect(NudgeSubject.of(query, runningName: nil).displayName == "com.apple.Safari")
        #expect(NudgeSubject.of(query).identifier == "com.apple.Safari")
    }

    // MARK: - Value semantics

    /// Two subjects are the same subject when both halves agree. Not identifier alone: a rung
    /// raised before an application was named and one raised after are the same *rule* and a
    /// different *sentence*, and a surface that treated them as equal would not redraw.
    @Test("equality is over both halves")
    func equalityIsOverBothHalves() throws {
        let named = try #require(NudgeSubject.named("com.apple.Safari", runningName: "Safari"))
        let bare = try #require(NudgeSubject.named("com.apple.Safari"))
        #expect(named != bare)
        #expect(named == NudgeSubject.named("com.apple.Safari", runningName: "Safari"))
    }

    @Test("the description is the name, because that is the half a person reads")
    func descriptionIsTheName() throws {
        let subject = try #require(NudgeSubject.named("com.apple.Safari", runningName: "Safari"))
        #expect(subject.description == "Safari")
        #expect("\(subject)" == "Safari")
    }
}
