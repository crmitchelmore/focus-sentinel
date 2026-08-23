import FocusCore
import FocusEvaluateCore
import Foundation
import Testing

@testable import FocusClassify

/// **R-74.1 — a constant is not committed until a fixture would fail if it moved.**
///
/// R-59 makes every threshold named, digested and versioned. That is a mechanism against
/// *silent change* and it is **not** evidence that the value is right: the digest test fails
/// when a number moves and says nothing about whether the number should have been that number
/// in the first place. Several constants arrived by narrative — *"past five minutes a person is
/// not glancing"* — and a narrative cannot fail. This suite is what can.
///
/// ## How a mutation is actually performed, and why it is not performed literally
///
/// The plan describes this suite as re-running the corpus "against a mutated `RelevancePolicy`",
/// on the stated premise that *"the policy is a value, so this costs nothing but a second
/// construction"*. **That premise is false against the shipped code**, and it was checked rather
/// than assumed: `RelevancePolicy` is an enum of `static let`s, deliberately so — R-59's whole
/// point is that the constant set is immutable, digested and impossible to vary at runtime, and
/// R-70f's lint forbids a numeric literal anywhere that could shadow one. Making the policy a
/// value threaded through the engine would mean rewriting Phase A, Phase B's lint and every
/// signature in Phase C, in order to test them.
///
/// So the mutation is performed on the **input** instead, which for a threshold is the same
/// experiment. Every constant here enters the engine through exactly one comparison of the form
/// `measurement ⋈ constant`. Moving the constant by δ and holding the measurement still is
/// therefore indistinguishable, at that comparison, from moving the measurement by −δ and
/// holding the constant still — and the corpus already contains the moved measurement, because
/// R-74.1 also requires a committed boundary triple. Each row below names the **witness**, the
/// **sibling** that sits where the witness would sit under the mutated constant, and the
/// observable that must differ between them.
///
/// What this buys is a real gate rather than a restatement. If somebody changes the engine so
/// that a boundary stops mattering — a band that no longer depends on token length, a negative
/// basis that no longer gates the accusation — the witness and its sibling stop differing and
/// this suite goes red, by name, saying which constant the corpus has stopped testing.
///
/// What it does not buy is a proof that the *only* thing the constant does is that comparison.
/// That is what the equivalence argument in each row is for, and it is prose a reviewer reads.
@Suite("Mutation witnesses")
struct MutationWitnessTests {
    /// What must differ between a witness and its sibling.
    enum Observable: String {
        case verdict
        case band
        case eligibility
        case uncertaintyReason
        case explanationTokens
        case drift
        case accumulated
        case mandateCount
    }

    /// Where the two halves of the experiment live.
    enum Subjects {
        /// Two single-shot corpus cases.
        case cases(witness: String, sibling: String)
        /// Two steps of one sequence, straddling the boundary inside a single transcript.
        case steps(sequence: String, below: Int, above: Int)
        /// Two whole sequences, compared on their mandate counts.
        case sequences(witness: String, sibling: String)
    }

    struct Row {
        let constant: String
        /// The committed alternative that flips the witness. Must be one of the constant's own
        /// `mutations` in `RelevancePolicy.manifest`.
        let mutation: String
        let subjects: Subjects
        let observable: Observable
        /// Why the sibling under the committed constant is the same experiment as the witness
        /// under the mutated one. Reviewed by a person; the assertions below check the rest.
        let argument: String
    }

