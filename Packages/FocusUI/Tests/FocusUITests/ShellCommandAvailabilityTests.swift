import FocusCore
import Testing

@testable import FocusUI

/// **Every menu item is offered exactly when the app would carry it out** (focus-6uf).
///
/// Measured in the running binary before this repair: all thirteen of the app's own items
/// reported `isEnabled = true`, in the same self-check report where AppKit's Edit menu correctly
/// reported Undo, Cut and Paste disabled — and six of them ran a `guard … else { return }` and
/// vanished in the state a person is in the first time they open the menu. `CockpitView.swift`
/// states the rule in its own comment — *"a shortcut that silently does nothing is a shortcut
/// people stop trusting"* — and then implemented the silent nothing.
///
/// ## Why this is a fold and not a list of six cases
///
/// The shape that produced the bead is "a treatment one half received and the other did not": the
/// guards lived on the two `perform` implementations and the item that sends the command had
/// none. A proof written to the six reported cases would pass for a fourteenth action added with
/// no predicate at all. So the space is folded: every `PriorityCommand`, in every world the
/// vocabulary can describe.
@Suite("A menu item is offered exactly when the app would carry it out")
struct ShellCommandAvailabilityTests {
    /// Every world `ShellCommandWorld` can express, derived from the vocabularies rather than
    /// written out: two commitments × seven session states (no session, plus every
    /// `SessionPhase`) × two nudge states.
    static let everyWorld: [ShellCommandWorld] = [true, false].flatMap { hasPriority in
        ([nil] + SessionPhase.allCases.map { Optional($0) }).flatMap { phase in
            [true, false].map { hasOpenNudge in
                ShellCommandWorld(
                    hasPriority: hasPriority,
                    sessionPhase: phase,
                    hasOpenNudge: hasOpenNudge
                )
            }
        }
    }

    /// The commands that are available in every world, as a committed set.
    ///
    /// **Self-referential**: the fold below derives this set from the predicate and compares it
    /// with this literal, so a command that gains a precondition, loses one, or arrives with none
    /// changes the derived set and fails here rather than shipping enabled and silent.
    static let alwaysAvailable: Set<PriorityCommand> = [
        .newPriority, .addFilesToContext, .pauseSensing, .hideOverlays, .showMenuBar
    ]

