import Foundation

/// The verbs `focus://` understands. An allowlist rather than a switch with a default, so adding
/// one is a deliberate act.
public enum HandoffVerb: String, Sendable, CaseIterable, Hashable {
    /// `focus://start?task=…&doneWhen=…&context=app:…` — replace the priority, optionally with
    /// a context pack.
    case start
    /// `focus://context?add=app:…&add=domain:…&add=keyword:…` — add to the **current**
    /// priority's context pack. Names no task, so it can never change which priority is current.
    case context
    /// `focus://priorities?primary=…&primaryDoneWhen=…&primaryContext=app:…&secondary1=…&…` —
    /// replace the standing shortlist: one main priority and up to two secondary ones. Never
    /// changes which priority is current; the cockpit offers them to pick from.
    case priorities
}

/// One standing slot a `priorities` handoff asks for, already bounded.
public struct HandoffStandingSlot: Sendable, Equatable, Hashable {
    /// 0 for the main priority, 1 and 2 for the secondary ones.
    public let slot: Int
    public let task: String
    public let doneWhen: String?
    /// Distinct, in arrival order, at most `HandoffRequest.maximumContextItemsPerSlot`.
    public let context: [HandoffContextItem]

    public init(slot: Int, task: String, doneWhen: String?, context: [HandoffContextItem] = []) {
        self.slot = slot
        self.task = task
        self.doneWhen = doneWhen
        self.context = context
    }

    /// The query-key prefix for each slot, in slot order.
    public static let keyPrefixes = ["primary", "secondary1", "secondary2"]
}

/// One context item a handoff asks for, already bounded and normalised.
///
/// Only the three kinds a URL can carry honestly: an app (a bundle identifier), a web origin and
/// a keyword. A `file` item needs a security-scoped bookmark made at the moment a person chose
/// the file, and a URL cannot be that moment, so `file:` is ignored and disclosed like any other
/// unreadable item.
public struct HandoffContextItem: Sendable, Equatable, Hashable {
    public let kind: ContextItemKind
    /// A bundle identifier, a `scheme://host[:port]` origin, or a lowercased keyword.
    public let value: String

    public init(kind: ContextItemKind, value: String) {
        self.kind = kind
        self.value = value
    }

    /// Longest bundle identifier accepted. Launch Services allows more; nobody ships one.
    public static let maximumBundleIDLength = 255

