import Foundation

/// The verbs `focus://` understands. Exactly one, and an allowlist rather than a switch with a
/// default, so adding a second is a deliberate act.
public enum HandoffVerb: String, Sendable, CaseIterable, Hashable {
    /// `focus://start?task=…&doneWhen=…`
    case start
}

/// Something the confirm surface must tell the user about what arrived.
///
/// A flag is never a rejection. The request still goes to the confirmation sheet; the flag is
/// what lets the sheet say "this was 5,000 characters and I kept the first 500" instead of
/// quietly showing a truncated sentence as though it were what the script sent.
public enum HandoffFlag: Sendable, Equatable, Hashable {
    /// The task was longer than the field cap and was cut. Carries the original length.
    case taskTruncated(originalLength: Int)
    /// The definition of done was longer than the field cap and was cut.
    case doneWhenTruncated(originalLength: Int)
    /// Control or format characters — NUL included — were removed from at least one value.
    case controlCharactersStripped
    /// A key appeared more than once. The first occurrence won; these are the names.
    case duplicateKeysIgnored([String])
    /// Query items this build does not understand, named so the sheet can list them.
    case unknownQueryItems([String])
}

/// Why a URL produced no request at all.
///
/// These are the plan's `.scheme`, `.unknownVerb` and `.tooLong`, plus the empty-task case that
/// the hostile corpus requires an answer for.
public enum HandoffRejection: Sendable, Equatable, Hashable {
    /// Not a `focus://` URL.
    case scheme
    /// A `focus://` URL whose verb this build does not know. Carries the verb, so the surface
    /// can name it and say which verbs do exist.
    case unknownVerb(String)
    /// Longer than the whole-URL cap, rejected before anything was decoded.
    case tooLong
    /// No task, or a task that was only whitespace once the control characters were gone.
    case missingTask
}

/// What a `focus://` URL asked for — **and nothing the app may act on without a person.**
public enum HandoffParse: Sendable, Equatable, Hashable {
    /// Show the confirmation sheet. This is the *only* non-rejection outcome, by construction:
    /// there is no case here that means "do it".
    case confirm(HandoffRequest)
    case rejected(HandoffRejection)

    public var request: HandoffRequest? {
        if case .confirm(let request) = self { return request }
        return nil
    }

    public var rejection: HandoffRejection? {
        if case .rejected(let rejection) = self { return rejection }
        return nil
    }
}

/// An incoming handoff, parsed and bounded.
///
/// ## The binding condition
///
/// **External input lands on a confirm surface and never silently replaces the priority**
/// (F-142). That is enforced by this type's shape as much as by any code path: `parse` returns
/// a `HandoffParse`, whose only non-rejection case is `.confirm`, and nothing here touches a
/// store. There is no route from `.onOpenURL` to a mutation that does not pass through a
/// person pressing Replace.
///
/// ## Why the parser owns every bound
///
/// Probe P-61 fed the real app a hostile corpus through the real `.onOpenURL` path and
/// measured that **all of it arrives verbatim**: a 5,019-character URL, a NUL byte inside a
/// decoded value, duplicate keys in order, unknown hosts, `✓`, `/`, `?` and `#` inside values,
/// and a `%ZZ` mis-escape. Nothing upstream sanitises anything. So the caps, the control
/// stripping, the first-wins rule and the verb allowlist all live here — in a **pure
/// function**, which is what makes the hostile-input suite a table test rather than an
/// integration test.
public struct HandoffRequest: Sendable, Equatable, Hashable {
    public let verb: HandoffVerb
    /// The intent, control-stripped, trimmed and capped. Never empty.
    public let task: String
    /// The optional definition of done, under the same treatment.
    public let doneWhen: String?
    /// Everything the confirm surface has to disclose about how this was bounded.
    public let flags: [HandoffFlag]

    public init(verb: HandoffVerb, task: String, doneWhen: String?, flags: [HandoffFlag]) {
        self.verb = verb
        self.task = task
        self.doneWhen = doneWhen
        self.flags = flags
    }

    // MARK: - Bounds