    /// One row per **B** constant. A constant missing from this table fails the completeness
    /// assertion below, which is what makes the table total rather than a selection.
    static let rows: [Row] = [
        Row(
            constant: "minimumTokenLength",
            mutation: "4",
            subjects: .cases(witness: "gc-0201", sibling: "gc-0200"),
            observable: .verdict,
            argument: """
            The filter drops a token shorter than the constant. gc-0201's only shared token is \
            three characters and survives at 3; gc-0200's is two and does not. Raising the \
            constant to 4 leaves gc-0201's token one character short of the filter, which is \
            exactly where gc-0200's already is.
            """
        ),
        Row(
            constant: "minimumStrongTokenLength",
            mutation: "5",
            subjects: .cases(witness: "gc-0202", sibling: "gc-0201"),
            observable: .band,
            argument: """
            An overlap bands medium when some shared token reaches this length and low \
            otherwise. gc-0202's token is four characters and gc-0201's is three. At 5, \
            gc-0202's token falls short by one, which is where gc-0201's token is at 4.
            """
        ),
        Row(
            constant: "minimumOverlapTokens",
            mutation: "2",
            subjects: .cases(witness: "gc-0203", sibling: "gc-0210"),
            observable: .verdict,
            argument: """
            The overlap route fires when the shared-token count reaches the constant. gc-0203 \
            shares exactly one token and gc-0210 shares none. Requiring two leaves gc-0203 one \
            short, which is where gc-0210 already is at one.
            """
        ),
        Row(
            constant: "minimumPriorityContentTokens",
            mutation: "3",
            subjects: .cases(witness: "gc-0204", sibling: "gc-0212"),
            observable: .uncertaintyReason,
            argument: """
            A priority is judgeable when its content-token count reaches the constant. gc-0204 \
            carries exactly two and gc-0212 exactly one. At 3, gc-0204 is one short, which is \
            where gc-0212 is at 2 — and the decline moves from noNegativeBasis to \
            insufficientPriorityEvidence, one step earlier in the rung.
            """
        ),
        Row(
            constant: "minimumNegativeBasisItems",
            mutation: "0",
            subjects: .cases(witness: "gc-0301", sibling: "gc-0315"),
            observable: .eligibility,
            argument: """
            **The strongest witness in the epic.** The accusation route requires the context \
            pack to hold at least this many app-or-domain identities that the observed subject \
            does not match. gc-0301 holds none and gc-0315 holds one, and they are otherwise the \
            same case: the same priority, the same Excel, the same ninety-one seconds. At 0 the \
            requirement is satisfied vacuously, so gc-0301 proceeds exactly as gc-0315 does — \
            unrelated at band medium, which is the intervention floor, which MANDATES. The \
            corpus therefore demonstrably reintroduces R-56.1's false accusation the moment the \
            guard is removed, which is the whole reason that ruling exists.
            """
        ),
        Row(
            constant: "maximumExplanationTokens",
            mutation: "2",
            subjects: .cases(witness: "gc-0205", sibling: "gc-0214"),
            observable: .explanationTokens,
            argument: """
            The clause is capped at this many tokens. gc-0205 overlaps on four and reports \
            three; gc-0214 overlaps on two and reports two. At 2, gc-0205 reports two, which is \
            what gc-0214 already reports. Note that the clause KIND is identical in both — this \
            constant is invisible to a corpus that asserts only clause kinds, which is why the \
            case schema carries an explanation-token count at all.
            """
        ),
        Row(
            constant: "similarityRelevantCeiling",
            mutation: "0.96",
            subjects: .cases(witness: "gc-0206", sibling: "gc-0217"),
            observable: .verdict,
            argument: """
            Similarity corroborates when the measured distance is at or below the ceiling. \
            P-124 scored gc-0206's pair at 0.9672 and gc-0217's at 0.9752, and the committed \
            ceiling of 0.97 sits between them with no measurement in the gap. Lowering it to \
            0.96 puts gc-0206 outside, which is where gc-0217 already is.
            """
        ),
        Row(
            constant: "languageConfidenceFloor",
            mutation: "0.90",
            subjects: .cases(witness: "gc-0207", sibling: "gc-0218"),
            observable: .verdict,
            argument: """
            The similarity signal runs only when both sides reach this English confidence. \
            gc-0207's priority scores 0.8678 and gc-0218's 0.7618, against identical evidence \
            and with both distances well inside the ceiling — the language gate is the only \
            thing separating them. Raising the floor to 0.90 puts gc-0207 below it, which is \
            where gc-0218 already is at 0.84.
            """
        ),
        Row(
            constant: "sustainedDriftThreshold",
            mutation: "120s",
            subjects: .steps(sequence: "seq-0003", below: 2, above: 3),
            observable: .drift,
            argument: """
            Drift becomes sustained at the first observation whose accumulator exceeds the \
            threshold. seq-0003 walks the boundary a second at a time: step 2 stands at ninety \
            seconds and remains in grace, step 3 stands at ninety-one and sustains. Raising the \
            threshold to a hundred and twenty puts step 3 where step 2 is — and the whole \
            fixture's single mandate disappears.
            """
        ),
        Row(
            constant: "driftResetGrace",
            mutation: "5s",
            subjects: .steps(sequence: "seq-0005", below: 6, above: 3),
            observable: .accumulated,
            argument: """
            A return clears the accumulator only once it has been HELD for this long. \
            seq-0005 contains both legs: a twenty-two second return resets the count to zero, \
            and a nineteen second one leaves sixty-one seconds standing. Dropping the constant \
            to five seconds makes the nineteen-second return behave like the twenty-two second \
            one — and the fixture's mandate, which that preserved accumulator earns, never \
            arrives. This is the anti-defeat property: without it, alt-tabbing back for a second \
            a minute mutes the app for ever.
            """
        ),
        Row(
            constant: "escalationDwell",
            mutation: "360s",
            subjects: .steps(sequence: "seq-0006", below: 1, above: 2),
            observable: .band,
            argument: """
            The band rises from medium to high once dwell passes this constant. seq-0006 holds \
            one subject either side of it — two hundred and ninety-nine seconds bands medium, \
            three hundred and one bands high. Raising it to three hundred and sixty puts the \
            second step where the first is.
            """
        ),
        Row(
            constant: "mandateCooldown",
            mutation: "900s",
            subjects: .steps(sequence: "seq-0007", below: 2, above: 3),
            observable: .drift,
            argument: """
            A cooldown ends when the clock passes the mandate instant plus this constant. \
            seq-0007 observes at five hundred and ninety-nine seconds, still in cooldown, and \
            again at six hundred and one, which begins a fresh grace period. Raising it to nine \
            hundred puts the later step where the earlier one is, and the fixture's second \
            mandate never happens.
            """
        ),
        Row(
            constant: "lookBackSpan",
            mutation: "360s",
            subjects: .steps(sequence: "seq-0008", below: 3, above: 4),
            observable: .drift,
            argument: """
            The window keeps observations newer than this span, and an anchor inside it extends \
            the effective threshold. seq-0008 shows the anchor in the window at step 3, where \
            a hundred and eighty seconds of drift stays in grace against the extended threshold, \
            and aged out at step 4, where the threshold has reverted to ninety and the very next \
            observation crosses it. Widening the span to three hundred and sixty keeps the \
            anchor alive and puts step 4 where step 3 is.
            """
        ),
        Row(
            constant: "returnAnchorDwell",
            mutation: "15s",
            subjects: .sequences(witness: "seq-0009", sibling: "seq-0011"),
            observable: .mandateCount,
            argument: """
            A relevant subject counts as an anchor once it has held for this long. seq-0009's \
            held for twenty-nine seconds and does not qualify, so the threshold stays at ninety \
            and ninety-one seconds of detour mandates; seq-0011's held for thirty and does, so \
            the threshold becomes a hundred and eighty and the identical detour says nothing. \
            Lowering the constant to fifteen makes seq-0009 into seq-0011.
            """
        ),
        Row(
            constant: "detourExtension",
            mutation: "45s",
            subjects: .sequences(witness: "seq-0010", sibling: "seq-0009"),
            observable: .mandateCount,
            argument: """
            An anchored detour's threshold is the sustained-drift threshold plus this constant. \
            seq-0010's drift reaches a hundred and fifty seconds against an effective threshold \
            of a hundred and eighty and stays silent; seq-0009's reaches ninety-one against \
            ninety and mandates. Cutting the extension to forty-five gives seq-0010 a threshold \
            of a hundred and thirty-five, which its hundred and fifty seconds exceeds — it \
            becomes seq-0009, and D-05's own worked example starts producing the false nudge the \
            ruling was written to prevent.
            """
        )
    ]

