import Foundation
import Testing

@testable import FocusCore

/// Five static decks, thirteen lines each, and no way to generate a sixth (R-90, F-65, F-66,
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

    @Test("there are five decks and thirteen lines, and the matrix is sixty-five keys")
    func theMatrixIsFiveByThirteen() {
        #expect(NudgeVoice.allCases.count == 5)
        #expect(
            Set(NudgeVoice.allCases) == [.neutral, .warm, .direct, .playful, .silentVisual]
        )
        #expect(NudgeCopyKey.allCases.count == 13)
        #expect(NudgeVoice.matrix.count == 65)
        #expect(Set(NudgeVoice.matrix).count == 65, "two decks composed the same key")
        #expect(NudgeVoice.standard == .neutral, "the Court's adopted default deck moved")
    }

    /// **Completeness.** A missing deck entry is an untranslated nudge shipped to somebody at
    /// their most sensitive moment, so every one of the sixty-five is asserted present, with a
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

    /// The Court's adopted default, asserted **by its exact words**, because F-66 chose them
    /// and D-11 makes the copy static precisely so a choice like this can be checked.
    @Test("the default voice says what the Court adopted")
    func theDefaultVoiceIsTheCourts() throws {
        let values = try Self.catalogValues()
        #expect(
            values[NudgeVoice.neutral.key(.accusationPanelTitle)] == "Still working on %@?"
        )
        #expect(values[NudgeVoice.neutral.key(.queryPanelTitle)] == "Is %@ part of %@?")
        #expect(values[NudgeVoice.neutral.key(.queryActionYes)] == "Yes, add it")
        #expect(values[NudgeVoice.neutral.key(.queryActionNo)] == "No")
        #expect(values[NudgeVoice.neutral.key(.queryActionNotNow)] == "Not now")
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
        #expect(queryLines.count == 5, "the question grew or lost a line")

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

    /// `silentVisual` is a **routing** deck, not a copy deck: it maps the panel rung onto the
    /// ambient one and puts the question in the popover. It still carries every line, because
    /// a badge with no words is not an accessible surface.
    @Test("silentVisual reroutes rather than falling silent")
    func silentVisualReroutes() {
        #expect(NudgeVoice.silentVisual.isRoutingDeck)
        #expect(NudgeVoice.silentVisual.renderedRung(for: .panel) == .ambient)
        #expect(NudgeVoice.silentVisual.renderedRung(for: .ambient) == .ambient)
        #expect(NudgeVoice.silentVisual.querySurface == .popoverBadge)

        for voice in NudgeVoice.allCases where voice != .silentVisual {
            #expect(!voice.isRoutingDeck)
            #expect(voice.querySurface == .panel)
            for rung in LadderRung.Kind.allCases {
                #expect(
                    voice.renderedRung(for: rung) == rung,
                    "\(voice.rawValue) is a copy deck and must not reroute a rung"
                )
            }
        }
    }

    /// A rendering choice, never a ladder change: the rung a voice *renders* is never above the
    /// rung the ladder asked for, so no deck can escalate on the ladder's behalf.
    @Test("no voice renders a rung higher than the one it was given")
    func noVoiceEscalates() {
        for voice in NudgeVoice.allCases {
            for rung in LadderRung.Kind.allCases {
                #expect(voice.renderedRung(for: rung).rank <= rung.rank)
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
