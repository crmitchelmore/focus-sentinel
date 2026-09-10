import Foundation

/// The modifier keys a global hot key may carry.
///
/// The raw values are `NSEvent.ModifierFlags`' raw values, because that is what the settings
/// row stores (`AppSettingsRecord.hotKeyModifierFlags`) and what a shortcut recorder built on
/// AppKit will hand over. `FocusCore` may not import AppKit — the numbers are therefore
/// written out here, once, with the shift counts visible — and `FocusSensing`'s registrar
/// translates them into the Carbon mask `RegisterEventHotKey` wants.
public struct HotKeyModifiers: OptionSet, Sendable, Hashable, Codable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let capsLock = HotKeyModifiers(rawValue: 1 << 16)
    public static let shift = HotKeyModifiers(rawValue: 1 << 17)
    public static let control = HotKeyModifiers(rawValue: 1 << 18)
    public static let option = HotKeyModifiers(rawValue: 1 << 19)
    public static let command = HotKeyModifiers(rawValue: 1 << 20)
    public static let function = HotKeyModifiers(rawValue: 1 << 23)

    /// The four modifiers a Carbon hot key can actually be registered with.
    ///
    /// Caps Lock and Fn are deliberately not among them: neither can take part in a
    /// `RegisterEventHotKey` mask, and a recorder that let a user "choose" Caps Lock would be
    /// offering a shortcut that can never fire.
    public static let registrable: HotKeyModifiers = [.shift, .control, .option, .command]

    /// This combination with everything unregistrable removed. Every decision below is made
    /// on this value, so a stray Caps Lock bit in a stored integer cannot turn a refused
    /// shortcut into an accepted one, or the reverse.
    public var significant: HotKeyModifiers {
        intersection(.registrable)
    }
}

/// A system-owned key equivalent, named so the refusal can be explained rather than silent.
///
/// The cases are typed tokens, not prose: `FocusCore` owns no user-visible text beyond its
/// `undo.*` action names, and the capture settings tab draws these through its own catalog
/// keys (R-29).
public enum SystemShortcutFunction: String, Sendable, CaseIterable, Codable, Hashable {
    /// ⌘Space — Spotlight.
    case spotlight
    /// ⌃Space — select the previous input source.
    case previousInputSource
    /// ⌘Tab — the application switcher.
    case applicationSwitcher
    /// ⌘Q — quit the frontmost application.
    case quitApplication
    /// ⌘W — close the frontmost window. It belongs to the app, but not as a *global* key.
    case closeWindow
    /// ⌘H — hide the frontmost application.
    case hideApplication
    /// ⌘M — minimise the frontmost window.
    case minimiseWindow
    /// ⌘, — open the frontmost application's settings.
    case applicationSettings
}

/// Why a shortcut was turned down before the API was ever called.
public enum HotKeyRefusal: Sendable, Equatable, Hashable, Codable {
    /// A bare key with no modifier would swallow that key everywhere on the Mac.
    case noModifier
    /// Shift alone is not a modifier for this purpose: ⇧A is a capital A.
    case shiftOnly
    /// The system already owns this combination, and owns it invisibly — probe P-55 measured
    /// that `RegisterEventHotKey` accepts ⌘Space, reports `noErr`, and simply takes the key
    /// away from Spotlight. The API will not refuse for us, so we refuse for ourselves.
    case systemReserved(function: SystemShortcutFunction)
    /// The key code is outside the range Carbon accepts, or names a key this app cannot draw
    /// — a media or modifier key. A shortcut that cannot be shown to the user cannot be
    /// explained to them either, and R-21 requires every refusal to be explicable.
    case unsupportedKeyCode
    /// There is no hot-key implementation wired up in this build. `NullHotKeyRegistrar`
    /// returns this rather than pretending to have registered anything.
    case registrarUnavailable
}