    @Test("the set of unconditional commands is the set that was committed")
    func theUnconditionalSetIsTheCommittedOne() {
        let derived = Set(
            PriorityCommand.allCases.filter { command in
                Self.everyWorld.allSatisfy { command.isAvailable(in: $0) }
            }
        )
        #expect(
            derived == Self.alwaysAvailable,
            """
            a command changed whether it is always offered: \
            gained \(derived.subtracting(Self.alwaysAvailable)), \
            lost \(Self.alwaysAvailable.subtracting(derived))
            """
        )
    }

    /// **The non-vacuity guard, per command.** Every command that is not in the committed
    /// unconditional set must actually be withdrawn somewhere, or its "precondition" is a
    /// predicate that answers the same thing everywhere — which is the defect wearing the new
    /// mechanism's clothes.
    @Test("every conditional command is really withdrawn in some world")
    func everyConditionalCommandIsWithdrawnSomewhere() {
        for command in PriorityCommand.allCases where !Self.alwaysAvailable.contains(command) {
            #expect(
                Self.everyWorld.contains { !command.isAvailable(in: $0) },
                "\(command.rawValue) is offered in every world, so its guard is decoration"
            )
            #expect(
                Self.everyWorld.contains { command.isAvailable(in: $0) },
                "\(command.rawValue) is offered in no world at all, so the item is dead"
            )
        }
    }

    /// The completeness check. The space's size is computed from the vocabularies, so an eighth
    /// `SessionPhase` or a twelfth `PriorityCommand` grows it and the fold with it.
    @Test("the fold covers every command in every world the world can be in")
    func theFoldCoversTheWholeSpace() {
        #expect(Self.everyWorld.count == 2 * (SessionPhase.allCases.count + 1) * 2)
        #expect(PriorityCommand.allCases.count == 11)
        let cells = PriorityCommand.allCases.flatMap { command in
            Self.everyWorld.map { command.isAvailable(in: $0) }
        }
        #expect(cells.count == PriorityCommand.allCases.count * Self.everyWorld.count)
        #expect(cells.contains(true) && cells.contains(false))
    }

    /// **The three session verbs against the control they duplicate** (the bead's own acceptance
    /// criterion). `SessionControls.verbButtons` draws only the verbs the machine would accept
    /// from the phase the session is in; this is that table, read off the view, and the menu's
    /// predicate has to agree with it phase by phase.
    ///
    /// It is stated here rather than imported on purpose: a test that asked the predicate what
    /// the predicate says would be a mirror. This is the second, independent statement, and both
    /// of the disagreements it was written to catch were real — with a finished session the old
    /// guards offered *Pause*, which the machine rejects, and refused *Start*, which the cockpit
    /// draws a button for.
    @Test("the session verbs agree with the cockpit control, phase by phase", arguments: SessionPhase.allCases)
    func theSessionVerbsAgreeWithTheCockpit(phase: SessionPhase) {
        // What `SessionControls.verbButtons` draws for this phase, of the three verbs the menu
        // also offers.
        let cockpitOffers: (start: Bool, pause: Bool, complete: Bool) = switch phase {
        case .focus, .intentionalDetour, .onBreak: (start: false, pause: true, complete: true)
        case .paused: (start: false, pause: false, complete: true)
        case .interrupted, .complete: (start: true, pause: false, complete: false)
        }
        let world = ShellCommandWorld(hasPriority: true, sessionPhase: phase, hasOpenNudge: false)
        #expect(PriorityCommand.startSession.isAvailable(in: world) == cockpitOffers.start)
        #expect(PriorityCommand.pauseSession.isAvailable(in: world) == cockpitOffers.pause)
        #expect(PriorityCommand.completeSession.isAvailable(in: world) == cockpitOffers.complete)
    }

    /// With no session at all the cockpit draws its Start button and nothing else, and the menu
    /// says the same. The `nil` phase is not in `SessionPhase.allCases`, so it is its own case.
    @Test("with no session only Start is offered")
    func withNoSessionOnlyStartIsOffered() {
        let world = ShellCommandWorld(hasPriority: true, sessionPhase: nil, hasOpenNudge: false)
        #expect(PriorityCommand.startSession.isAvailable(in: world))
        #expect(!PriorityCommand.pauseSession.isAvailable(in: world))
        #expect(!PriorityCommand.completeSession.isAvailable(in: world))
    }

    /// Every registry action answers, and the two effects that are not commands answer `true` for
    /// the reasons their documentation gives. A fold over the shipping registry, so an action
    /// added tomorrow is asked the question here.
    @Test("every shipped action answers the availability question in every world")
    func everyShippedActionAnswers() {
        for action in CommandRegistry.shell.actions {
            for world in Self.everyWorld {
                // The point is that it answers at all — the *values* are the fold above. This is
                // the join: an action whose effect had no case would not compile, and one whose
                // effect is a command must agree with that command.
                if case .priority(let command) = action.effect {
                    #expect(action.isAvailable(in: world) == command.isAvailable(in: world))
                } else {
                    #expect(action.isAvailable(in: world))
                }
            }
        }
        #expect(CommandRegistry.shell.actions.count == 13)
    }

    /// **What this proof would still be green for** (repair doctrine, clause 3).
    ///
    /// It is entirely about the predicate. It says nothing about whether `ShellActionButton`
    /// actually applies `.disabled(…)`, nothing about whether AppKit's `NSMenuItem` reflects it,
    /// and nothing about the world the composition root assembles — a provider that answered
    /// `nothingIsCommitted` for the running app would pass every line here while withdrawing
    /// items a person could use. Those three are the self-check's: it reads the world the running
    /// binary reports, compares each item's live `isEnabled` and `hasAction` with this predicate's
    /// answer, and holds both against a table written independently in `scripts/self-check.sh`.
    @Test("a world nobody filled in withdraws the conditional verbs and keeps the rest")
    func theEmptyWorldWithdrawsTheConditionalVerbs() {
        let empty = ShellCommandWorld.nothingIsCommitted
        for command in PriorityCommand.allCases {
            let expected = Self.alwaysAvailable.contains(command) || command == .startSession
            #expect(
                command.isAvailable(in: empty) == expected,
                "\(command.rawValue) answered \(command.isAvailable(in: empty)) for an empty world"
            )
        }
    }
}
