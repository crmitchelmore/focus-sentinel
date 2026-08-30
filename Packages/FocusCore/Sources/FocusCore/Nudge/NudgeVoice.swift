import Foundation

/// A value a template line needs filled in.
///
/// Four, and each is a **typed value the app already has**, never prose it composes. Two of
/// them name something — the priority and the subject — and those are the two the Court's
/// default templates declare ("Still working on {task}?", "Is {subject} part of {task}?"). The
/// other two are a rendered duration and the return target, which is itself a subject.
///
/// There is no fifth, and there is no free-form slot. That is what makes standing condition 4
/// structural rather than observed: the copy path is `NudgeVoice → NudgeCopyKey →
/// LocalizedStringResource`, and **no string in any deck is generated at runtime** (D-11).
/// There is no model in this build at all, and when e06 adds one the copy path is unchanged.
public enum NudgeCopySlot: String, Sendable, CaseIterable, Codable, Hashable {
    /// The priority's intent, in the person's own words, rendered through e02's
    /// truncation-free treatment.
    case task
    /// The application's localised name or the normalised origin. **Never a window title,
    /// never a path, never a URL with a path or a query** — e04's `NormalisedToken` makes those
    /// unrepresentable and this slot inherits the guarantee.
    case subject
    /// A rendered duration. A fact about the person's own day, not a score about them.
    case duration
    /// The application a return-to-task would activate, when one is stored. The action is not
    /// offered at all when there is none: a "back to work" button with nowhere to go is a
    /// button that lies (R-88).
    case returnTarget
}

/// **Every line a nudge can say.** Thirteen situations, and no fourteenth.
///
/// The raw value is the key's tail; the full String Catalog key is
/// `nudge.<deck>.<situation>`, composed by `NudgeVoice.key(_:)`. Composing rather than writing
/// sixty-five literals is deliberate: the pair is checked as a **bijection** by
/// `check-strings.sh` (R-96l) — every deck × every key exists in the catalog, and every
/// `nudge.*` catalog key names a real pair — which is a stronger property than "this literal
/// appears in some source file".
public enum NudgeCopyKey: String, Sendable, CaseIterable, Codable, Hashable {
    // The accusation, at rung 2 — the panel, which is the top of the ladder (U-2). There is no
    // rung 3 for these lines to also serve.
    case accusationPanelTitle = "accusation.panel.title"
    case accusationPanelBody = "accusation.panel.body"
    case accusationActionReturn = "accusation.action.return"
    case accusationActionRelevant = "accusation.action.relevant"
    case accusationActionNotNow = "accusation.action.notNow"
    case accusationActionSnooze = "accusation.action.snooze"
    case accusationActionPriority = "accusation.action.priority"
    case accusationActionPause = "accusation.action.pause"

    // The question. U-1's centrepiece: three actions and no more.
    case queryPanelTitle = "query.panel.title"
    case queryPanelScopeApp = "query.panel.scope.app"
    case queryActionYes = "query.action.yes"
    case queryActionNo = "query.action.no"
    case queryActionNotNow = "query.action.notNow"

    /// The slots this line takes, **in the order the format string consumes them**.
    ///
    /// `NudgeVoiceTests` asserts that every deck's string for a key carries exactly this many
    /// `%@` specifiers — so a translator who drops one, or a deck that invents one, fails the
    /// suite rather than crashing a person's nudge.
    public var slots: [NudgeCopySlot] {
        switch self {
        case .accusationPanelTitle: [.task]
        case .accusationPanelBody: [.subject, .duration]
        case .accusationActionReturn: [.returnTarget]
        case .queryPanelTitle: [.subject, .task]
        case .accusationActionRelevant, .accusationActionNotNow, .accusationActionSnooze,
             .accusationActionPriority, .accusationActionPause, .queryPanelScopeApp,
             .queryActionYes, .queryActionNo, .queryActionNotNow: []
        }
    }

