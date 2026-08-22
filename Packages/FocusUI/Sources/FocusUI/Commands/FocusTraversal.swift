import SwiftUI

/// A surface the user can be focused inside.
///
/// One per window or settings pane, because Tab moves within a surface and the order that
/// makes sense in the cockpit has nothing to say about the order inside a Settings tab.
public enum FocusSurface: String, Sendable, CaseIterable, Hashable, Identifiable {
    case cockpit
    /// The global quick-capture panel, summoned by the hot key from anywhere on the Mac.
    case quickCapture
    case settingsGeneral
    case settingsPrivacy

    public var id: String { rawValue }
}

/// Every element in the shell that can hold keyboard focus.
///
/// Only genuinely interactive elements are here. A heading, a status badge or a selectable
/// path is not in the Tab order because AppKit does not put static text there and pretending
/// otherwise would make the traversal model a fiction. The test asserts that every case
/// declared here appears in exactly one surface's order — so a field that is added and never
/// placed is a failure, not an invisible dead end.
public enum FocusField: String, Sendable, CaseIterable, Hashable, Identifiable {
    /// The cockpit's capture field, where the one thing is typed.
    case cockpitCaptureField
    /// The cockpit's Set Priority button.
    case cockpitSetPriority
    /// The definition-of-done field, directly under the priority hero.
    case cockpitDoneWhen
    /// The field that adds a keyword to the context pack.
    case cockpitContextKeyword
    /// The button that opens the file importer for the context pack.
    case cockpitContextAddFiles
    /// The cockpit's primary action: finish the current priority.
    case cockpitComplete
    /// The cockpit's route to Settings.
    case cockpitOpenSettings
    /// The appearance preference picker in General settings.
    case generalAppearancePicker
    /// The "Reveal Data Store in Finder" button in Privacy settings.
    case privacyRevealStore
    /// The quick-capture panel's field and its Set Priority button. Separate cases from the
    /// cockpit's, because the panel is its own surface with its own Tab order and its own
    /// Escape behaviour.
    case quickCaptureField
    case quickCaptureSet

    public var id: String { rawValue }
}

/// What Escape does in a surface.
public enum CancelBehaviour: String, Sendable, Equatable, Hashable {
    /// Escape closes the window. What a Settings window does.
    case dismissWindow
    /// Escape does nothing. The cockpit is the app's main window and has no modal state to
    /// back out of; closing it on Escape would be a surprise, not a convenience.
    case none
}

/// The focus contract for one surface: the Tab order, what Return activates, and what
/// Escape does.
public struct SurfaceFocus: Sendable, Equatable, Hashable {
    public let surface: FocusSurface
    /// The Tab order, first to last. Shift-Tab is this order reversed.
    public let order: [FocusField]
    /// The field Return activates, or `nil` where the surface has no default action.
    public let defaultField: FocusField?
    public let cancel: CancelBehaviour
}

/// Keyboard reachability, as a table.
///
/// F-145 asks that every shell action be reachable from the keyboard. Half of that is the
/// command registry — an action with a key equivalent is reachable from anywhere. The other
/// half is this: the elements that are *not* menu actions must still be reachable by Tab,
/// in an order someone can predict, with Return and Escape bound where the surface has
/// something for them to do.
///
/// The runtime half is grant-free too: the self-check hands synthesised key events to
/// `NSApp.mainMenu` and reports which equivalents were claimed. Full Keyboard Access
/// behaviour is confirmed by eye in the live frames — evidence, never the gate.
public enum FocusTraversal {
    /// The focus contract for every surface, in the order a user meets them.
    public static let surfaces: [SurfaceFocus] = [
        SurfaceFocus(
            surface: .cockpit,
            // Top to bottom, in the order the column reads: the definition of done sits
            // under the hero, the primary action under that, and the route to Settings last.
            order: [
                .cockpitCaptureField,
                .cockpitSetPriority,
                .cockpitDoneWhen,
                .cockpitContextKeyword,
                .cockpitContextAddFiles,
                .cockpitComplete,
                .cockpitOpenSettings
            ],
            defaultField: .cockpitComplete,
            cancel: .none
        ),
        SurfaceFocus(
            surface: .quickCapture,
            order: [.quickCaptureField, .quickCaptureSet],
            defaultField: .quickCaptureSet,
            // Escape closes the panel without saving. It is a transient surface summoned over
            // someone else's work, so backing out of it must be free.
            cancel: .dismissWindow
        ),
        SurfaceFocus(
            surface: .settingsGeneral,
            order: [.generalAppearancePicker],
            defaultField: nil,
            cancel: .dismissWindow
        ),
        SurfaceFocus(
            surface: .settingsPrivacy,
            order: [.privacyRevealStore],
            defaultField: .privacyRevealStore,
            cancel: .dismissWindow
        )
    ]

    public static func contract(for surface: FocusSurface) -> SurfaceFocus {
        // Every case is declared above, and a test asserts it: this is a programming error,
        // not a runtime condition.
        guard let contract = surfaces.first(where: { $0.surface == surface }) else {
            preconditionFailure("no focus contract declared for \(surface.rawValue)")
        }
        return contract
    }

    public static func order(in surface: FocusSurface) -> [FocusField] {
        contract(for: surface).order
    }

    /// Where focus starts in a surface.
    public static func firstField(in surface: FocusSurface) -> FocusField? {
        order(in: surface).first
    }

    /// The next field Tab moves to, or `nil` at the end of the order.
    ///
    /// Deliberately not wrapping. The *model* is a total order with a first and a last
    /// element, which is what makes "no cycles, no unreachable field" checkable; AppKit
    /// wraps at the window boundary at runtime, and that is its business, not the model's.
    public static func next(after field: FocusField, in surface: FocusSurface) -> FocusField? {
        let order = order(in: surface)
        guard let index = order.firstIndex(of: field), index + 1 < order.count else { return nil }
        return order[index + 1]
    }

    /// The previous field Shift-Tab moves to, or `nil` at the start of the order.
    public static func previous(before field: FocusField, in surface: FocusSurface) -> FocusField? {
        let order = order(in: surface)
        guard let index = order.firstIndex(of: field), index > 0 else { return nil }
        return order[index - 1]
    }

    /// Which surface a field belongs to.
    public static func surface(of field: FocusField) -> FocusSurface? {
        surfaces.first { $0.order.contains(field) }?.surface
    }
}
