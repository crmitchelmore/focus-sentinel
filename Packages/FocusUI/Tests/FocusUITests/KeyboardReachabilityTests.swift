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

    @Test("every action carries a discoverable key equivalent in e01")
    func everyActionIsBound() {
        // Per the Court's ruling not every action needs a shortcut — but both of e01's do,
        // and losing one would be a regression rather than a design change.
        #expect(registry.actions.allSatisfy { $0.shortcut != nil })
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
    }

    @Test("Return activates the primary action wherever a surface has one")
    func defaultActionsAreBound() {
        #expect(FocusTraversal.contract(for: .cockpit).defaultField == .cockpitOpenSettings)
        #expect(FocusTraversal.contract(for: .settingsPrivacy).defaultField == .privacyRevealStore)
        // General settings has no primary action — a picker is not something Return
        // "confirms" — so it declares none rather than inventing one.
        #expect(FocusTraversal.contract(for: .settingsGeneral).defaultField == nil)
    }

    @Test("the cockpit and both Settings tabs each have a focusable element")
    func everyShellSurfaceIsReachable() {
        #expect(FocusTraversal.firstField(in: .cockpit) == .cockpitOpenSettings)
        #expect(FocusTraversal.firstField(in: .settingsGeneral) == .generalAppearancePicker)
        #expect(FocusTraversal.firstField(in: .settingsPrivacy) == .privacyRevealStore)
    }
}
