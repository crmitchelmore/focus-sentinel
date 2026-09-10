import Foundation

/// **The words History uses for the vocabularies the ledger already stores** (focus-tee.5).
///
/// Four closed enums that had raw values and no sentence: what became of an interruption, what
/// the person did about it, what they answered a question, and why an affordance was withdrawn.
/// Until now nothing drew them, because nothing rendered a stored row back to a person.
///
/// Here rather than in `FocusUI` for the reason every other relevance vocabulary is: the enum
/// lives in `FocusCore`, and a surface that had to know which case it was holding in order to
/// pick a key would be the fifth place the vocabulary is written down. Each accessor is an
/// exhaustive `switch`, so a case added tomorrow does not compile until it has a sentence, and
/// `Config/string-draw-sites.txt` carries the row that says which file draws each namespace.
///
/// **The sentences are past tense and factual.** History says what happened; it does not grade
/// it, congratulate anybody or express regret. D-01's ruling is about numbers, but the same
/// reasoning applies to adjectives: a ledger that editorialises is a scoreboard with words.
extension InterventionDisposition {
    /// The String Catalog key describing what became of this interruption.
    public var historyCopyKey: String {
        switch self {
        case .delivered: "history.disposition.delivered"
        case .deferred: "history.disposition.deferred"
        case .unopened: "history.disposition.unopened"
        case .suppressed: "history.disposition.suppressed"
        }
    }

    public var historyCopyResource: LocalizedStringResource {
        LocalizedStringResource(
            String.LocalizationValue(historyCopyKey),
            bundle: .atURL(Bundle.module.bundleURL)
        )
    }
}

extension InterventionOutcome {
    /// The String Catalog key describing what the person did about it.
    public var historyCopyKey: String {
        switch self {
        case .dismissed: "history.outcome.dismissed"
        case .corrected: "history.outcome.corrected"
        case .snoozed: "history.outcome.snoozed"
        case .returned: "history.outcome.returned"
        case .pausedSession: "history.outcome.pausedSession"
        case .priorityChanged: "history.outcome.priorityChanged"
        case .answered: "history.outcome.answered"
        case .ignored: "history.outcome.ignored"
        }
    }

    public var historyCopyResource: LocalizedStringResource {
        LocalizedStringResource(
            String.LocalizationValue(historyCopyKey),
            bundle: .atURL(Bundle.module.bundleURL)
        )
    }
}

extension NudgeSurface {
    /// The String Catalog key naming **where** an interruption was carried.
    ///
    /// `notification` keeps a sentence although the app posts none: the case exists so a stored
    /// row written by an earlier build still decodes and still draws, which is the same reason
    /// the case itself was kept rather than deleted. A row nobody can read is a row silently
    /// dropped.
    public var historyCopyKey: String {
        switch self {
        case .menuBar: "history.surface.menuBar"
        case .panel: "history.surface.panel"
        case .notification: "history.surface.notification"
        case .popoverBadge: "history.surface.popoverBadge"
        }
    }

    public var historyCopyResource: LocalizedStringResource {
        LocalizedStringResource(
            String.LocalizationValue(historyCopyKey),
            bundle: .atURL(Bundle.module.bundleURL)
        )
    }
}

extension AskedQuestionOutcome {
    /// The String Catalog key for **the person's own answer**, in their words rather than the
    /// app's: this is the one column in the ledger that records what *they* said.
    public var historyCopyKey: String {
        switch self {
        case .answeredRelevant: "history.answer.answeredRelevant"
        case .answeredUnrelated: "history.answer.answeredUnrelated"
        case .declined: "history.answer.declined"
        case .expired: "history.answer.expired"
        }
    }

    public var historyCopyResource: LocalizedStringResource {
        LocalizedStringResource(
            String.LocalizationValue(historyCopyKey),
            bundle: .atURL(Bundle.module.bundleURL)
        )
    }
}

extension HistoryWithdrawal {
    /// The String Catalog key saying **why** the correction is not being offered.
    ///
    /// R-88: an affordance withdrawn without a stated reason is a control a person cannot
    /// account for, which is worse than one that is simply absent.
    public var copyKey: String {
        switch self {
        case .priorityDeleted: "history.withdrawal.priorityDeleted"
        case .noPriority: "history.withdrawal.noPriority"
        case .originSubject: "history.withdrawal.originSubject"
        case .noSubject: "history.withdrawal.noSubject"
        }
    }

    public var copyResource: LocalizedStringResource {
        LocalizedStringResource(
            String.LocalizationValue(copyKey),
            bundle: .atURL(Bundle.module.bundleURL)
        )
    }
}