    /// Parse `app:<bundle id>`, `domain:<origin or host>` or `keyword:<text>`. `nil` for
    /// anything else, including a well-formed `file:`.
    public static func parse(_ text: String) -> HandoffContextItem? {
        guard let colon = text.firstIndex(of: ":") else { return nil }
        let kind = text[..<colon].lowercased()
        let rest = String(text[text.index(after: colon)...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        switch kind {
        case "app":
            let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-"))
            guard !rest.isEmpty, rest.count <= maximumBundleIDLength, rest.contains("."),
                  rest.unicodeScalars.allSatisfy({ $0.isASCII && allowed.contains($0) })
            else { return nil }
            return HandoffContextItem(kind: .app, value: rest)
        case "domain":
            // A bare host is read as https; only web origins are accepted, because a domain
            // item is matched against what a browser reports.
            let candidate = rest.contains("://") ? rest : "https://\(rest)"
            guard let origin = OriginNormalizer.normalize(candidate),
                  origin.hasPrefix("https://") || origin.hasPrefix("http://")
            else { return nil }
            return HandoffContextItem(kind: .domain, value: origin)
        case "keyword":
            let keyword = rest.lowercased()
            guard !keyword.isEmpty, keyword.count <= HandoffRequest.maximumFieldLength else {
                return nil
            }
            return HandoffContextItem(kind: .keyword, value: keyword)
        default:
            return nil
        }
    }
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
    /// Context items that could not be read, were of a kind a URL cannot carry, or came after
    /// the cap. Carries how many, not what: the sheet lists what it *will* add.
    case contextItemsIgnored(count: Int)
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
    /// A `context` verb with no readable item to add.
    case missingContext
    /// A `priorities` verb with no main priority.
    case missingPrimary
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
    /// The intent, control-stripped, trimmed and capped. Never empty for `.start`; always empty
    /// for `.context`, which names no task.
    public let task: String
    /// The optional definition of done, under the same treatment. Always `nil` for `.context`.
    public let doneWhen: String?
    /// Everything the confirm surface has to disclose about how this was bounded.
    public let flags: [HandoffFlag]
    /// Context items to add: to the new priority for `.start`, to the current one for
    /// `.context`. Distinct, in arrival order, at most `maximumContextItems`. Never empty for
    /// `.context`.
    public let context: [HandoffContextItem]
    /// The standing shortlist a `.priorities` handoff asks for, in slot order, the main one
    /// first. Always empty for the other verbs; never empty for `.priorities`.
    public let standing: [HandoffStandingSlot]

    public init(
        verb: HandoffVerb,
        task: String,
        doneWhen: String?,
        flags: [HandoffFlag],
        context: [HandoffContextItem] = [],
        standing: [HandoffStandingSlot] = []
    ) {
        self.verb = verb
        self.task = task
        self.doneWhen = doneWhen
        self.flags = flags
        self.context = context
        self.standing = standing
    }

    // MARK: - Bounds

    /// The scheme, exactly. Registry F-142 standardised it as `focus://`; since focus-h8jf it
    /// is the train's, so an Alpha build answers `focus-alpha://` and macOS routes a link to the
    /// train that made it. A process with no train metadata answers `focus`, as before.
    public static var scheme: String { ReleaseTrain.current.urlScheme }
    /// The whole URL, before anything is decoded.
    public static let maximumURLLength = 4_096
    /// Each field, after decoding.
    public static let maximumFieldLength = 500
    /// The query keys each verb understands. Anything else is ignored *and named*.
    public static let knownQueryKeys: [HandoffVerb: [String]] = [
        .start: ["task", "doneWhen", "context"],
        .context: ["add"],
        .priorities: HandoffStandingSlot.keyPrefixes.flatMap { [$0, "\($0)DoneWhen", "\($0)Context"] },
    ]
    /// Keys that may repeat, one item each. The first-wins rule does not apply to them.
    public static let repeatableQueryKeys: Set<String> = Set(
        ["context", "add"] + HandoffStandingSlot.keyPrefixes.map { "\($0)Context" }
    )
    /// Most context items one handoff may carry. More are ignored and counted.
    public static let maximumContextItems = 20
    /// Most context items one standing slot may carry: three slots share one URL.
    public static let maximumContextItemsPerSlot = 8

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
        var repeatedValues: [(name: String, value: String)] = []
        var duplicateKeys: [String] = []
        var unknownKeys: [String] = []
        let known = knownQueryKeys[verb] ?? []

        for item in items {
            if !known.contains(item.name) {
                if !unknownKeys.contains(item.name) { unknownKeys.append(item.name) }
                continue
            }
            if repeatableQueryKeys.contains(item.name) {
                repeatedValues.append((item.name, item.value ?? ""))
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

        var ignoredContext = 0
        func contextItems(named name: String, cap: Int) -> [HandoffContextItem] {
            var context: [HandoffContextItem] = []
            for raw in repeatedValues where raw.name == name {
                let cleaned = stripControlCharacters(raw.value, didStrip: &strippedAnything)
                guard let item = HandoffContextItem.parse(cleaned) else {
                    ignoredContext += 1
                    continue
                }
                if context.contains(item) { continue }
                guard context.count < cap else {
                    ignoredContext += 1
                    continue
                }
                context.append(item)
            }
            return context
        }

        if verb == .priorities {
            var standing: [HandoffStandingSlot] = []
            var truncated: [HandoffFlag] = []
            for (slot, prefix) in HandoffStandingSlot.keyPrefixes.enumerated() {
                let rawTask = firstValues[prefix] ?? ""
                let cleanedTask = stripControlCharacters(rawTask, didStrip: &strippedAnything)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let context = contextItems(named: "\(prefix)Context", cap: maximumContextItemsPerSlot)
                guard !cleanedTask.isEmpty else {
                    // A slot with no task is no slot, and its context has nowhere to go.
                    ignoredContext += context.count
                    continue
                }
                let task = capped(cleanedTask)
                if task.count < cleanedTask.count {
                    truncated.append(.taskTruncated(originalLength: cleanedTask.count))
                }
                var doneWhen: String?
                if let rawDoneWhen = firstValues["\(prefix)DoneWhen"] {
                    let cleaned = stripControlCharacters(rawDoneWhen, didStrip: &strippedAnything)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if !cleaned.isEmpty {
                        let cappedDoneWhen = capped(cleaned)
                        if cappedDoneWhen.count < cleaned.count {
                            truncated.append(.doneWhenTruncated(originalLength: cleaned.count))
                        }
                        doneWhen = cappedDoneWhen
                    }
                }
                standing.append(
                    HandoffStandingSlot(slot: slot, task: task, doneWhen: doneWhen, context: context)
                )
            }
            // The main priority is the point of the shortlist; secondaries alone are not one.
            guard standing.first?.slot == 0 else { return .rejected(.missingPrimary) }
            flags.append(contentsOf: truncated)
            if strippedAnything { flags.append(.controlCharactersStripped) }
            if !duplicateKeys.isEmpty { flags.append(.duplicateKeysIgnored(duplicateKeys)) }
            if !unknownKeys.isEmpty { flags.append(.unknownQueryItems(unknownKeys)) }
            if ignoredContext > 0 { flags.append(.contextItemsIgnored(count: ignoredContext)) }
            return .confirm(
                HandoffRequest(verb: verb, task: "", doneWhen: nil, flags: flags, standing: standing)
            )
        }

        let context = contextItems(
            named: verb == .context ? "add" : "context",
            cap: maximumContextItems
        )

        if verb == .context {
            guard !context.isEmpty else { return .rejected(.missingContext) }
            if strippedAnything { flags.append(.controlCharactersStripped) }
            if !unknownKeys.isEmpty { flags.append(.unknownQueryItems(unknownKeys)) }
            if ignoredContext > 0 { flags.append(.contextItemsIgnored(count: ignoredContext)) }
            return .confirm(
                HandoffRequest(verb: verb, task: "", doneWhen: nil, flags: flags, context: context)
            )
        }

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
        if ignoredContext > 0 { flags.append(.contextItemsIgnored(count: ignoredContext)) }

        return .confirm(
            HandoffRequest(
                verb: verb,
                task: task,
                doneWhen: doneWhen,
                flags: flags,
                context: context
            )
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
