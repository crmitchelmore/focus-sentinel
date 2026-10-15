import Foundation
import Testing

@testable import FocusCore

/// Four static decks, sixteen lines each, and no generated copy (R-90, F-65, F-66,
/// D-11, SC-4).
@Suite("Nudge voices")
struct NudgeVoiceTests {
    /// The committed catalog, read as JSON. The lane-gated resolution tests below prove the
    /// *compiled* catalog answers; this reads the **source of truth** so that a missing entry
    /// fails in the inner loop too, where a developer will actually see it.
    static func catalogValues() throws -> [String: String] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()          // FocusCoreTests
            .deletingLastPathComponent()          // Tests
            .deletingLastPathComponent()          // FocusCore (package)
            .appending(path: "Sources/FocusCore/Resources/Localizable.xcstrings")
        let document = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
        let strings = try #require((document as? [String: Any])?["strings"] as? [String: Any])

        var values: [String: String] = [:]
        for (key, entry) in strings {
            guard let entry = entry as? [String: Any],
                  let localizations = entry["localizations"] as? [String: Any],
                  let english = localizations["en"] as? [String: Any],
                  let unit = english["stringUnit"] as? [String: Any],
                  let value = unit["value"] as? String
            else { continue }
            values[key] = value
        }
        return values
    }

    @Test("there are four decks and sixteen lines, and the matrix is sixty-four keys")
    func theMatrixIsFiveByThirteen() {
        #expect(NudgeVoice.allCases.count == 4)
        #expect(
            Set(NudgeVoice.allCases) == [.neutral, .warm, .direct, .silentVisual],
            "`playful` is retired by the ruling on focus-0nm; a fifth deck is a new ruling"
        )
        #expect(NudgeCopyKey.allCases.count == 16)
        #expect(NudgeVoice.matrix.count == 64)
        #expect(Set(NudgeVoice.matrix).count == 64, "two decks composed the same key")
        #expect(NudgeVoice.standard == .neutral, "the Court's adopted default deck moved")
    }

    /// **Completeness.** A missing deck entry is an untranslated nudge shipped to somebody at
    /// their most sensitive moment, so every one of the sixty-four is asserted present, with a
    /// non-empty English value, in the committed catalog.
    @Test("every deck has every line, in the committed catalog")
    func everyDeckHasEveryLine() throws {
        let values = try Self.catalogValues()
        for voice in NudgeVoice.allCases {
            for line in NudgeCopyKey.allCases {
                let key = voice.key(line)
                let value = values[key]
                #expect(value != nil, "the catalog has no entry for \(key)")
                #expect(!(value ?? "").isEmpty, "\(key) has an empty English value")
            }
        }
    }

    /// **No key resolves to its own name.** A key with no value resolves to the key at runtime,
    /// which is the silent failure the whole localisation lane exists to catch.
    @Test("no deck line's value is its own key")
    func noLineIsItsOwnKey() throws {
        let values = try Self.catalogValues()
        for key in NudgeVoice.matrix {
            #expect(values[key] != key, "\(key) resolves to its own name")
        }
    }

    /// **No deck string carries a format specifier the code does not supply**, and none omits
    /// one it does. A translator who drops a `%@` and a deck that invents one are the same bug
    /// with two different symptoms, and both crash a person's nudge rather than a test.
    @Test("every deck line carries exactly the specifiers its key declares")
    func specifiersMatchTheDeclaredSlots() throws {
        let values = try Self.catalogValues()
        for voice in NudgeVoice.allCases {
            for line in NudgeCopyKey.allCases {
                let key = voice.key(line)
                let value = try #require(values[key])
                let specifiers = Self.specifierCount(in: value)
                #expect(
                    specifiers == line.slots.count,
                    "\(key) has \(specifiers) specifier(s) but declares \(line.slots.count)"
                )
                // Only `%@` is permitted: a `%d`, a `%f` or a `%1$s` would be the app formatting
                // a number for somebody, and every number a nudge shows is rendered by the UI
                // from a typed value first.
                #expect(
                    !Self.hasForeignSpecifier(value),
                    "\(key) carries a format specifier that is not %@: \(value)"
                )
            }
        }
    }

    /// The default deck, asserted **by its exact words**, because D-11 makes the copy static
    /// precisely so a choice like this can be checked.
    ///
    /// **F-66's accusation title is gone, and that is a ruling rather than a drift**
    /// (focus-0nm). "Still working on %@?" was an accusation wearing a question mark: the app
    /// protects one question mark, the real question, and a person who has learned that it
    /// means "Focus needs a rule" must never be shown one that means "you have drifted". R-96v
    /// now fails the gate on it. The question still asks about app membership; the owner-requested
    /// plain-language edit keeps that distinction.
    @Test("the default voice retains the owner requested plain wording")
    func theDefaultVoiceUsesPlainWording() throws {
        let values = try Self.catalogValues()
        let title = values[NudgeVoice.neutral.key(.accusationPanelTitle)]
        #expect(title == "\"%@\" is the current priority.")
        #expect(
            title?.hasSuffix("?") == false,
            "the accusation is a statement; only the question asks (R-96v)"
        )
        #expect(values[NudgeVoice.neutral.key(.queryPanelTitle)] == "Is %@ part of %@?")
        #expect(values[NudgeVoice.neutral.key(.queryActionYes)] == "Yes, add it")
        #expect(values[NudgeVoice.neutral.key(.queryActionNo)] == "No, it isn't")
        #expect(values[NudgeVoice.neutral.key(.queryActionNotNow)] == "Ask later")
    }

    /// **The person is never the grammatical subject** (R-96t, focus-0nm).
    ///
    /// The single most load-bearing rule in e11's direction, and the one the shipped default
    /// deck broke: `nudge.neutral.accusation.panel.body` read "You've been in %@ for %@." — a
    /// report on the person rather than on the screen. An instrument names what is in front of
    /// it and holds no opinion about whoever is reading it. `check-forbidden.sh` runs the same
    /// fold over the committed catalog as a gate stage; this runs it here so a deck author sees
    /// it before the gate does.
    ///
    /// Both apostrophes, because the catalog ships the typographic one and a check that only
    /// knew the ASCII form would have been green on the very line it was written for.
    @Test("the person is never the grammatical subject of a line the app says")
    func noDeckLineMakesThePersonTheSubject() throws {
        let values = try Self.catalogValues()
        let secondPerson = [
            "you", "you'", "your", "yours", "yourself",
        ]

        var checked = 0
        for voice in NudgeVoice.allCases {
            for line in NudgeCopyKey.allCases {
                let key = voice.key(line)
                let value = try #require(values[key])
                    .replacingOccurrences(of: "\u{2019}", with: "'")
                    .lowercased()
                checked += 1
                let words = value.split(whereSeparator: { !$0.isLetter && $0 != "'" })
                for word in words {
                    #expect(
                        !secondPerson.contains(String(word)),
                        "\(key) makes the person the subject: \(value)"
                    )
                }
            }
        }
        #expect(checked == NudgeVoice.matrix.count, "the fold stopped covering the matrix")
    }

    /// **Grammar is the channel** (R-96v, focus-0nm).
    ///
    /// The accusation is a statement; the question is a question. This is the sharpest available
    /// operationalisation of "a question is never an accusation", a rule this repository has held
    /// in prose since F-65 and could not check. It was red on three of the four decks.
    @Test("an accusation never wears a question mark, and a question always asks")
    func grammarIsTheChannel() throws {
        let values = try Self.catalogValues()
        for voice in NudgeVoice.allCases {
            let accusation = try #require(values[voice.key(.accusationPanelTitle)])
            let question = try #require(values[voice.key(.queryPanelTitle)])
            #expect(
                !accusation.hasSuffix("?"),
                "\(voice.rawValue)'s accusation wears a question mark: \(accusation)"
            )
            #expect(
                question.hasSuffix("?"),
                "\(voice.rawValue)'s question does not ask: \(question)"
            )
        }
    }

    /// **The question never accuses.** A small, blunt word list, deliberately blunt, because
    /// tone is the product. `check-strings.sh` runs the same assertion over the catalog as a
    /// gate stage (R-96f); this runs it here so a deck author sees it immediately.
    @Test("no line under a query key accuses anybody")
    func noQueryLineAccuses() throws {
        let values = try Self.catalogValues()
        let accusatory = [
            "distract", "off task", "off-task", "wasting", "waste of", "procrastinat",
            "you should", "you shouldn", "stop ", "slacking", "goofing", "avoiding",
            "supposed to", "not working"
        ]

        let queryLines = NudgeCopyKey.allCases.filter(\.isQueryLine)
        #expect(queryLines.count == 8, "the question grew or lost a line")

        for voice in NudgeVoice.allCases {
            for line in queryLines {
                let key = voice.key(line)
                let value = try #require(values[key]).lowercased()
                for word in accusatory {
                    #expect(
                        !value.contains(word),
                        "\(key) contains the accusatory phrase \"\(word)\": \(value)"
                    )
                }
            }
        }
    }

    /// The three actions and no more. U-1's affordance is one question whose cheapest answer
    /// teaches the app — a fourth button would be a fourth thing to think about.
    @Test("the question has exactly three actions in every deck")
    func theQuestionHasThreeActions() {
        let actions: Set<NudgeCopyKey> = [.queryActionYes, .queryActionNo, .queryActionNotNow]
        #expect(
            Set(NudgeCopyKey.allCases.filter { $0.isQueryLine && $0.rawValue.contains("action") })
                == actions
        )
    }

    // MARK: - The routing deck

    /// `silentVisual` is a **routing** deck, not a copy deck: it puts the top rung and the
    /// question alike in the menu-bar popover. It still carries every line, because a badge with
    /// no words is not an accessible surface.
    ///
    /// **A deck says how quiet, never which rung** (focus-vxo). `renderedRung(for:)` used to say
    /// the second thing — under this deck the panel rung "was" the ambient rung — and it was
    /// false in the loop, which climbed to the panel rung, recorded it delivered against a named
    /// application, spent the accusation budget on it and drew the panel rung's own label in the
    /// popover. The function is deleted, so no deck has a way to say it: the router is handed
    /// the rung the ladder set, and `isRoutingDeck` is the deck's whole say in where it lands.
    @Test("the routing deck reroutes the surface, and no deck reroutes the rung")
    func silentVisualReroutes() {
        #expect(NudgeVoice.silentVisual.isRoutingDeck)
        #expect(NudgeVoice.silentVisual.querySurface == .popoverBadge)

        for voice in NudgeVoice.allCases where voice != .silentVisual {
            #expect(!voice.isRoutingDeck)
            #expect(voice.querySurface == .panel)
        }

        // **What a deck may not do, over every deck.** The glyph is the ambient rung's only
        // surface and the top rung never lands on it: the ambient rung is what a glyph means,
        // and a deck that sent the panel rung there would be re-labelling a rung the ladder has
        // already climbed, recorded and charged for. That is the defect focus-vxo closed, and
        // this is it stated as a rule rather than as the one deck it was true of.
        for voice in NudgeVoice.allCases {
            let ambient = SurfaceRouter.route(
                rung: .ambient,
                presentation: .notPresenting,
                media: .idle,
                reducedInterruption: false,
                menuBarVisible: true,
                voice: voice
            )
            let panel = SurfaceRouter.route(
                rung: .panel,
                presentation: .notPresenting,
                media: .idle,
                reducedInterruption: false,
                menuBarVisible: true,
                voice: voice
            )
            #expect(ambient.surface == .menuBar, "\(voice.rawValue) moved the glyph")
            #expect(panel.surface != .menuBar, "\(voice.rawValue) put the top rung on the glyph")
        }
    }

    /// A deck chooses a quieter surface, never a louder one, and never a different rung: for
    /// every deck and every rung the router is asked for the rung it was given, and the surface
    /// it answers is never louder than the standard deck's.
    @Test("no deck routes a rung anywhere louder than the standard deck does")
    func noVoiceEscalates() {
        for voice in NudgeVoice.allCases {
            for rung in LadderRung.Kind.allCases {
                let standard = SurfaceRouter.route(
                    rung: rung,
                    presentation: .notPresenting,
                    media: .idle,
                    reducedInterruption: false,
                    menuBarVisible: true,
                    voice: .standard
                )
                let deck = SurfaceRouter.route(
                    rung: rung,
                    presentation: .notPresenting,
                    media: .idle,
                    reducedInterruption: false,
                    menuBarVisible: true,
                    voice: voice
                )
                // "Louder" is `holdsTheInterruptionSlot`: a deck may take a rung off the screen
                // and may never put one there the standard deck would not have.
                let standardHolds = standard.surface?.holdsTheInterruptionSlot ?? false
                let deckHolds = deck.surface?.holdsTheInterruptionSlot ?? false
                #expect(!deckHolds || standardHolds, "\(voice.rawValue) escalated \(rung.rawValue)")
            }
        }
    }

    // MARK: - Keys and resources

    @Test("a deck key is nudge dot deck dot situation, and nothing else")
    func keyShape() {
        for voice in NudgeVoice.allCases {
            for line in NudgeCopyKey.allCases {
                #expect(voice.key(line) == "nudge.\(voice.rawValue).\(line.rawValue)")
                #expect(voice.key(line).hasPrefix("\(NudgeVoice.keyPrefix)."))
            }
        }
    }

    @Test(
        "no deck line resolves to its own key at runtime",
        .enabled(if: LocalizationLane.catalogsAreCompiled)
    )
    func linesResolve() {
        for voice in NudgeVoice.allCases {
            for line in NudgeCopyKey.allCases {
                let rendered = String(localized: voice.resource(line))
                #expect(rendered != voice.key(line), "\(voice.key(line)) resolved to its own name")
                #expect(!rendered.isEmpty)
            }
        }
    }

    @Test("the deck vocabularies round-trip through Codable on their raw values")
    func codableRoundTrip() throws {
        for voice in NudgeVoice.allCases {
            let data = try JSONEncoder().encode(voice)
            #expect(try JSONDecoder().decode(NudgeVoice.self, from: data) == voice)
        }
        for line in NudgeCopyKey.allCases {
            let data = try JSONEncoder().encode(line)
            #expect(try JSONDecoder().decode(NudgeCopyKey.self, from: data) == line)
        }
        for slot in NudgeCopySlot.allCases {
            let data = try JSONEncoder().encode(slot)
            #expect(try JSONDecoder().decode(NudgeCopySlot.self, from: data) == slot)
        }
    }

    // MARK: - Helpers

    /// `%@` occurrences, positional (`%1$@`) included, `%%` excluded.
    static func specifierCount(in value: String) -> Int {
        var count = 0
        var characters = Array(value)
        var index = 0
        while index < characters.count {
            guard characters[index] == "%" else {
                index += 1
                continue
            }
            var cursor = index + 1
            if cursor < characters.count, characters[cursor] == "%" {
                index = cursor + 1                                   // an escaped per-cent
                continue
            }
            while cursor < characters.count, characters[cursor].isNumber || characters[cursor] == "$" {
                cursor += 1
            }
            if cursor < characters.count, characters[cursor] == "@" { count += 1 }
            index = cursor + 1
        }
        return count
    }

    /// Whether the value carries a specifier that is not `%@` — a `%d`, a `%f`, a `%s`.
    static func hasForeignSpecifier(_ value: String) -> Bool {
        let characters = Array(value)
        var index = 0
        while index < characters.count {
            guard characters[index] == "%" else {
                index += 1
                continue
            }
            var cursor = index + 1
            if cursor < characters.count, characters[cursor] == "%" {
                index = cursor + 1
                continue
            }
            while cursor < characters.count,
                  characters[cursor].isNumber || characters[cursor] == "$" {
                cursor += 1
            }
            guard cursor < characters.count else { return true }
            if characters[cursor] != "@" { return true }
            index = cursor + 1
        }
        return false
    }
}