/// A global hot key, as two integers plus the rules about them.
///
/// The two integers are exactly what `AppSettingsRecord` stores, so the type round-trips
/// through the database without a transformation step that could quietly change meaning.
public struct HotKeySpec: Sendable, Equatable, Hashable, Codable {
    /// The virtual key code — the same numbering Carbon's `kVK_*` constants use. 49 is Space.
    public let keyCode: Int
    /// `NSEvent.ModifierFlags` raw values, as stored.
    public let modifierFlags: Int

    public init(keyCode: Int, modifierFlags: Int) {
        self.keyCode = keyCode
        self.modifierFlags = modifierFlags
    }

    public init(keyCode: Int, modifiers: HotKeyModifiers) {
        self.init(keyCode: keyCode, modifierFlags: modifiers.rawValue)
    }

    public var modifiers: HotKeyModifiers {
        HotKeyModifiers(rawValue: modifierFlags)
    }

    /// The quick-capture default: ⌃⌥⌘Space.
    ///
    /// Not ⌘Space, and the reason is measured rather than tasteful (P-55): the API hands
    /// Spotlight's combination over without complaint, so an app whose *default* was ⌘Space
    /// would steal a system shortcut on first launch from every user who never opened
    /// Settings.
    public static let quickCaptureDefault = HotKeySpec(
        keyCode: FocusSchemaV3.defaultHotKeyKeyCode,
        modifierFlags: FocusSchemaV3.defaultHotKeyModifierFlags
    )

    /// **The quick-capture combinations this app offers**, the default first (focus-d3g).
    ///
    /// A committed list rather than a key-capture recorder, and the reason is what the defect
    /// actually was: P-55 measured that `RegisterEventHotKey` hands over a combination another
    /// application already owns without complaint, so somebody whose Mac binds the default had
    /// **no route to a different one**. A list of four closes that. A recorder would close it
    /// more elegantly and is a different piece of work — a key-capture control, its escape
    /// behaviour, its own accessibility story — none of which the person with a clashing default
    /// needs in order to be unstuck.
    ///
    /// Every entry is `isRegistrable` and `HotKeySpecTests` asserts it over the whole list, so a
    /// fifth added by hand cannot ship as an option the platform will take and not bind.
    /// ⌃⌥⌘ throughout, because that is the family the default is in and a person changing the
    /// key should not also have to relearn the modifiers.
    public static let quickCaptureChoices: [HotKeySpec] = [
        .quickCaptureDefault,
        HotKeySpec(keyCode: VirtualKey.f, modifiers: [.control, .option, .command]),
        HotKeySpec(keyCode: VirtualKey.j, modifiers: [.control, .option, .command]),
        HotKeySpec(keyCode: VirtualKey.k, modifiers: [.control, .option, .command])
    ]

    // MARK: - The refusal list

    /// Combinations the recorder turns down outright, with the system function each one
    /// belongs to.
    ///
    /// This is e01's `systemReservedShortcuts` plus the two Space bindings the system owns,
    /// expressed in virtual key codes because a global hot key is registered by key code and
    /// not by character.
    public struct ReservedCombination: Sendable, Equatable, Hashable {
        public let keyCode: Int
        public let modifiers: HotKeyModifiers
        public let function: SystemShortcutFunction

        public init(keyCode: Int, modifiers: HotKeyModifiers, function: SystemShortcutFunction) {
            self.keyCode = keyCode
            self.modifiers = modifiers
            self.function = function
        }

        /// The combination as a spec, so a test can feed the list straight back through
        /// `refusal` instead of rebuilding each case by hand.
        public var spec: HotKeySpec {
            HotKeySpec(keyCode: keyCode, modifiers: modifiers)
        }
    }

    public static let reservedCombinations: [ReservedCombination] = [
        ReservedCombination(keyCode: VirtualKey.space, modifiers: .command, function: .spotlight),
        ReservedCombination(
            keyCode: VirtualKey.space, modifiers: .control, function: .previousInputSource
        ),
        ReservedCombination(
            keyCode: VirtualKey.tab, modifiers: .command, function: .applicationSwitcher
        ),
        ReservedCombination(keyCode: VirtualKey.q, modifiers: .command, function: .quitApplication),
        ReservedCombination(keyCode: VirtualKey.w, modifiers: .command, function: .closeWindow),
        ReservedCombination(keyCode: VirtualKey.h, modifiers: .command, function: .hideApplication),
        ReservedCombination(keyCode: VirtualKey.m, modifiers: .command, function: .minimiseWindow),
        ReservedCombination(
            keyCode: VirtualKey.comma, modifiers: .command, function: .applicationSettings
        )
    ]

