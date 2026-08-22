import Foundation
import Testing

@testable import FocusCore

/// One committed expectation about one sentence.
///
/// `findings` is an **ordered** array, not a set: the validator emits the shape of the phrase
/// first, then shortness, then the missing outcome, and the surface shows the first one at the
/// top. An order that drifts is a surface whose first line drifts.
struct IntentCase: Sendable {
    let intent: String
    let findings: [IntentFinding.Kind]
    var isWellFormed: Bool { findings.isEmpty }

    init(_ intent: String, _ findings: [IntentFinding.Kind] = []) {
        self.intent = intent
        self.findings = findings
    }
}

/// The committed table. Every row is an assertion about a sentence a person might really
/// type, including the three the Court named.
enum IntentTable {
    static let english = Locale(identifier: "en_US")

    static let cases: [IntentCase] = [
        // --- well formed: a leading imperative and something concrete to do to it ---------
        IntentCase("Finish and submit the Q3 proposal"),
        IntentCase("Write the migration stage for schema v2"),
        IntentCase("Fix the login bug on the settings screen"),
        IntentCase("Review Priya's pull request"),
        IntentCase("Send the invoice to Acme"),
        IntentCase("Draft the release notes for 2.1"),
        IntentCase("Prepare slides for Thursday's review"),
        IntentCase("Migrate the store to schema v2"),
        IntentCase("Refactor the parser into a pure function"),
        IntentCase("Book a dentist appointment"),
        IntentCase("Ship the native shell"),
        IntentCase("Update the README with the new gate stages"),
        IntentCase("Test the migration against the committed fixture"),
        IntentCase("Cancel the unused subscription"),
        IntentCase("Email Dana about the contract"),
        IntentCase("Organise the downloads folder"),
        IntentCase("Debug the flaky snapshot test"),
        IntentCase("Plan next quarter's roadmap"),
        IntentCase("Compare the two bookmark strategies"),
        IntentCase("Record the v2 store fixture"),
        // Case and surrounding whitespace are not content.
        IntentCase("FINISH THE PROPOSAL"),
        IntentCase("  Ship the one thing  "),
        // Punctuation around a word is stripped; punctuation inside it is meaning.
        IntentCase("Fix the bug."),
        IntentCase("Write v2.1 release notes"),

        // --- a topic rather than a task --------------------------------------------------
        // The Court's own example.
        IntentCase("proposal", [.nounOnlyPhrase, .tooShort]),
        IntentCase("spreadsheet", [.nounOnlyPhrase, .tooShort]),
        IntentCase("the budget", [.nounOnlyPhrase]),
        IntentCase("the quarterly report", [.nounOnlyPhrase]),
        IntentCase("a new logo", [.nounOnlyPhrase]),
        IntentCase("an awkward conversation with finance", [.nounOnlyPhrase]),
        IntentCase("x", [.nounOnlyPhrase, .tooShort]),

        // --- something that is not an imperative at the front -----------------------------
        // The Court's own example: a gerund describes a state, it does not name a job.
        IntentCase("working on the proposal", [.noLeadingVerb]),
        IntentCase("writing the release notes", [.noLeadingVerb]),
        IntentCase("running the numbers for Q3", [.noLeadingVerb]),
        IntentCase("thinking about the redesign", [.noLeadingVerb]),
        IntentCase("Priya's pull request", [.noLeadingVerb]),
        IntentCase("quick note about the contract", [.noLeadingVerb]),
        IntentCase("maybe the tax return", [.noLeadingVerb]),

        // --- a verb with nothing attached to it -------------------------------------------
        IntentCase("Fix it", [.noOutcome]),
        IntentCase("Finish this", [.noOutcome]),
        IntentCase("Update it now", [.noOutcome]),
        IntentCase("Send it to them", [.noOutcome]),
        IntentCase("Clean up", [.noOutcome]),
        IntentCase("Do the thing", [.noOutcome]),

        // --- too little to act on ----------------------------------------------------------
        IntentCase("fix", [.tooShort, .noOutcome]),
        IntentCase("Review", [.tooShort, .noOutcome]),
        IntentCase("invoice", [.tooShort, .noOutcome]),
        IntentCase("", [.tooShort]),
        IntentCase("     ", [.tooShort])
    ]
}

@Suite("Intent validation")
struct IntentValidatorTests {
    @Test("the committed table has at least forty rows and no duplicates")
    func tableIsBigEnoughToMeanSomething() {
        #expect(IntentTable.cases.count >= 40)
        let intents = IntentTable.cases.map(\.intent)
        #expect(Set(intents).count == intents.count, "the table repeats a sentence")
    }

