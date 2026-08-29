import Foundation

/// **One rung of the accusation ladder**, and the type that makes "a query cannot escalate
/// into an accusation" a fact rather than a promise.
///
/// The Court ruled three stages (D-06) and e05 shipped three. **U-2 amended that ruling to two**:
/// the ambient glyph and a single panel nudge. The third rung — explicit recommitment, and the
/// escalation from the panel to it — is deferred to epic focus-5ab, to be designed cleanly rather
/// than repaired, and is removed from the shipping product rather than left behind a flag.
///
/// What makes this type load-bearing is not the count but the **provenance**: a rung is the
/// accusation's unit of escalation, so where a rung can come from *is* the no-escalation
/// invariant.
///
/// * The memberwise initialiser is `fileprivate`, and this file holds exactly two producers —
///   `entry(for:)` and `escalated()` — both of which start from an `InterventionMandate`.
/// * There is **no overload taking a `QueryWarrant`, a `Verdict` or a `Bool`.** A question
///   carries no band and no stage, which the ladder requires, so an adapter could not be
///   written without inventing evidence — and inventing evidence is visible in a diff.
/// * `check-forbidden.sh` asserts (R-96c) that `LadderRung(` appears in exactly one source
///   file, that the file names `InterventionMandate`, and that it does **not** name
///   `QueryWarrant`.
///
/// Together with `QueryWarrant`'s own single producer and the ban on a shared protocol
/// (R-96d), that is the third of R-76's four structural facts.
public struct LadderRung: Sendable, Equatable, Hashable {
    /// The two stages, in escalation order.
    ///
    /// Rank is derived from `allCases`, exactly as `CascadeStage.rank` and `EvidenceBand.rank`
    /// are, so the order is a property of the declaration and no numeric literal appears
    /// (R-96j).
    public enum Kind: String, Sendable, CaseIterable, Codable, Hashable, Comparable {
        /// Rank 0. The menu-bar glyph changes to `unrelated`, and nothing else happens: no
        /// panel, no sound, no motion. Under Reduce Motion it is a shape and label change
        /// only. e08 adds the notch as a second renderer of this same rung.
        case ambient
        /// Rank 1. The non-activating `NSPanel` with the full correction economy — the first
        /// thing that asks for attention, and now the last. The ladder tops out here.
        case panel

        /// Where this rung sits. 0, 1 — derived, never written down.
        public var rank: Int {
            Self.allCases.firstIndex(of: self) ?? Self.allCases.count
        }

        /// The rung above this one, or `nil` at the top. The ladder tops out at the panel; the
        /// recommitment rung above it is deferred to focus-5ab, and there was never any coercion
        /// above that either (D-07, R-99).
        public var next: Kind? {
            let index = rank + 1
            return index < Self.allCases.count ? Self.allCases[index] : nil
        }

        /// The String Catalog key for this rung's label. `check-strings.sh` asserts the
        /// bijection with `nudge.rung.*` in both directions (R-96l).
        public var copyKey: String {
            switch self {
            case .ambient: "nudge.rung.ambient"
            case .panel: "nudge.rung.panel"
            }
        }

        public var copyResource: LocalizedStringResource {
            LocalizedStringResource(
                String.LocalizationValue(copyKey),
                bundle: .atURL(Bundle.module.bundleURL)
            )
        }

        public static func < (lhs: Kind, rhs: Kind) -> Bool { lhs.rank < rhs.rank }
    }

    /// Which stage this is.
    public let kind: Kind
    /// **The authorisation this rung exists on.** Not a `Verdict`, not a `Bool`, not a
    /// `QueryWarrant`: the one type e04 made unconstructible from an `uncertain` verdict.
    public let mandate: InterventionMandate

    /// **Fileprivate on purpose**, with exactly two callers, both in this file.
    fileprivate init(kind: Kind, mandate: InterventionMandate) {
        self.kind = kind
        self.mandate = mandate
    }

    /// The rung a ladder enters at, for a fresh mandate.
    ///
    /// **Always `.ambient`.** The ladder never re-enters at the rung it left: a person who came
    /// back and drifted again starts at the silent glyph, because starting at the notification
    /// would punish them for having complied once (R-80).
    public static func entry(for mandate: InterventionMandate) -> LadderRung {
        LadderRung(kind: Kind.allCases[0], mandate: mandate)
    }

