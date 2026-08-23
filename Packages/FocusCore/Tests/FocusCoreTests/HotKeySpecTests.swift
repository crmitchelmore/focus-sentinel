import Foundation
import Testing

@testable import FocusCore

@Suite("Hot-key specs, refusals and glyphs")
struct HotKeySpecTests {
    // MARK: - The default

    @Test("the shipped default is ⌃⌥⌘Space, and it is registrable")
    func theDefaultIsRegistrable() {
        let spec = HotKeySpec.quickCaptureDefault
        #expect(spec.keyCode == VirtualKey.space)
        #expect(spec.modifiers.significant == [.control, .option, .command])
        #expect(spec.refusal == nil)
        #expect(spec.isRegistrable)
        #expect(spec.glyphs == "⌃⌥⌘Space")
    }

    /// The default must equal what the settings row stores, or the first launch would
    /// re-register a different combination from the one the schema advertises.
    @Test("the default matches the stored schema default exactly")
    func theDefaultMatchesTheSchema() {
        #expect(HotKeySpec.quickCaptureDefault.keyCode == FocusSchemaV3.defaultHotKeyKeyCode)
        #expect(
            HotKeySpec.quickCaptureDefault.modifierFlags
                == FocusSchemaV3.defaultHotKeyModifierFlags
        )
    }

    // MARK: - The refusal list (R-21)

    @Test("every reserved combination is refused, and names the system function it collides with")
    func everyReservedCombinationIsRefused() {
        for combination in HotKeySpec.reservedCombinations {
            #expect(
                combination.spec.refusal == .systemReserved(function: combination.function),
                "\(combination.spec.glyphs) should be refused as \(combination.function.rawValue)"
            )
        }
    }

    /// The list the plan names, spelled out rather than derived, so that a change to the table
    /// has to be a deliberate change to this test too.
    @Test("the reserved set is exactly ⌘Space, ⌃Space, ⌘Tab, ⌘Q, ⌘W, ⌘H, ⌘M and ⌘,")
    func theReservedSetIsTheNamedOne() {
        let drawn = Set(HotKeySpec.reservedCombinations.map(\.spec.glyphs))
        #expect(drawn == ["⌘Space", "⌃Space", "⌘⇥", "⌘Q", "⌘W", "⌘H", "⌘M", "⌘,"])
        #expect(HotKeySpec.reservedCombinations.count == 8)
    }

    @Test("a bare key with no modifier is refused")
    func noModifierIsRefused() {
        #expect(HotKeySpec(keyCode: VirtualKey.space, modifiers: []).refusal == .noModifier)
        #expect(HotKeySpec(keyCode: 0, modifiers: []).refusal == .noModifier)
        // Caps Lock and Fn are not registrable modifiers, so a combination carrying only
        // those is still a bare key.
        #expect(HotKeySpec(keyCode: 0, modifiers: [.capsLock, .function]).refusal == .noModifier)
    }

    @Test("Shift alone is refused: ⇧A is a capital A, not a shortcut")
    func shiftOnlyIsRefused() {
        #expect(HotKeySpec(keyCode: 0, modifiers: .shift).refusal == .shiftOnly)
        #expect(HotKeySpec(keyCode: VirtualKey.space, modifiers: [.shift, .capsLock]).refusal
            == .shiftOnly)
    }

    @Test("adding a real modifier to Shift makes it registrable again")
    func shiftWithAnotherModifierIsAccepted() {
        #expect(HotKeySpec(keyCode: 0, modifiers: [.shift, .command]).refusal == nil)
        #expect(HotKeySpec(keyCode: 0, modifiers: [.shift, .command]).glyphs == "⇧⌘A")
    }

    /// Only the exact reserved combination is refused. ⌃⌥⌘Space — the shipped default — is a
    /// Space binding too, and refusing it would refuse the app's own shortcut.
    @Test("a reserved key with different modifiers is not itself reserved")
    func onlyTheExactCombinationIsReserved() {
        #expect(HotKeySpec(keyCode: VirtualKey.space, modifiers: .command).refusal != nil)
        #expect(
            HotKeySpec(keyCode: VirtualKey.space, modifiers: [.control, .option, .command])
                .refusal == nil
        )
        #expect(HotKeySpec(keyCode: VirtualKey.q, modifiers: [.option, .command]).refusal == nil)
    }

    /// Caps Lock cannot take part in a `RegisterEventHotKey` mask, so it must not be able to
    /// smuggle a reserved combination past the list either.
    @Test("an insignificant modifier cannot disguise a reserved combination")
    func capsLockCannotDisguiseAReservedCombination() {
        let spotlightWithCapsLock = HotKeySpec(
            keyCode: VirtualKey.space,
            modifiers: [.command, .capsLock]
        )
        #expect(spotlightWithCapsLock.refusal == .systemReserved(function: .spotlight))
    }

    @Test("a key code Carbon does not use, or this app cannot draw, is refused")
    func undrawableKeyCodesAreRefused() {
        // 63 is Fn, 72–74 are the volume keys: real key codes, but not shortcut keys.
        #expect(HotKeySpec(keyCode: 63, modifiers: .command).refusal == .unsupportedKeyCode)
        #expect(HotKeySpec(keyCode: 73, modifiers: .command).refusal == .unsupportedKeyCode)
        // Out of range entirely — the shape a corrupt or hand-edited settings row takes.
        #expect(HotKeySpec(keyCode: 9_999, modifiers: .command).refusal == .unsupportedKeyCode)
        #expect(HotKeySpec(keyCode: -1, modifiers: .command).refusal == .unsupportedKeyCode)
    }

    // MARK: - Glyphs (e01's Shortcut.glyphs conventions)

    @Test("glyphs are drawn in the Mac's modifier order: ⌃⌥⇧⌘")
    func modifierOrderIsTheMacsOwn() {
        let all = HotKeySpec(keyCode: VirtualKey.w, modifiers: [.command, .shift, .option, .control])
        #expect(all.glyphs == "⌃⌥⇧⌘W")
        #expect(HotKeySpec(keyCode: VirtualKey.w, modifiers: .command).glyphs == "⌘W")
        #expect(HotKeySpec(keyCode: VirtualKey.w, modifiers: [.command, .option]).glyphs == "⌥⌘W")
    }

    @Test("named keys are drawn the way the Mac draws them")
    func namedKeysAreDrawnTheMacWay() {
        #expect(HotKeySpec(keyCode: 49, modifiers: .command).glyphs == "⌘Space")
        #expect(HotKeySpec(keyCode: 48, modifiers: .option).glyphs == "⌥⇥")
        #expect(HotKeySpec(keyCode: 36, modifiers: .command).glyphs == "⌘↩")
        #expect(HotKeySpec(keyCode: 53, modifiers: .command).glyphs == "⌘⎋")
        #expect(HotKeySpec(keyCode: 51, modifiers: .command).glyphs == "⌘⌫")
        #expect(HotKeySpec(keyCode: 126, modifiers: .command).glyphs == "⌘↑")
        #expect(HotKeySpec(keyCode: 122, modifiers: .command).glyphs == "⌘F1")
    }

    /// e01's `Shortcut.glyphs` uppercases letters and leaves punctuation alone; the two
    /// renderers appear side by side in the shortcut reference, so they must agree.
    @Test("letters are uppercased and punctuation is left alone")
    func lettersAreUppercased() {
        #expect(HotKeySpec(keyCode: VirtualKey.comma, modifiers: .option).glyphs == "⌥,")
        #expect(HotKeySpec(keyCode: 44, modifiers: .command).glyphs == "⌘/")
        #expect(HotKeySpec(keyCode: 18, modifiers: .command).glyphs == "⌘1")
        #expect(HotKeySpec(keyCode: VirtualKey.m, modifiers: .option).glyphs == "⌥M")
    }

    @Test("every drawable key code produces a non-empty label, and no two names collide oddly")
    func everyDrawableKeyHasALabel() {
        // The table is a dictionary literal: a duplicated key would trap the first time it is
        // touched, so walking the whole Carbon key-code range is also how that is asserted.
        var labelled = 0
        for keyCode in 0...127 where VirtualKey.label(for: keyCode) != nil {
            #expect(VirtualKey.label(for: keyCode)?.isEmpty == false)
            labelled += 1
        }
        #expect(labelled > 60, "the recorder should accept most of the keyboard, not a handful")
        #expect(VirtualKey.label(for: 128) == nil)
    }

    // MARK: - Round-tripping through the stored integers

    @Test("a spec round-trips through the two integers AppSettingsRecord stores")
    func roundTripsThroughStoredIntegers() {
        let specs: [HotKeySpec] = [
            .quickCaptureDefault,
            HotKeySpec(keyCode: VirtualKey.q, modifiers: [.option, .command]),
            HotKeySpec(keyCode: 36, modifiers: [.control, .shift]),
            HotKeySpec(keyCode: 122, modifiers: .command)
        ]
        for spec in specs {
            let stored = (keyCode: spec.keyCode, modifierFlags: spec.modifierFlags)
            let restored = HotKeySpec(
                keyCode: stored.keyCode,
                modifierFlags: stored.modifierFlags
            )
            #expect(restored == spec)
            #expect(restored.glyphs == spec.glyphs)
            #expect(restored.refusal == spec.refusal)
        }
    }

    @Test("the modifier raw values are the AppKit ones the settings row stores")
    func modifierRawValuesAreTheAppKitOnes() {
        #expect(HotKeyModifiers.capsLock.rawValue == 1 << 16)
        #expect(HotKeyModifiers.shift.rawValue == 1 << 17)
        #expect(HotKeyModifiers.control.rawValue == 1 << 18)
        #expect(HotKeyModifiers.option.rawValue == 1 << 19)
        #expect(HotKeyModifiers.command.rawValue == 1 << 20)
        #expect(HotKeyModifiers.function.rawValue == 1 << 23)
        #expect(
            HotKeyModifiers.registrable.rawValue
                == (1 << 17) | (1 << 18) | (1 << 19) | (1 << 20)
        )
    }

    @Test("a spec is Codable, so a settings export cannot silently reshape it")
    func specIsCodable() throws {
        let encoded = try JSONEncoder().encode(HotKeySpec.quickCaptureDefault)
        let decoded = try JSONDecoder().decode(HotKeySpec.self, from: encoded)
        #expect(decoded == HotKeySpec.quickCaptureDefault)
    }

    // MARK: - The registration vocabulary

    @Test("a registration result reports whether the key is actually live")
    func registrationResultReportsLiveness() {
        #expect(HotKeyRegistration.registered.isRegistered)
        #expect(!HotKeyRegistration.alreadyRegistered.isRegistered)
        #expect(!HotKeyRegistration.refused(reason: .noModifier).isRegistered)
        #expect(!HotKeyRegistration.failed(status: -9878).isRegistered)
    }

    @Test("availability answers the question the settings tab asks")
    func availabilityIsReadable() {
        #expect(HotKeyAvailability.available.isAvailable)
        #expect(!HotKeyAvailability.unavailable(reason: .notImplemented).isAvailable)
        #expect(!HotKeyAvailability.unavailable(reason: .unsupportedOnThisMac).isAvailable)
    }
}