    /// The scheme, exactly. Registry F-142 standardised it as `focus://`.
    public static let scheme = "focus"
    /// The whole URL, before anything is decoded.
    public static let maximumURLLength = 4_096
    /// Each field, after decoding.
    public static let maximumFieldLength = 500
    /// The query keys this build understands. Anything else is ignored *and named*.
    public static let knownQueryKeys = ["task", "doneWhen"]

    // MARK: - The parse

    /// Parse a URL. Pure: no clock, no store, no side effect, no I/O.
    public static func parse(_ url: URL) -> HandoffParse {
        guard url.scheme?.lowercased() == scheme else { return .rejected(.scheme) }

        let host = url.host(percentEncoded: false) ?? ""
        guard let verb = HandoffVerb(rawValue: host.lowercased()) else {
            return .rejected(.unknownVerb(host))
        }

        // Before any decoding, per R-23: a URL this long is refused on sight rather than
        // percent-decoded into memory first.
        guard url.absoluteString.count <= maximumURLLength else { return .rejected(.tooLong) }

        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []

        var firstValues: [String: String] = [:]
        var duplicateKeys: [String] = []
        var unknownKeys: [String] = []

        for item in items {
            if !knownQueryKeys.contains(item.name) {
                if !unknownKeys.contains(item.name) { unknownKeys.append(item.name) }
                continue
            }
            if firstValues[item.name] != nil {
                // First occurrence wins. Measured: `task=x&task=y` arrives as two items in
                // order, so "which one did you mean" is a real question and the answer is
                // "the first, and I will tell you I ignored the other".
                if !duplicateKeys.contains(item.name) { duplicateKeys.append(item.name) }
                continue
            }
            firstValues[item.name] = item.value ?? ""
        }

        var strippedAnything = false
        var flags: [HandoffFlag] = []

        let rawTask = firstValues["task"] ?? ""
        let cleanedTask = stripControlCharacters(rawTask, didStrip: &strippedAnything)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedTask.isEmpty else { return .rejected(.missingTask) }

        let task = capped(cleanedTask)
        if task.count < cleanedTask.count {
            flags.append(.taskTruncated(originalLength: cleanedTask.count))
        }

        var doneWhen: String?
        if let rawDoneWhen = firstValues["doneWhen"] {
            let cleaned = stripControlCharacters(rawDoneWhen, didStrip: &strippedAnything)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleaned.isEmpty {
                let capped = capped(cleaned)
                if capped.count < cleaned.count {
                    flags.append(.doneWhenTruncated(originalLength: cleaned.count))
                }
                doneWhen = capped
            }
        }

        // A fixed flag order, so the confirm surface reads the same way twice.
        if strippedAnything { flags.append(.controlCharactersStripped) }
        if !duplicateKeys.isEmpty { flags.append(.duplicateKeysIgnored(duplicateKeys)) }
        if !unknownKeys.isEmpty { flags.append(.unknownQueryItems(unknownKeys)) }

        return .confirm(
            HandoffRequest(verb: verb, task: task, doneWhen: doneWhen, flags: flags)
        )
    }

    /// Parse text that has not been through `URL` yet. Text `URL` will not accept is not a
    /// `focus://` URL, which is the same answer by a shorter route.
    public static func parse(_ string: String) -> HandoffParse {
        guard string.count <= maximumURLLength else { return .rejected(.tooLong) }
        guard let url = URL(string: string) else { return .rejected(.scheme) }
        return parse(url)
    }

    // MARK: - Bounding, one rule each

    /// Remove every scalar in `Cc` or `Cf` — NUL, the C0 and C1 ranges, and the invisible
    /// formatting characters that make two different strings look identical.
    private static func stripControlCharacters(
        _ text: String,
        didStrip: inout Bool
    ) -> String {
        var scalars = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            if CharacterSet.controlCharacters.contains(scalar) {
                didStrip = true
            } else {
                scalars.append(scalar)
            }
        }
        return String(scalars)
    }

    /// Cut to the field cap, counting Characters — a grapheme, not a byte, is what a person
    /// typed.
    private static func capped(_ text: String) -> String {
        text.count > maximumFieldLength ? String(text.prefix(maximumFieldLength)) : text
    }
}
