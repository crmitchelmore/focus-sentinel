import FocusCore
import SwiftUI
import Testing

@testable import FocusUI

/// F-145 in two halves, both automated and both grant-free.
///
/// *Menu half:* an action with a key equivalent is reachable from anywhere, and the registry
/// suite pins the equivalents. *Focus half:* everything else must be reachable by Tab, in a
/// predictable order, with Return and Escape bound wherever the surface has something for
/// them to do. This suite asserts the reconciliation of the two — every action is reachable
/// one way or the other, and no field is declared and then left unreachable.
///
/// Nothing here needs a TCC grant. The runtime confirmation is the app's own self-check
/// (`performKeyEquivalent`), and Full Keyboard Access is confirmed by eye in the live
/// frames — evidence, never the gate.
@Suite("Keyboard reachability")
struct KeyboardReachabilityTests {
    private let registry = CommandRegistry.shell

    // MARK: - Every action is reachable

    @Test("every shell action is menu-reachable or focus-reachable")
    func everyActionIsReachable() {
        for action in registry.actions {
            let menuReachable = action.shortcut != nil
                && MenuPlacement.allCases.contains(action.placement)
            let focusReachable = FocusField.allCases.contains { field in
                FocusTraversal.surface(of: field) != nil && field.rawValue == action.id
            }
            #expect(menuReachable || focusReachable, "\(action.id) is unreachable")
        }
    }

    @Test("every action carries a discoverable key equivalent")
    func everyActionIsBound() {
        // Per the Court's ruling not every action needs a shortcut — but every one the shell
        // ships today does, and losing one would be a regression rather than a design change.
        #expect(registry.actions.allSatisfy { $0.shortcut != nil })
    }

    @Test("a priority command reaches a surface that answers it")
    func priorityCommandsHaveASurface() {
        // The other half of "reachable": a key equivalent that arrives somewhere nothing is
        // listening is a shortcut in the reference and a dead end in the app. Every priority
        // command is answered by the cockpit, whose focus contract names the field each one
        // lands in.
        let cockpit = FocusTraversal.contract(for: .cockpit)
        #expect(cockpit.order.contains(.cockpitCaptureField))
        #expect(cockpit.order.contains(.cockpitComplete))
        #expect(cockpit.order.contains(.cockpitContextAddFiles))
    }

    // MARK: - e05: every nudge action is reachable without a mouse (F-145)

    /// The accusation panel offers six actions. Each one is reachable from the keyboard, and
    /// this asserts the **mapping** rather than the count: every action either has a registry
    /// command of its own or is one of the two the registry already had under another name.
    @Test("every action on the accusation panel has a keyboard route")
    func everyPanelActionHasAKeyboardRoute() throws {
        let routes: [CorrectionAction: String] = [
            .thisIsRelevant: "nudge.relevant",
            .snooze: "nudge.snooze",
            // Already in the registry under the name the rest of the app uses for it.
            .pause: "session.pause",
            .changePriority: "priority.new"
        ]

        for (action, id) in routes {
            let command = try #require(registry.action(id: id), "\(action) has no command")
            #expect(command.shortcut != nil)
        }

        // The two that are not commands, and why neither needs to be:
        //
        //   * `returnToTask` is offered only when there is somewhere to go, so a fixed key
        //     equivalent would be a shortcut that does nothing most of the time — and the panel
        //     draws it as the prominent action, which is where a person looks first.
        //   * `dismiss` is **Escape**, on the panel itself, through
        //     `NudgePanel.cancelOperation(_:)`. That is a keyboard route; it is simply not a
        //     menu one, and binding Escape in the menu bar would take it from every text field.
        #expect(registry.actions.allSatisfy { $0.id != "nudge.return" })
        #expect(registry.actions.allSatisfy { $0.id != "nudge.dismiss" })
    }

    /// F-81's command clears the screen and is reachable, and it is the **only** action in the
    /// registry that answers nothing: hiding is not dismissing, and it writes nothing at all.
    @Test("hiding every overlay is one reachable command that answers nothing")
    func hidingIsReachableAndAnswersNothing() throws {
        let hide = try #require(registry.action(id: "nudge.hideOverlays"))
        #expect(hide.shortcut != nil)
        #expect(hide.placement == .view)
        #expect(hide.effect == .priority(.hideOverlays))
        #expect(!PriorityCommand.hideOverlays.opensCockpit)
    }

    // MARK: - e05: what VoiceOver hears (F-144, F-146)

