import FocusClassify
import FocusCore
import Testing
@testable import FocusModel

/// **U-1, at the type level, and then folded over anyway.**
///
/// The guarantee is that `ModelAnswer` has no `unrelated` case: nothing the model says can be
/// widened into an accusation, because there is no value to widen it into. The fold below is a
/// check on the *mapping* — that every label the `@Generable` schema keeps has a destination,
/// and that the one label a naive implementation would route to `Verdict.unrelated` lands in a
/// decline instead. It is not the guarantee, and if somebody deleted it the guarantee would
/// still hold.
@Suite("The model answer vocabulary")
struct ModelAnswerTests {
    @Test("every schema label maps, and the mapping is total")
    func everyLabelMaps() {
        // `CaseIterable` over the `@Generable` enum: a fifth label added to the schema without a
        // destination is a compile error in `SystemModelPort.answer(for:)` and a new row here.
        #expect(SystemModelPort.Label.allCases.count == 4)
        for label in SystemModelPort.Label.allCases {
            _ = SystemModelPort.answer(for: label)
        }
    }

    @Test("the unrelated label produces a decline, never a relevance")
    func unrelatedDeclines() {
        #expect(SystemModelPort.answer(for: .unrelated) == .decline(.modelSaidUnrelated))
        #expect(!SystemModelPort.answer(for: .unrelated).isRelevant)
    }

    @Test("only the two positive labels are relevant, and each says which kind")
    func positiveLabels() {
        #expect(SystemModelPort.answer(for: .yes) == .relevant(.direct))
        #expect(SystemModelPort.answer(for: .supporting) == .relevant(.supporting))
        #expect(SystemModelPort.answer(for: .unsure) == .decline(.modelSaidUncertain))

        let relevant = SystemModelPort.Label.allCases
            .filter { SystemModelPort.answer(for: $0).isRelevant }
        #expect(Set(relevant) == [.yes, .supporting])
    }

    @Test("no answer this type can hold is an accusation")
    func noAnswerAccuses() {
        // Enumerated over the whole space rather than over the labels: every `ModelAnswer` that
        // can be constructed at all is either a relevance or a decline, and a decline is
        // silence. There is no third case and no payload that changes that.
        var space: [ModelAnswer] = ModelRelevance.allCases.map(ModelAnswer.relevant)
        space += ModelDeclineReason.allCases.map(ModelAnswer.decline)
        #expect(space.count == ModelRelevance.allCases.count + ModelDeclineReason.allCases.count)
        for answer in space {
            switch answer {
            case .relevant, .decline: continue
            }
        }
    }
}

/// The availability vocabulary, and the one thing every case of it must agree on.
@Suite("Model tier availability")
struct ModelTierAvailabilityTests {
    @Test("only `available` composes the rung into the ladder")
    func onlyAvailableExecutes() {
        for state in ModelTierAvailability.allCases {
            #expect(state.isExecutable == (state == .available))
        }
    }

    @Test("the capability mapping is total, and no case is a refusal")
    func capabilityMappingIsTotal() {
        for state in ModelTierAvailability.allCases {
            let mapped = state.capabilityState
            // `.denied` means *the user said no to us*, and this app asks nobody anything.
            #expect(mapped != .denied)
            #expect(mapped == (state == .available ? .available : .unavailable))
        }
    }
}

/// The rung's own behaviour, driven without a model on the machine.
@Suite("The model rung")
struct FocusModelRungTests {
    struct StubJudge: ModelJudging {
        let state: ModelTierAvailability
        let answer: ModelAnswer
        func availability() -> ModelTierAvailability { state }
        func judge(_ request: ModelRequest) async -> ModelAnswer { answer }
    }

    static func request(key: String = "k1", subject: String = "com.acme.tool") -> ModelRequest {
        ModelRequest(
            cacheKey: key,
            priorityTokens: NormalisedToken.normalised(["write", "proposal"]),
            subject: NormalisedToken.normalised(subject)!,
            priorityRevision: 1
        )
    }