    /// Why this combination cannot be registered, or `nil` if it can.
    ///
    /// Every registrar consults this **before** calling the platform API, which is what makes
    /// the refusal list a property of the app rather than of one adapter.
    public var refusal: HotKeyRefusal? {
        let significant = modifiers.significant
        if significant.isEmpty { return .noModifier }
        if significant == .shift { return .shiftOnly }
        for combination in Self.reservedCombinations
        where combination.keyCode == keyCode && combination.modifiers == significant {
            return .systemReserved(function: combination.function)
        }
        if VirtualKey.label(for: keyCode) == nil { return .unsupportedKeyCode }
        return nil
    }

    public var isRegistrable: Bool { refusal == nil }

    // MARK: - Drawing

    /// How the shortcut is drawn — `⌃⌥⌘Space`, `⌘W`, `⌥⌘↩`.
    ///
    /// Modifier order is the Mac's own (Control, Option, Shift, Command) and the key glyphs
    /// follow the same conventions as `FocusUI.Shortcut.glyphs`, so a hot key and a menu key
    /// equivalent are drawn identically wherever they appear side by side.
    public var glyphs: String {
        var result = ""
        let significant = modifiers.significant
        if significant.contains(.control) { result += "⌃" }
        if significant.contains(.option) { result += "⌥" }
        if significant.contains(.shift) { result += "⇧" }
        if significant.contains(.command) { result += "⌘" }
        result += VirtualKey.label(for: keyCode) ?? ""
        return result
    }
}

/// Virtual key codes, and how each one is drawn.
///
/// The numbering is the Mac's own — the same values Carbon's `kVK_*` constants carry and the
/// same values `NSEvent.keyCode` reports — written out here because `FocusCore` may not import
/// Carbon (SC-2 permits it in exactly one file, and that file is a `FocusSensing` adapter).
public enum VirtualKey {
    public static let f = 3
    public static let h = 4
    public static let j = 38
    public static let k = 40
    public static let q = 12
    public static let w = 13
    public static let comma = 43
    public static let m = 46
    public static let tab = 48
    public static let space = 49

    /// The label a key is drawn with, or `nil` for a key this app will not accept — a media
    /// key, a modifier key, or a code outside the range Carbon uses at all.
    public static func label(for keyCode: Int) -> String? {
        labels[keyCode]
    }

    /// Every key the recorder accepts. A code absent from this table is refused rather than
    /// drawn as a number: `⌃⌥⌘?` explains nothing to the person trying to fix it.
    private static let labels: [Int: String] = [
        // ANSI letters, digits and punctuation.
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
        10: "§", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T",
        18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5", 24: "=", 25: "9", 26: "7",
        27: "-", 28: "8", 29: "0", 30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P",
        37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/", 45: "N",
        46: "M", 47: ".", 50: "`",
        // Editing and navigation, drawn the way the Mac draws them.
        36: "↩", 48: "⇥", 49: "Space", 51: "⌫", 53: "⎋",
        115: "↖", 116: "⇞", 117: "⌦", 119: "↘", 121: "⇟",
        123: "←", 124: "→", 125: "↓", 126: "↑",
        // The numeric keypad.
        65: ".", 67: "*", 69: "+", 71: "⌧", 75: "/", 76: "⌤", 78: "-", 81: "=",
        82: "0", 83: "1", 84: "2", 85: "3", 86: "4", 87: "5", 88: "6", 89: "7", 91: "8",
        92: "9",
        // Function keys.
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8",
        101: "F9", 109: "F10", 103: "F11", 111: "F12", 105: "F13", 107: "F14", 113: "F15",
        106: "F16", 64: "F17", 79: "F18", 80: "F19", 90: "F20"
    ]
}