    /// A nudge that appeared silently for a VoiceOver user would be a visual event they never
    /// learn about — the same failure "differentiate without colour" exists to prevent, at the
    /// other end of the same problem. Both panels announce, and both announce **what they
    /// actually draw** rather than a category like "dialog".
    @Test(
        "both nudge panels announce the words they draw",
        .enabled(if: LocalizationLane.catalogsAreCompiled)
    )
    func panelsAnnounceTheirOwnWords() {
        let accusation = AccusationPresentation(
            rung: .panel,
            task: "Write the Q3 proposal",
            subject: AccusationFixture.safari,
            dwelled: .seconds(600),
            returnTarget: "Pages",
            hasOpenSession: true
        ).announcement()
        #expect(!accusation.isEmpty)
        #expect(accusation.contains("Write the Q3 proposal"))
        // **What VoiceOver hears is what the panel draws** — a name (focus-ebv). These two lines
        // pinned the bundle identifier, which is how the defect survived: the accusation spoke
        // *"You've been in com.apple.Safari for 10 minutes"* and the suite agreed.
        #expect(accusation.contains(AccusationFixture.safari.displayName))
        #expect(!accusation.contains(AccusationFixture.safari.identifier))

        let question = QueryPresentation(
            task: "Write the Q3 proposal",
            subject: QueryFixture.figma,
            reason: .noNegativeBasis,
            dwelled: .seconds(90)
        ).announcement()
        #expect(!question.isEmpty)
        #expect(question.contains(QueryFixture.figma.displayName))
        #expect(!question.contains(QueryFixture.figma.identifier))
        // The scope is spoken **before** the answer, exactly as it is drawn.
        #expect(question.contains(NudgeCopy.string(voice: .standard, .queryPanelScopeApp)))
    }

    /// The ambient rung is a silent surface for somebody who can see it. For somebody who
    /// cannot, silence would mean the rung never happened — so the menu bar's spoken label
    /// always carries the state's name, whatever the "differentiate without colour" setting
    /// says, because that preference is about the *visual* channel.
    @Test(
        "the menu bar always has a spoken label, in every state",
        .enabled(if: LocalizationLane.catalogsAreCompiled),
        arguments: FocusStatus.allCases
    )
    func menuBarAlwaysSpeaksItsState(status: FocusStatus) {
        for differentiate in [false, true] {
            let label = MenuBarController.accessibilityLabel(
                MenuBarPresentation(
                    status: status,
                    elapsed: .seconds(600),
                    differentiateWithoutColor: differentiate
                )
            )
            #expect(label.contains(status.shortLabel))
            #expect(!label.isEmpty)
        }
    }

    // MARK: - The traversal model

    @Test("every surface has a focus contract")
    func everySurfaceHasAContract() {
        #expect(FocusTraversal.surfaces.count == FocusSurface.allCases.count)
        for surface in FocusSurface.allCases {
            #expect(FocusTraversal.contract(for: surface).surface == surface)
        }
    }

    @Test("no field is unreachable: each appears in exactly one surface order")
    func everyFieldIsPlacedExactlyOnce() {
        for field in FocusField.allCases {
            let containing = FocusTraversal.surfaces.filter { $0.order.contains(field) }
            #expect(containing.count == 1, "\(field.rawValue) is placed \(containing.count) time(s)")
            #expect(FocusTraversal.surface(of: field) != nil)
        }
    }

    @Test("each surface's order is a total order with no repeats and no empty surface")
    func ordersAreTotalOrders() {
        for contract in FocusTraversal.surfaces {
            #expect(!contract.order.isEmpty, "\(contract.surface.rawValue) has no focusable field")
            #expect(Set(contract.order).count == contract.order.count)
        }
    }

    @Test("Tab walks every field once and then stops — no cycles")
    func traversalTerminatesAndCoversEveryField() {
        for contract in FocusTraversal.surfaces {
            var visited: [FocusField] = []
            var cursor = FocusTraversal.firstField(in: contract.surface)

            // Bounded by the order's length: if `next` ever cycled, this loop would exceed
            // it and the count assertion below would fail rather than hanging.
            var steps = 0
            while let field = cursor, steps <= contract.order.count {
                visited.append(field)
                cursor = FocusTraversal.next(after: field, in: contract.surface)
                steps += 1
            }

            #expect(visited == contract.order)
            #expect(cursor == nil)
        }
    }