    // MARK: - The table is total over the B constants

    /// A B constant with no row is a constant this suite does not test, whatever the manifest
    /// claims about it. R-59's class column is only load-bearing if this is asserted.
    @Test("every behavioural constant has a witness row")
    func theTableIsTotal() {
        let behavioural = RelevancePolicy.manifest
            .filter { $0.kind == .behavioural }
            .map(\.name)
        let covered = Self.rows.map(\.constant)

        for constant in behavioural {
            #expect(covered.contains(constant), "\(constant) is class B and has no witness row")
        }
        for constant in covered {
            #expect(
                behavioural.contains(constant),
                "\(constant) has a witness row but is not class B"
            )
        }
        #expect(Set(covered).count == covered.count, "a constant appears twice")
    }

    /// The row and the manifest must agree about which case witnesses which constant and which
    /// alternative value it is mutated to. Two independent statements of the same fact that
    /// could drift apart would be worse than one.
    @Test("every row agrees with the manifest it claims to witness")
    func everyRowMatchesTheManifest() throws {
        for row in Self.rows {
            let constant = try #require(
                RelevancePolicy.manifest.first { $0.name == row.constant },
                "\(row.constant) is not in the manifest"
            )
            let mutationDetail = "\(row.constant): the row mutates to \(row.mutation), "
                + "the manifest commits \(constant.mutations.joined(separator: ", "))"
            #expect(constant.mutations.contains(row.mutation), "\(mutationDetail)")

            let named = Self.names(in: row.subjects)
            let witnessDetail = "\(row.constant): the manifest names "
                + "\(constant.witnesses.joined(separator: ", ")) and the row uses "
                + named.joined(separator: ", ")
            #expect(constant.witnesses.contains { named.contains($0) }, "\(witnessDetail)")
            #expect(!row.argument.isEmpty)
        }
    }

    /// Every id the table names must be a case or a sequence that actually exists. A witness
    /// that was renamed is a witness that was lost, and this is where that shows.
    @Test("every named witness and sibling is in the committed corpus")
    func everyNamedFixtureExists() throws {
        let corpus = try CorpusFixtures.loaded()
        let caseIDs = Set(corpus.cases.map(\.id))
        let sequenceIDs = Set(corpus.sequences.map(\.id))

        for row in Self.rows {
            switch row.subjects {
            case .cases(let witness, let sibling):
                #expect(caseIDs.contains(witness), "\(row.constant): no case \(witness)")
                #expect(caseIDs.contains(sibling), "\(row.constant): no case \(sibling)")
            case .steps(let sequence, _, _), .sequences(let sequence, _):
                #expect(sequenceIDs.contains(sequence), "\(row.constant): no sequence \(sequence)")
            }
        }

        // And the manifest's own witness ids, which are what R-74.1 actually commits.
        for constant in RelevancePolicy.manifest where !constant.witnesses.isEmpty {
            for witness in constant.witnesses {
                #expect(
                    caseIDs.contains(witness) || sequenceIDs.contains(witness),
                    "\(constant.name) names \(witness), which is in neither the corpus nor the sequences"
                )
            }
        }
    }

    // MARK: - The witness actually flips

    /// The assertion that turns "corpus-tested constant" from an adjective into a gate: for
    /// every behavioural constant, the two halves of its experiment must produce **different**
    /// answers, and different in the observable the row names.
    @Test("every witness differs from its sibling in the named observable")
    func everyWitnessFlips() throws {
        let corpus = try CorpusFixtures.loaded()
        let runner = CorpusFixtures.runner
        let replay = SequenceReplayHarness(runner: runner)
        let caseByID = Dictionary(uniqueKeysWithValues: corpus.cases.map { ($0.id, $0) })
        let sequenceByID = Dictionary(uniqueKeysWithValues: corpus.sequences.map { ($0.id, $0) })

        for row in Self.rows {
            switch row.subjects {
            case .cases(let witnessID, let siblingID):
                let witness = try #require(caseByID[witnessID])
                let sibling = try #require(caseByID[siblingID])
                let left = runner.run(witness)
                let right = runner.run(sibling)
                // Both halves must themselves be correct, or the comparison is between two
                // things at least one of which the engine already gets wrong.
                #expect(runner.compare(witness, to: left) == nil, "\(witnessID) does not pass")
                #expect(runner.compare(sibling, to: right) == nil, "\(siblingID) does not pass")
                #expect(
                    Self.observed(row.observable, of: left, sibling: witness)
                        != Self.observed(row.observable, of: right, sibling: sibling),
                    """
                    \(row.constant) at \(row.mutation): \(witnessID) and \(siblingID) agree on \
                    \(row.observable.rawValue), so the corpus would not notice the constant \
                    moving.
                    \(row.argument)
                    """
                )

            case .steps(let sequenceID, let below, let above):
                let fixture = try #require(sequenceByID[sequenceID])
                let transcript = replay.replay(fixture)
                #expect(
                    replay.compare(fixture, to: transcript) == nil,
                    "\(sequenceID) does not replay as committed"
                )
                #expect(transcript.records.count > max(below, above))
                let left = transcript.records[below]
                let right = transcript.records[above]
                #expect(
                    Self.observed(row.observable, of: left)
                        != Self.observed(row.observable, of: right),
                    """
                    \(row.constant) at \(row.mutation): steps \(below) and \(above) of \
                    \(sequenceID) agree on \(row.observable.rawValue).
                    \(row.argument)
                    \(transcript.text)
                    """
                )

            case .sequences(let witnessID, let siblingID):
                let witness = try #require(sequenceByID[witnessID])
                let sibling = try #require(sequenceByID[siblingID])
                let left = replay.replay(witness)
                let right = replay.replay(sibling)
                #expect(replay.compare(witness, to: left) == nil, "\(witnessID) does not replay as committed")
                #expect(replay.compare(sibling, to: right) == nil, "\(siblingID) does not replay as committed")
                #expect(
                    left.mandateCount != right.mandateCount,
                    """
                    \(row.constant) at \(row.mutation): \(witnessID) and \(siblingID) issue the \
                    same number of mandates.
                    \(row.argument)
                    """
                )
            }
        }
    }

    // MARK: - The boundary triples themselves

    /// R-74.1's other half: each behavioural threshold has a committed case **on** it as well as
    /// either side. The dwell triples are the ones a reader can check by eye, and they are the
    /// ones a maintainer is most likely to disturb.
    @Test("the committed dwell triples sit either side of their thresholds")
    func theDwellTriplesAreCommitted() throws {
        let corpus = try CorpusFixtures.loaded()
        let threshold = Int(RelevancePolicy.sustainedDriftThreshold.components.seconds)
        let escalation = Int(RelevancePolicy.escalationDwell.components.seconds)
        let anchor = Int(RelevancePolicy.returnAnchorDwell.components.seconds)

        for boundary in [threshold, escalation, anchor] {
            for offset in [-1, 0, 1] {
                let dwell = boundary + offset
                #expect(
                    corpus.cases.contains { $0.dwellSeconds == dwell },
                    "no committed case dwells for \(dwell)s (\(boundary) \(offset))"
                )
            }
        }
    }

    // MARK: - Reading one observable

    static func names(in subjects: Subjects) -> [String] {
        switch subjects {
        case .cases(let witness, let sibling): [witness, sibling]
        case .steps(let sequence, _, _): [sequence]
        case .sequences(let witness, let sibling): [witness, sibling]
        }
    }

    static func observed(
        _ observable: Observable,
        of outcome: CorpusOutcome,
        sibling: CorpusCase
    ) -> String {
        switch observable {
        case .verdict: outcome.verdict.rawValue
        case .band: outcome.band?.rawValue ?? "-"
        case .eligibility: outcome.eligibility.encoded
        case .uncertaintyReason: outcome.uncertaintyReason?.rawValue ?? "-"
        case .explanationTokens: "\(outcome.explanationTokenCount)"
        case .drift, .accumulated, .mandateCount: "\(outcome.drift)"
        }
    }

    static func observed(
        _ observable: Observable,
        of record: SequenceObservationRecord
    ) -> String {
        switch observable {
        case .verdict: record.verdict.rawValue
        case .band: record.band?.rawValue ?? "-"
        case .eligibility: record.eligibility.encoded
        case .drift: record.driftName
        case .accumulated: "\(record.accumulatedSeconds)"
        case .uncertaintyReason, .explanationTokens, .mandateCount: record.line
        }
    }
}
