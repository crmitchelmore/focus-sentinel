import SwiftUI

/// A surface the user can be focused inside.
///
/// One per window or settings pane, because Tab moves within a surface and the order that
/// makes sense in the cockpit has nothing to say about the order inside a Settings tab.
public enum FocusSurface: String, Sendable, CaseIterable, Hashable, Identifiable {
    case cockpit
    /// The global quick-capture panel, summoned by the hot key from anywhere on the Mac.
    case quickCapture
    /// The sheet that finishes a priority.
    case completionSheet
    /// The sheet an incoming focus:// handoff lands on.
    case handoffConfirm
    /// The sheet that stops a session and asks why (F-101).
    case interruptionSheet
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
    /// The daily ritual banner's dismissal, above everything else while it is shown.
    case cockpitRitualDismiss
    /// The priority's own sentence, being fixed in place. Distinct from the capture field:
    /// that one starts a new commitment, this one corrects the wording of the current.
    case cockpitEditIntent
    /// The cockpit's capture field, where the one thing is typed.
    case cockpitCaptureField
    /// The cockpit's Set Priority button.
    case cockpitSetPriority
    /// The definition-of-done field, directly under the priority hero.
    case cockpitDoneWhen
    /// The timebox control. One identity for the control, not one per preset button.
    case cockpitTimebox
    /// The field that adds a keyword to the context pack.
    case cockpitContextKeyword
    /// The button that opens the file importer for the context pack.
    case cockpitContextAddFiles
    /// The field that names what a new per-task rule is about.
    case cockpitRuleSubject
    /// The session's primary verb — Start, Pause or Resume, whichever the phase makes primary.
    ///
    /// **One identity for the control, not one per verb.** The traversal model names the session
    /// section; which button carries the identity depends on the phase the session is actually
    /// in, exactly as the timebox control names itself rather than each of its four presets.
    case cockpitSessionPrimary
    /// The cockpit's primary action: finish the current priority.
    case cockpitComplete
    /// F-119's switch, in the cockpit. The same stored value the menu item drives.
    case cockpitSensingPause
    /// The cockpit's route to Settings.
    case cockpitOpenSettings
    /// The appearance preference picker in General settings.
    case generalAppearancePicker
    /// The launch-at-login switch in General settings (D-12, focus-odz.4). A switch a person
    /// cannot reach from the keyboard is a switch somebody cannot turn on.
    case generalLaunchAtLogin
    /// The daily-ritual switch in General settings (focus-d3g). A switch a person cannot reach
    /// from the keyboard is a switch somebody cannot turn off.
    case generalRitualEnabled
    /// The quick-capture shortcut picker in General settings (focus-d3g).
    case generalQuickCaptureShortcut
    /// The "Reveal Data Store in Finder" button in Privacy settings.
    case privacyRevealStore
    /// The quick-capture panel's field and its Set Priority button. Separate cases from the
    /// cockpit's, because the panel is its own surface with its own Tab order and its own
    /// Escape behaviour.
    case quickCaptureField
    case quickCaptureSet
    /// The completion sheet's two optional reflection fields and its Complete button.
    case completionShipped
    case completionRestartPoint
    case completionConfirm
    /// The handoff sheet's two buttons — and there are only ever two.
    case handoffReplace
    case handoffCancel
    /// The interruption sheet: a reason, an optional note, and the two buttons. Every field is
    /// optional and the confirm button is enabled with all of them empty.
    case interruptReason
    case interruptNote
    case interruptConfirm
    case interruptCancel

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
                .cockpitRitualDismiss,
                // The hero is the top of the column, so editing it in place is the first
                // field under the banner and above the definition of done.
                .cockpitEditIntent,
                .cockpitDoneWhen,
                // The priority's own verbs sit directly under its definition of done (focus-6uya):
                // they act on the commitment, so they are reached before the machinery that
                // serves it rather than after the rules pane.
                .cockpitComplete,
                // Change Priority opens capture below the current commitment's verbs.
                .cockpitCaptureField,
                .cockpitSetPriority,
                .cockpitTimebox,
                // The session sits directly under the timebox: both are about how the time is
                // being spent, and a person who has just chosen a box is one Tab from starting
                // the session that runs inside it.
                .cockpitSessionPrimary,
                .cockpitContextKeyword,
                .cockpitContextAddFiles,
                .cockpitRuleSubject,
                // The footer, in the order it reads: what is being watched, then the way out to
                // Settings.
                .cockpitSensingPause,
                .cockpitOpenSettings
            ],
            // **No default action, deliberately.** The cockpit is a non-modal window full of
            // text fields, and Return is the key that commits the field you are in. A window
            // default button collects every Return that no field claimed — so making Complete
            // the default put finishing the work one stray keystroke away from typing, which
            // is the exact rule `CommandRegistry` gives for binding Complete Priority to ⌃⌘⏎
            // instead of ⌘⏎. Completion is reachable by click, by that key equivalent and by
            // the File menu; a modal sheet, which the user opened on purpose, is where a
            // default button belongs.
            defaultField: nil,
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
            surface: .completionSheet,
            order: [.completionShipped, .completionRestartPoint, .completionConfirm],
            defaultField: .completionConfirm,
            cancel: .dismissWindow
        ),
        SurfaceFocus(
            surface: .handoffConfirm,
            // Cancel first and Cancel by default: Return must never be the key that gives
            // away the priority the user was already working on.
            order: [.handoffCancel, .handoffReplace],
            defaultField: .handoffCancel,
            cancel: .dismissWindow
        ),
        SurfaceFocus(
            surface: .interruptionSheet,
            // The reason first, because it is the only field with a value already in it, then
            // the optional note, then the two buttons — cancel before confirm, so Tab reaches
            // the harmless one first.
            order: [.interruptReason, .interruptNote, .interruptCancel, .interruptConfirm],
            // Return stops the session. This is a modal sheet the person opened on purpose,
            // which is exactly where a default button belongs — unlike the cockpit, which
            // declares none.
            defaultField: .interruptConfirm,
            cancel: .dismissWindow
        ),
        SurfaceFocus(
            surface: .settingsGeneral,
            order: [
                .generalAppearancePicker, .generalLaunchAtLogin,
                .generalRitualEnabled, .generalQuickCaptureShortcut
            ],
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

    /// The focus contract for one surface.
    ///
    /// **A `switch` over the surfaces with no `default`, and that is the repair** (focus-tzj.7).
    /// This was a lookup in the array above with `preconditionFailure` for a miss, justified by
    /// a test asserting the array is total. What that bought was a **runtime crash** the day
    /// somebody adds a surface: the compiler said nothing, and the trap fired when a person
    /// opened the new window. Written as a fold, the missing row is a build error in this file.
    ///
    /// The array stays as the declaration — it is what `allSurfaces` and the totality test read,
    /// and it is the readable form of the contract — and this is the total function over it. The
    /// `first(where:)` cannot fail *because* the `switch` below has already named the surface, so
    /// the fallback is the surface's own empty contract rather than a trap: a window with no
    /// declared order is a window Tab does nothing in, which is a poor experience and not a
    /// crash.
    public static func contract(for surface: FocusSurface) -> SurfaceFocus {
        switch surface {
        case .cockpit, .quickCapture, .completionSheet, .handoffConfirm,
             .interruptionSheet, .settingsGeneral, .settingsPrivacy:
            surfaces.first { $0.surface == surface }
                ?? SurfaceFocus(surface: surface, order: [], defaultField: nil, cancel: .none)
        }
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
