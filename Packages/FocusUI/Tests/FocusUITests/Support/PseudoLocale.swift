import Foundation

@testable import FocusUI

/// Pseudo-localisation: the sanctioned substitute for a translation the programme does not
/// have.
///
/// Translation itself is parked — there is no translator in the loop, and asserting against
/// a fabricated `fr` translation would prove nothing except that someone invented French.
/// What *can* be proved is that the shell survives the thing translation actually does to a
/// layout: strings get longer, and characters stop being ASCII.
///
/// The transform is deterministic — same input, same output, every run — because it feeds
/// the snapshot lane, and a snapshot with a random component is a flaky test with extra
/// steps.
enum PseudoLocale {
    /// The delimiters. A string that has been through the transform is unmistakable in a
    /// render, and a *clipped* one is unmistakable too: the closing bracket is missing.
    static let opening = "⟦"
    static let closing = "⟧"

    /// Roughly the expansion German or Finnish inflicts on English UI text.
    static let expansionFactor = 2.0

    /// The one transform, wired into the shell's own text seam so that pseudo-localisation
    /// is a property of the shipping views rather than of a test-only copy of them.
    static let transform = ShellStringTransform(name: "pseudo") { expand($0) }

    /// Accent every letter and pad to about twice the original length.
    static func expand(_ string: String) -> String {
        guard !string.isEmpty else { return string }

        let accented = String(string.map(accent))
        let target = Int((Double(string.count) * expansionFactor).rounded())
        // Two of the budget go to the delimiters; the rest is padding, appended as a run of
        // middle dots so the padding cannot be mistaken for content.
        let padding = max(0, target - accented.count - 2)

        return opening + accented + String(repeating: "·", count: padding) + closing
    }

    /// A stable, per-character substitution. Letters only: punctuation, digits and the ⌘
    /// glyphs are left alone so a shortcut column stays readable.
    private static func accent(_ character: Character) -> Character {
        switch character {
        case "a": "á"; case "b": "ƀ"; case "c": "ć"; case "d": "đ"; case "e": "é"
        case "f": "ƒ"; case "g": "ǧ"; case "h": "ĥ"; case "i": "í"; case "j": "ĵ"
        case "k": "ķ"; case "l": "ļ"; case "m": "ɱ"; case "n": "ñ"; case "o": "ö"
        case "p": "þ"; case "q": "ɋ"; case "r": "ŕ"; case "s": "š"; case "t": "ť"
        case "u": "ú"; case "v": "ṽ"; case "w": "ŵ"; case "x": "ẋ"; case "y": "ý"
        case "z": "ž"
        case "A": "Á"; case "B": "Ɓ"; case "C": "Ć"; case "D": "Đ"; case "E": "É"
        case "F": "Ƒ"; case "G": "Ǧ"; case "H": "Ĥ"; case "I": "Í"; case "J": "Ĵ"
        case "K": "Ķ"; case "L": "Ļ"; case "M": "Ṁ"; case "N": "Ñ"; case "O": "Ö"
        case "P": "Þ"; case "Q": "Ɋ"; case "R": "Ŕ"; case "S": "Š"; case "T": "Ť"
        case "U": "Ú"; case "V": "Ṽ"; case "W": "Ŵ"; case "X": "Ẋ"; case "Y": "Ý"
        case "Z": "Ž"
        default: character
        }
    }
}