    @Test("a cold cache answers nothing, which leaves the deterministic answer standing")
    func coldCacheIsSilent() {
        let rung = FocusModelRung(
            judge: StubJudge(state: .available, answer: .relevant(.direct))
        )
        #expect(rung.cachedAnswer(for: Self.request()) == nil)
    }

    @Test("a primed answer is served, and a decline is cached as hard as a rescue")
    func declinesAreCachedToo() async {
        let rescuer = FocusModelRung(
            judge: StubJudge(state: .available, answer: .relevant(.supporting))
        )
        #expect(await rescuer.prime(Self.request()) == .relevant(.supporting))
        #expect(rescuer.cachedAnswer(for: Self.request()) == .relevant(.supporting))

        let decliner = FocusModelRung(
            judge: StubJudge(state: .available, answer: .decline(.modelSaidUnrelated))
        )
        #expect(await decliner.prime(Self.request()) == .decline(.modelSaidUnrelated))
        // The cache IS the rate limiter: a second ask is served, not re-generated.
        #expect(await decliner.prime(Self.request()) == .decline(.modelSaidUnrelated))
        #expect(decliner.generationCount == 1)
    }

    @Test("a judge that could not be reached is asked again, not cached")
    func notAvailableIsNotCached() async {
        let unreachable = FocusModelRung(
            judge: StubJudge(state: .available, answer: .decline(.notAvailable))
        )
        #expect(await unreachable.prime(Self.request()) == .decline(.notAvailable))
        #expect(unreachable.cachedAnswer(for: Self.request()) == nil)
        #expect(await unreachable.prime(Self.request()) == .decline(.notAvailable))
        #expect(unreachable.generationCount == 0)
    }

    @Test("an unavailable tier declines and generates nothing")
    func unavailableTierAsksNobody() async {
        for state in ModelTierAvailability.allCases where state != .available {
            let rung = FocusModelRung(
                judge: StubJudge(state: state, answer: .relevant(.direct))
            )
            #expect(await rung.prime(Self.request()) == .decline(.notAvailable))
            #expect(rung.generationCount == 0)
            rung.request(Self.request())
            #expect(rung.cachedAnswer(for: Self.request()) == nil)
        }
    }

    @Test("a rule written about a subject drops what the model said about it")
    func invalidateBySubject() async {
        let rung = FocusModelRung(
            judge: StubJudge(state: .available, answer: .relevant(.direct))
        )
        await rung.prime(Self.request(key: "k1", subject: "com.acme.tool"))
        await rung.prime(Self.request(key: "k2", subject: "com.other.app"))

        rung.invalidate(subject: "com.acme.tool")
        #expect(rung.cachedAnswer(for: Self.request(key: "k1")) == nil)
        #expect(rung.cachedAnswer(for: Self.request(key: "k2", subject: "com.other.app")) != nil)
    }

    @Test("a session ending forgets everything")
    func resetForgets() async {
        let rung = FocusModelRung(
            judge: StubJudge(state: .available, answer: .relevant(.direct))
        )
        await rung.prime(Self.request())
        rung.reset()
        #expect(rung.cachedAnswer(for: Self.request()) == nil)
    }

    @Test("the prompt version is the revision list's length, never a digit")
    func promptVersionIsTheList() {
        let rung = FocusModelRung(
            judge: StubJudge(state: .available, answer: .relevant(.direct))
        )
        #expect(rung.promptVersion == Prompt.revisions.count)
        #expect(rung.promptVersion > 0)
    }

    @Test("the prompt carries the task and the subject and nothing else")
    func promptCarriesOnlyTokens() {
        let question = Prompt.question(for: Self.request())
        #expect(question.contains("write proposal"))
        #expect(question.contains("com.acme.tool"))
        // Nothing in the prompt invites a judgement about the person.
        for word in ["distract", "waste", "off task", "slack", "lazy"] {
            #expect(!question.lowercased().contains(word))
            #expect(!Prompt.instructions.lowercased().contains(word))
        }
    }
}