    /// The next rung up, for the same mandate, or `nil` at the top.
    ///
    /// Whether escalation is *permitted* is `LadderMachine`'s question and needs four more
    /// facts — a still-live mandate, a **delivered** previous rung (R-81), `escalationDwell`
    /// elapsed since that delivery, and budget (R-83). This function only says what the next
    /// rung would be.
    public func escalated() -> LadderRung? {
        guard let next = kind.next else { return nil }
        return LadderRung(kind: next, mandate: mandate)
    }

    /// The subject this rung is about, or `nil` when drift accumulated across several and a
    /// surface must say "several unrelated apps" rather than misnaming one of them.
    public var subject: String? {
        mandate.isMixed || mandate.subject.isEmpty ? nil : mandate.subject
    }
}

/// Where the ladder has got to.
///
/// A value, reduced by a pure function on an injected `MonotonicClock` reading — e03's R-46
/// doctrine and e04's `DriftState`, applied to the third state machine that needed it. There is
/// no timer object anywhere in the nudge, and R-96i is the lint that keeps it that way; that is
/// what makes every sequence fixture an exact assertion rather than a flaky one.
public enum LadderState: Sendable, Equatable, Hashable {
    /// Nothing is escalating. The state a correction, a snooze, a pause, a priority change, a
    /// return to task, a phase change out of `.focus` or a `relevant` verdict resets to —
    /// immediately and totally (R-80).
    case idle
    /// A rung has been **delivered** and the ladder is waiting.
    ///
    /// - Parameters:
    ///   - rung: what was delivered.
    ///   - deliveredAt: the monotonic reading of that delivery. `escalationDwell` is measured
    ///     from here, which is why a `.deferred` rung must never write it (R-81).
    ///   - consecutiveIgnored: delivered rungs since the last correction, snooze, pause or
    ///     return. At `InterventionPolicy.ignoredAccusationBackoff` the ladder holds.
    case engaged(rung: LadderRung, deliveredAt: Duration, consecutiveIgnored: Int)
    /// The person has ignored `ignoredAccusationBackoff` rungs in a row, so the ladder has
    /// dropped back to the ambient rung and holds there for the rest of the session.
    ///
    /// It does **not** go fully silent: the glyph still tells the truth, because that is the
    /// one channel the person has not objected to and F-146's whole point is that the state is
    /// always legible.
    case heldAtAmbient(rung: LadderRung, since: Duration)

    /// The rung currently occupied, if any.
    public var rung: LadderRung? {
        switch self {
        case .idle: nil
        case .engaged(let rung, _, _): rung
        case .heldAtAmbient(let rung, _): rung
        }
    }

    /// How many delivered rungs have gone unanswered.
    public var consecutiveIgnored: Int {
        switch self {
        case .idle, .heldAtAmbient: 0
        case .engaged(_, _, let count): count
        }
    }
}

/// The things that end a ladder outright.
///
/// De-escalation is **immediate and total** (R-80): any one of these resets the state to
/// `.idle`, and re-entry is at the ambient rung. There is no partial climb-down, because a
/// ladder that remembered where it was would punish somebody for having complied.
public enum LadderDeEscalation: String, Sendable, CaseIterable, Codable, Hashable {
    /// "This is relevant" — the correction that removes the subject from the accusable set
    /// entirely, and therefore suppresses harder than any ignore (R-83).
    case corrected
    /// "Not this time" — a session-lived rule through e04's `SessionRuleBox`.
    case excusedForThisSession
    case snoozed
    case paused
    case priorityChanged
    case returnedToTask
    /// The session left `.focus` — a break, a deliberate detour, an interruption, completion.
    case phaseLeftFocus
    /// The engine now says this is real work.
    case verdictRelevant
    case sessionEnded
}

/// What the ladder's reducer consumes.
///
/// Declared here, with the rest of the vocabulary, so that `LadderMachine` (T129) is a pure
/// function over values that already exist rather than a machine that invents its own inputs.
public enum LadderEvent: Sendable, Equatable, Hashable {
    /// A live mandate for a subject was observed.
    case mandate(InterventionMandate)
    /// What actually happened when the app tried to speak. **`.deferred` does not advance the
    /// ladder, does not spend either cap and does not start the escalation clock** (R-81).
    case delivery(RungDelivery)
    /// A delivered rung went unanswered — no correction, snooze, pause or return.
    case rungIgnored
    /// Something happened that ends the ladder.
    case deEscalated(LadderDeEscalation)
    /// Time passed and nothing else did. Carries the monotonic reading, so a replay is exact.
    case tick(Duration)
}