    /// Whether this line belongs to the **question**.
    ///
    /// R-96f fails the gate on any second-person accusatory string under a `query` key. The
    /// accusation never says "you are distracted"; the question never says "you should be
    /// working". Tone is the product, and D-11 made the copy static precisely so it could be
    /// checked.
    public var isQueryLine: Bool { rawValue.hasPrefix("query.") }
}

/// **Five static decks, and no way to generate a sixth** (R-90, F-65, D-11, SC-4).
///
/// Four of them are registers of the same thirteen lines. The fifth is different in kind:
/// `silentVisual` is a **routing** deck rather than a copy deck — it takes the panel rung and the
/// question alike into the menu-bar popover — and it is the accessibility-critical one, so it
/// carries the full line set as well and is snapshot-tested like the rest.
///
/// The Court's adopted default is F-66's: **"Still working on {task}?"** for the accusation and
/// its question-shaped sibling **"Is {subject} part of {task}?"** for the query.
public enum NudgeVoice: String, Sendable, CaseIterable, Codable, Hashable {
    /// The Court's adopted default.
    case neutral
    /// Gentler, and slower to imply anything.
    case warm
    /// Terse. Fewer words, never harder words.
    case direct
    /// Lighter. Still never accusatory.
    case playful
    /// Quiet by construction: no panel, no motion, no sound. A routing deck.
    case silentVisual

    /// What ships.
    public static let standard = NudgeVoice.neutral

    /// Whether this deck changes **where** a nudge appears rather than only what it says.
    ///
    /// It is read by `SurfaceRouter.route(rung:…)`, as one of the three terms of that function's
    /// *quiet* condition, beside `reducedInterruption` and a running microphone. That is the
    /// whole of the deck's routing effect and there is no second mechanism: R-92's ruling is one
    /// flag inside the existing router, and a deck that reached the router by a private path
    /// would be the parallel surface stack the ruling forbids.
    ///
    /// **It used to have a partner, `renderedRung(for:)`, and deleting that is focus-vxo's
    /// ruling.** The function claimed the panel rung *was* the ambient rung under this deck, and
    /// three things made that false at once. The running loop recorded the rung as an accusation
    /// delivered against a named subject and spent the accusation budget on it, `MenuBarPopover`
    /// drew the panel rung's own label — *"A small panel you can answer"* — and the router sent
    /// it to `.menuBar`, which offers no answer at all. Worse, the claim was load-bearing in the
    /// two properties that existed to catch exactly this: both asked the *rendered* rung whether
    /// it made an accusation, so the four broken cells were skipped by their own guard. A rung
    /// the ladder climbed to, recorded, and charged for is an accusation; a deck may choose a
    /// quieter **surface** for it and may not un-say it.
    public var isRoutingDeck: Bool { self == .silentVisual }

    /// The surface a **question** takes under this voice.
    ///
    /// Reduced interruption produces the same answer through the router's own flag, which is
    /// why R-92 is one flag inside the existing router rather than a parallel surface stack.
    public var querySurface: NudgeSurface {
        switch self {
        case .neutral, .warm, .direct, .playful: .panel
        case .silentVisual: .popoverBadge
        }
    }

    /// The full String Catalog key for one line in this deck.
    public func key(_ line: NudgeCopyKey) -> String {
        "\(Self.keyPrefix).\(rawValue).\(line.rawValue)"
    }

    /// The localised line, resolved against this package's own bundle.
    public func resource(_ line: NudgeCopyKey) -> LocalizedStringResource {
        LocalizedStringResource(
            String.LocalizationValue(key(line)),
            bundle: .atURL(Bundle.module.bundleURL)
        )
    }

    /// The namespace every deck key lives under. Named once, here, because
    /// `check-strings.sh` reads the same prefix and a second spelling of it would be a fifth
    /// place the vocabulary is written down.
    public static let keyPrefix = "nudge"

    /// Every key in the matrix — five decks × thirteen lines — in a stable order.
    ///
    /// This is what the completeness lint compares the catalog against, and what the settings
    /// pane's preview iterates.
    public static var matrix: [String] {
        allCases.flatMap { voice in NudgeCopyKey.allCases.map { voice.key($0) } }
    }
}