    @Test("Shift-Tab is the same order, reversed")
    func previousIsTheInverseOfNext() {
        for contract in FocusTraversal.surfaces {
            for field in contract.order {
                if let next = FocusTraversal.next(after: field, in: contract.surface) {
                    #expect(FocusTraversal.previous(before: next, in: contract.surface) == field)
                }
                if let previous = FocusTraversal.previous(before: field, in: contract.surface) {
                    #expect(FocusTraversal.next(after: previous, in: contract.surface) == field)
                }
            }
            #expect(FocusTraversal.previous(before: contract.order[0], in: contract.surface) == nil)
            #expect(
                FocusTraversal.next(after: contract.order[contract.order.count - 1], in: contract.surface) == nil
            )
        }
    }

    // MARK: - Return and Escape

    @Test("a surface's default field is one of its own fields")
    func defaultFieldBelongsToItsSurface() {
        for contract in FocusTraversal.surfaces {
            guard let defaultField = contract.defaultField else { continue }
            #expect(contract.order.contains(defaultField))
        }
    }

    @Test("Escape dismisses the Settings window and does nothing in the cockpit")
    func cancelBehaviourIsDeclaredPerSurface() {
        // The cockpit is the app's main window: it has no modal state to back out of, and
        // closing it on Escape would be a surprise rather than a convenience.
        #expect(FocusTraversal.contract(for: .cockpit).cancel == .none)
        #expect(FocusTraversal.contract(for: .settingsGeneral).cancel == .dismissWindow)
        #expect(FocusTraversal.contract(for: .settingsPrivacy).cancel == .dismissWindow)
        // The quick-capture panel is summoned over someone else's work: backing out of it
        // without saving anything must always be one key away.
        #expect(FocusTraversal.contract(for: .quickCapture).cancel == .dismissWindow)
        // A sheet always has a way out that changes nothing.
        #expect(FocusTraversal.contract(for: .completionSheet).cancel == .dismissWindow)
    }

    @Test("Return activates the primary action wherever a surface has one")
    func defaultActionsAreBound() {
        // The cockpit declares **no** default action. It is a non-modal window full of text
        // fields, and a window default button collects every Return no field claimed — so
        // "Return finishes the priority" is one stray keystroke away from typing. That is the
        // same rule `CommandRegistry` states when it binds Complete Priority to ⌃⌘⏎ rather
        // than ⌘⏎, and the cockpit now keeps it too.
        #expect(FocusTraversal.contract(for: .cockpit).defaultField == nil)
        #expect(FocusTraversal.contract(for: .settingsPrivacy).defaultField == .privacyRevealStore)
        // General settings has no primary action — a picker is not something Return
        // "confirms" — so it declares none rather than inventing one.
        #expect(FocusTraversal.contract(for: .settingsGeneral).defaultField == nil)
    }

    @Test("the e03 surfaces are reachable, in the order their columns read")
    func sessionAndSensingAreReachable() {
        let cockpit = FocusTraversal.contract(for: .cockpit)

        // The session sits directly under the timebox: both are about how the time is being
        // spent, and a person who has just chosen a box is one Tab from starting the session
        // that runs inside it.
        #expect(FocusTraversal.next(after: .cockpitTimebox, in: .cockpit) == .cockpitSessionPrimary)
        #expect(cockpit.order.contains(.cockpitSessionPrimary))

        // The footer, in the order it reads: what is being watched, then the way out.
        #expect(
            FocusTraversal.next(after: .cockpitSensingPause, in: .cockpit) == .cockpitOpenSettings
        )
        #expect(FocusTraversal.previous(before: .cockpitOpenSettings, in: .cockpit) == .cockpitSensingPause)

        // One identity for the session control, not one per verb — the same rule the timebox
        // follows with its four presets. Which button carries it depends on the phase.
        #expect(cockpit.order.filter { $0 == .cockpitSessionPrimary }.count == 1)
    }

    @Test("the interruption sheet reaches the harmless button before the destructive one")
    func interruptionSheetOrderIsSafe() {
        let sheet = FocusTraversal.contract(for: .interruptionSheet)

        #expect(sheet.order == [.interruptReason, .interruptNote, .interruptCancel, .interruptConfirm])
        #expect(FocusTraversal.firstField(in: .interruptionSheet) == .interruptReason)
        // Cancel before Stop, so Tab reaches the one that changes nothing first.
        #expect(
            FocusTraversal.next(after: .interruptNote, in: .interruptionSheet) == .interruptCancel
        )
        // A modal sheet the person opened on purpose is exactly where a default button belongs —
        // unlike the cockpit, which declares none because Return there commits a field.
        #expect(sheet.defaultField == .interruptConfirm)
        #expect(sheet.cancel == .dismissWindow)
    }

    @Test("the cockpit and both Settings tabs each have a focusable element")
    func everyShellSurfaceIsReachable() {
        // The ritual banner sits above everything else while it is shown, so it comes first
        // in the order. The hero is the top of the column under it, so correcting the
        // priority's own wording in place comes next; the capture field — which starts a
        // *new* commitment rather than fixing the current one — follows, and is where focus
        // lands on an ordinary day when neither the banner nor the editor is up.
        #expect(FocusTraversal.firstField(in: .cockpit) == .cockpitRitualDismiss)
        #expect(
            FocusTraversal.next(after: .cockpitRitualDismiss, in: .cockpit) == .cockpitEditIntent
        )
        #expect(
            FocusTraversal.next(after: .cockpitEditIntent, in: .cockpit) == .cockpitCaptureField
        )
        #expect(FocusTraversal.firstField(in: .quickCapture) == .quickCaptureField)
        #expect(FocusTraversal.firstField(in: .completionSheet) == .completionShipped)
        #expect(FocusTraversal.firstField(in: .settingsGeneral) == .generalAppearancePicker)
        #expect(FocusTraversal.firstField(in: .settingsPrivacy) == .privacyRevealStore)
    }
}
