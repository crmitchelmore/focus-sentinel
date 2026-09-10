import FocusClassify
import FocusCore
import FoundationModels
import Foundation

/// **The one file in this repository that names `FoundationModels`.**
///
/// `check-forbidden.sh` R-117a counts the files containing `import FoundationModels`,
/// `SystemLanguageModel` and `LanguageModelSession` and requires the answer to be one, inside
/// `Packages/FocusModel`. e04's absolute ban (R-70h, *"no model, anywhere, in any form"*)
/// discharged its purpose — the heuristic layer was proven complete before a model existed —
/// and what replaces it is a **count**, so moving the producer is a reviewed act rather than a
/// quiet one. The ban is amended, not deleted: everywhere except this package it still holds.
///
/// ## What is deliberately absent, and what a lint says about each
///
/// * No `prewarm()`, no `SystemLanguageModel.Adapter`, no `SystemLanguageModel(useCase:)` —
///   the three surfaces that can pull an asset (R-117d). *"We never trigger a download"*
///   (R-108) is a lint here, not a promise: `.availability` is a read and that is all we do.
/// * No `Tool`, no tool conformance, no transcript carried between subjects. One-shot
///   sessions, no tools, no external content.
/// * No networking type of any kind. P-150 sampled `lsof -nP -i` every 100 ms across the
///   probe's whole life — eighty samples, zero lines — and `nettop -P` produced a header and
///   no data row. `modelmanagerd` stated the entitlement answer in its own words:
///   *"Unentitled inference allowed for usecase: com.apple.FoundationModels"*.
enum SystemModelPort {
    /// What this Mac says about the model, translated into `FocusCore`'s vocabulary.
    ///
    /// A read, never a request. `@unknown default` maps to `.unknown`, which
    /// `ModelTierAvailability` treats as not-executable — a state we cannot name is not a state
    /// we may treat as ready.
    static func availability() -> ModelTierAvailability {
        switch SystemLanguageModel.default.availability {
        case .available:
            return .available
        case .unavailable(let reason):
            switch reason {
            case .appleIntelligenceNotEnabled: return .appleIntelligenceNotEnabled
            case .modelNotReady: return .modelNotReady
            case .deviceNotEligible: return .deviceNotEligible
            @unknown default: return .unknown
            }
        @unknown default:
            return .unknown
        }
    }

    /// The four labels the schema keeps, and the mapping into what the app may act on.
    ///
    /// `unrelated` is kept **in the schema** so the model has somewhere to put a genuine "no"
    /// and the evaluation lane can count how often it says one. It is mapped, here and only
    /// here, to a *decline* — `ModelAnswer` has no `unrelated` case to map it to, which is U-1
    /// held at the type level. R-117c lints that `Verdict.unrelated` is not constructible
    /// anywhere in this package.
    @Generable
    enum Label: String, CaseIterable {
        /// This subject is the work itself.
        case yes
        /// This subject is in service of the work.
        case supporting
        /// Cannot tell.
        case unsure
        /// This subject is not the work. **Produces silence, never an accusation.**
        case unrelated
    }

    @Generable
    struct Judgement {
        @Guide(description: "How the observed application relates to the stated task.")
        var answer: Label
    }

    /// Every label, mapped. Total by construction — a fifth label is a compile error here.
    static func answer(for label: Label) -> ModelAnswer {
        switch label {
        case .yes: .relevant(.direct)
        case .supporting: .relevant(.supporting)
        case .unsure: .decline(.modelSaidUncertain)
        case .unrelated: .decline(.modelSaidUnrelated)
        }
    }

    /// One bounded generation, one session, no transcript kept.
    ///
    /// `.greedy` because P-154 measured twelve identical verdicts across two processes under
    /// it, which is the strongest reproducibility this tier offers; R-112's three-run bucket
    /// stability is what checks the claim rather than assuming it.
    ///
    /// A throw is a `.refused`, not a crash and not a retry loop: the deterministic answer is
    /// already standing, so the cost of a refusal is a question the app would have asked anyway.
    static func judge(_ request: ModelRequest) async -> ModelAnswer {
        do {
            let session = LanguageModelSession(instructions: Prompt.instructions)
            let response = try await session.respond(
                to: Prompt.question(for: request),
                generating: Judgement.self,
                options: GenerationOptions(sampling: .greedy)
            )
            return answer(for: response.content.answer)
        } catch {
            return .decline(.refused)
        }
    }
}
