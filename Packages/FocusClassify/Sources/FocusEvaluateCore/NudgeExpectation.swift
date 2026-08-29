import FocusCore
import Foundation

/// **What a person would have answered**, committed case by case (R-94a, T143b).
///
/// P-140 enumerated every field of all 165 committed corpus cases and found that `expect` carries
/// the classifier's expected *output* and nothing else — there is **no field anywhere recording
/// what a person would have said**. That is why `queryRate ≤ 0.17` could never have been a
/// false-positive rate: the ground truth for one did not exist in the file. This is the field that
/// authors it.
///
/// Three values, and the third is not a hedge. A subject like Slack or Figma against *"write the
/// Q3 proposal"* has **no wrong answer**: a person might reasonably say yes and a person might
/// reasonably say no, and the app's only failure there would be to ask too often — which is what
/// `queryVolumeRate` and `queriesPerFocusDay` measure. So `eitherIsReasonable` cases are excluded
/// from the band's denominator and counted in a field of their own, rather than being forced onto
/// one side and quietly moving a number that is supposed to mean something.
public enum QueryGroundTruth: String, Sendable, CaseIterable, Codable, Hashable {
    /// The person would say "yes, this is part of it". A *"yes"* is **not** a false positive:
    /// under U-1 it is the affordance working — one click, a durable rule, a subject the app
    /// never has to ask about again (R-94a's recorded refusal).
    case relevant
    /// The person would say "no". A question here is the app being polite about something it
    /// might have had the evidence to call `unrelated` outright.
    case unrelated
    /// **No answer is wrong.** Excluded from every ratio's denominator.
    case eitherIsReasonable

    /// Whether this case contributes to `nudge.queryAnsweredRelevantShare`'s two-sided band.
    public var countsTowardsBand: Bool { self != .eitherIsReasonable }
}

/// **What the nudge loop must do with one judgement**, committed on the case beside the
/// classifier's own expectation (T143a).
///
/// Four shapes and no fifth, mirroring `NudgeDecision` exactly — because a corpus expectation that
/// could not express one of the decider's answers would be a corpus that silently stopped testing
/// it. The payload is carried in every case: *"silent"* alone would pass for a case suppressed by
/// the wrong gate, and the first gate that closed is the reason a person would be given.
public enum NudgeExpectation: Sendable, Equatable, Hashable {
    /// The app says nothing, and this is the **first** gate of R-84's ordered stack that closed.
    case silent(NudgeSuppressionReason)
    /// The app asks one question, for this askable uncertainty (R-77).
    case ask(QueryableUncertainty)
    /// The app says "you are off task", at this rung of D-06's three.
    case accuse(LadderRung.Kind)
    /// The app would have spoken and could not be seen. **Advances nothing, spends nothing**
    /// (R-81).
    case deferred(DeferralReason)

    /// `"silent:<reason>"` · `"ask:<reason>"` · `"accuse:<rung>"` · `"deferred:<reason>"`.
    ///
    /// One string rather than an object, for the same reason `CorpusEligibility.encoded` is one:
    /// a fixture reads better as `"ask:noNegativeBasis"` than as three lines of JSON, and a
    /// failure message that prints two of these side by side is legible without a diff tool.
    public var encoded: String {
        switch self {
        case .silent(let reason): "silent:\(reason.rawValue)"
        case .ask(let reason): "ask:\(reason.rawValue)"
        case .accuse(let rung): "accuse:\(rung.rawValue)"
        case .deferred(let reason): "deferred:\(reason.rawValue)"
        }
    }

    /// Decode strictly. An unknown head or an unknown payload fails the **load**, never defaults:
    /// a corpus that accepted `"aks:noNegativeBasis"` would be a corpus that stopped asserting
    /// anything about that case, silently and for ever.
    public static func decode(_ raw: String, path: String) throws -> NudgeExpectation {
        let parts = raw.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2 else {
            throw CorpusDecodingError(
                path: path,
                reason: "'\(raw)' is not '<silent|ask|accuse|deferred>:<payload>'"
            )
        }

        func payload<T: RawRepresentable & CaseIterable>(
            _ type: T.Type
        ) throws -> T where T.RawValue == String {
            guard let value = T.allCases.first(where: { $0.rawValue == parts[1] }) else {
                throw CorpusDecodingError(
                    path: path,
                    reason: "'\(parts[1])' is not one of "
                        + T.allCases.map(\.rawValue).joined(separator: ", ")
                )
            }
            return value
        }

        switch parts[0] {
        case "silent": return .silent(try payload(NudgeSuppressionReason.self))
        case "ask": return .ask(try payload(QueryableUncertainty.self))
        case "accuse": return .accuse(try payload(LadderRung.Kind.self))
        case "deferred": return .deferred(try payload(DeferralReason.self))
        default:
            throw CorpusDecodingError(
                path: path,
                reason: "'\(parts[0])' is not silent, ask, accuse or deferred"
            )
        }
    }

    /// The expectation a decision would satisfy — so a failure message says what to write rather
    /// than only what was wrong.
    public static func observed(_ decision: NudgeDecision) -> NudgeExpectation {
        switch decision {
        case .accuse(let rung, _): .accuse(rung.kind)
        case .ask(let warrant, _): .ask(warrant.reason)
        case .silent(let silence): .silent(silence.reason)
        case .deferred(let reason): .deferred(reason)
        }
    }

    /// Whether this expectation is an interruption a person would experience.
    public var isSpeaking: Bool {
        switch self {
        case .ask, .accuse: true
        case .silent, .deferred: false
        }
    }

    /// The askable uncertainty a question was about, when it was one.
    public var queryReason: QueryableUncertainty? {
        switch self {
        case .ask(let reason): reason
        case .silent, .accuse, .deferred: nil
        }
    }
}