    @Test("every row in the committed table", arguments: IntentTable.cases)
    func tableRow(_ testCase: IntentCase) {
        let assessment = IntentValidator.assess(testCase.intent, locale: IntentTable.english)

        if testCase.isWellFormed {
            #expect(
                assessment == .wellFormed,
                "‘\(testCase.intent)’ expected well formed, got \(assessment)"
            )
        } else {
            #expect(
                assessment.findings.map(\.kind) == testCase.findings,
                "‘\(testCase.intent)’ expected \(testCase.findings), got \(assessment.findings.map(\.kind))"
            )
        }
    }

    /// The whole promise of the refinement strip: the suggestion is the user's sentence,
    /// rearranged — never a sentence the app made up. The only word that may appear without
    /// having been typed is the imperative behind a gerund the user themselves wrote.
    @Test("every suggestion is made of the user's own words", arguments: IntentTable.cases)
    func suggestionsUseTheUsersOwnWords(_ testCase: IntentCase) {
        let assessment = IntentValidator.assess(testCase.intent, locale: IntentTable.english)
        guard case .needsWork(let findings) = assessment else { return }

        let typed = Set(IntentValidator.tokenize(testCase.intent).map(\.normalised))
        guard !typed.isEmpty else { return }

        for finding in findings {
            let rewrite = finding.suggestion.rewrite
            #expect(!rewrite.isEmpty, "‘\(testCase.intent)’ produced an empty rewrite")

            for word in IntentValidator.tokenize(rewrite).map(\.normalised) {
                #expect(
                    typed.contains(word) || VerbLexicon.isImperative(word),
                    "the rewrite of ‘\(testCase.intent)’ invented the word ‘\(word)’"
                )
            }

            if let phrase = finding.suggestion.doneWhenPhrase {
                for word in IntentValidator.tokenize(phrase).map(\.normalised) {
                    #expect(
                        typed.contains(word),
                        "the done-when phrase for ‘\(testCase.intent)’ invented ‘\(word)’"
                    )
                }
            }
        }
    }

    @Test("a gerund is rewritten into the imperative behind it")
    func gerundsBecomeImperatives() {
        let assessment = IntentValidator.assess("working on the proposal", locale: IntentTable.english)
        let finding = try? #require(assessment.findings.first)
        #expect(finding?.kind == .noLeadingVerb)
        #expect(finding?.suggestion.kind == .startWithVerb)
        #expect(finding?.suggestion.rewrite == "Work on the proposal")
        #expect(finding?.suggestion.doneWhenPhrase == "the proposal")

        #expect(VerbLexicon.imperativeBehindGerund("working") == "work")
        #expect(VerbLexicon.imperativeBehindGerund("writing") == "write")
        #expect(VerbLexicon.imperativeBehindGerund("running") == "run")
        #expect(VerbLexicon.imperativeBehindGerund("shipping") == "ship")
        // Not every -ing is a gerund the lexicon can undo, and it says so rather than guessing.
        #expect(VerbLexicon.imperativeBehindGerund("nothing") == nil)
        #expect(VerbLexicon.imperativeBehindGerund("thinking") == nil)
        // A short imperative that merely ends in -ing is never mistaken for a gerund.
        #expect(VerbLexicon.imperativeBehindGerund("bring") == nil)
    }

    @Test("a leading article is dropped rather than a verb being invented")
    func articlesAreDropped() {
        let assessment = IntentValidator.assess("the quarterly report", locale: IntentTable.english)
        let finding = try? #require(assessment.findings.first)
        #expect(finding?.kind == .nounOnlyPhrase)
        #expect(finding?.suggestion.rewrite == "Quarterly report")
        #expect(finding?.suggestion.doneWhenPhrase == "quarterly report")
    }

    @Test("a noun-only phrase yields a done-when phrase to pre-fill with")
    func nounOnlyPhraseCarriesADoneWhenPhrase() {
        let assessment = IntentValidator.assess("proposal", locale: IntentTable.english)
        #expect(assessment.findings.map(\.kind) == [.nounOnlyPhrase, .tooShort])
        #expect(assessment.findings.first?.suggestion.doneWhenPhrase == "proposal")
        #expect(assessment.hasSomethingToSay)
    }

    // MARK: - Honestly bounded

    @Test(
        "outside English the validator says nothing at all",
        arguments: ["fr_FR", "de_DE", "ja_JP", "es_ES", "pt_BR", "zh_Hans_CN"]
    )
    func nonEnglishIsNotAssessable(_ identifier: String) {
        let locale = Locale(identifier: identifier)
        #expect(IntentValidator.isAssessable(locale: locale) == false)
        // Even a sentence that is obviously well formed in English gets silence, because the
        // question the validator is being asked is not one it can answer in this locale.
        #expect(
            IntentValidator.assess("Finish and submit the Q3 proposal", locale: locale)
                == .notAssessable
        )
        #expect(IntentValidator.assess("proposition", locale: locale) == .notAssessable)
        #expect(IntentValidator.assess("proposition", locale: locale).hasSomethingToSay == false)
    }

    @Test(
        "every English region is assessable",
        arguments: ["en_US", "en_GB", "en_AU", "en_IE", "en_CA", "en"]
    )
    func everyEnglishRegionIsAssessable(_ identifier: String) {
        let locale = Locale(identifier: identifier)
        #expect(IntentValidator.isAssessable(locale: locale))
        #expect(IntentValidator.assess("Ship the native shell", locale: locale) == .wellFormed)
    }

    @Test("both spellings of the -ise/-ize pairs are imperatives")
    func bothSpellingsAreKnown() {
        for pair in [("organise", "organize"), ("prioritise", "prioritize"), ("finalise", "finalize")] {
            #expect(VerbLexicon.isImperative(pair.0), "\(pair.0) is missing from the lexicon")
            #expect(VerbLexicon.isImperative(pair.1), "\(pair.1) is missing from the lexicon")
        }
        #expect(VerbLexicon.imperatives.count >= 150)
    }

    // MARK: - Purity

    @Test("the validator is a pure function: same input, same output, no clock")
    func validatorIsPure() {
        for testCase in IntentTable.cases {
            let first = IntentValidator.assess(testCase.intent, locale: IntentTable.english)
            let second = IntentValidator.assess(testCase.intent, locale: IntentTable.english)
            let third = IntentValidator.assess(testCase.intent, locale: Locale(identifier: "en_GB"))
            #expect(first == second, "‘\(testCase.intent)’ is not deterministic")
            #expect(first == third, "‘\(testCase.intent)’ depends on the English region")
        }
    }

    @Test("assessing does not mutate the sentence it was given")
    func assessingDoesNotMutateItsInput() {
        let original = "  working on the proposal  "
        _ = IntentValidator.assess(original, locale: IntentTable.english)
        #expect(original == "  working on the proposal  ")
    }
}
