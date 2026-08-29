import Foundation

/// **A whole value, as one comparable line — derived, never enumerated** (focus-7ow).
///
/// ## Why this exists
///
/// Five rounds of this epic have written the proof to the known failure. `ShellRenderedField` had
/// a case for every value the eight-no-op mutant touched and for nothing else, so a residue mutant
/// could lie about `state.priority?.doneWhen`, about the contents of `state.recent`, and about
/// five of `InterventionSettings`' seven fields while the gate stayed green with an empty
/// ok-assertion diff. Every one of those was a field somebody would have had to *think of*.
///
/// A digest is the opposite instrument. It is `Mirror` over the whole value, so a field added to
/// `PrioritySnapshot` tomorrow is in the reported string tomorrow, with nobody editing anything.
/// Where `CapabilityMatrix.renderedDescription` is a hand-written whole-value line — and is right
/// to be, because the order and the spelling are load-bearing in a gate log — this is the general
/// case for every other struct a window draws.
///
/// ## What it is not
///
/// It is not a hash. A failing gate line has to say *what* differs, so the output is readable:
/// `(intent=write the report;doneWhen=none;…)`. It is not stable across releases either, and
/// nothing may persist it — it exists to be compared against itself, inside one process, between
/// the value the composition root handed a window and the value that window says it drew.
public enum ShellValueDigest {
    /// The whole value, rendered. `nil` is `"none"`, which is the same spelling every optional
    /// field in `ShellRenderedField` already uses.
    public static func describe(_ value: Any?) -> String {
        guard let value else { return "none" }
        return render(value, depth: 0)
    }

    /// Deep enough for every value in this repository, and bounded so a reference cycle in some
    /// future type cannot hang a window's layout pass.
    private static let maximumDepth = 8

    private static func render(_ value: Any, depth: Int) -> String {
        // The leaves, spelled the way a person reads them. Without this a `UUID` renders as
        // sixteen `UInt8` children and a gate line becomes unreadable.
        switch value {
        case let leaf as String: return leaf
        case let leaf as Bool: return leaf ? "true" : "false"
        case let leaf as UUID: return leaf.uuidString
        case let leaf as URL: return leaf.path(percentEncoded: false)
        case let leaf as Date: return String(Int(leaf.timeIntervalSinceReferenceDate))
        case let leaf as Double: return String(Int(leaf.rounded()))
        case let leaf as any BinaryInteger: return String(describing: leaf)
        default: break
        }

        guard depth < maximumDepth else { return "…" }
        let mirror = Mirror(reflecting: value)

        switch mirror.displayStyle {
        case .optional:
            guard let wrapped = mirror.children.first else { return "none" }
            return render(wrapped.value, depth: depth)

        case .collection, .set:
            // Sets are sorted so that two readings of one value are one string. Arrays are not:
            // the order of `state.recent` is what the window draws, and sorting it would hide a
            // list drawn backwards.
            let parts = mirror.children.map { render($0.value, depth: depth + 1) }
            return "[" + (mirror.displayStyle == .set ? parts.sorted() : parts).joined(separator: "|") + "]"

        case .dictionary:
            let parts = mirror.children.map { render($0.value, depth: depth + 1) }
            return "{" + parts.sorted().joined(separator: "|") + "}"

        case .enum:
            // A payload-free case has no children, and `String(describing:)` is its name. A case
            // with a payload gets the name plus the payload, so `.some(3)` and `.some(4)` differ.
            let name = String(describing: value)
            if mirror.children.isEmpty { return name }
            let parts = mirror.children.map { child in
                "\(child.label ?? "_"):\(render(child.value, depth: depth + 1))"
            }
            return name.prefix(while: { $0 != "(" }) + "(" + parts.joined(separator: ";") + ")"

        case .struct, .class, .tuple:
            if mirror.children.isEmpty { return String(describing: value) }
            let parts = mirror.children.map { child in
                "\(child.label ?? "_")=\(render(child.value, depth: depth + 1))"
            }
            return "(" + parts.joined(separator: ";") + ")"

        case .none:
            return String(describing: value)

        @unknown default:
            return String(describing: value)
        }
    }
}
