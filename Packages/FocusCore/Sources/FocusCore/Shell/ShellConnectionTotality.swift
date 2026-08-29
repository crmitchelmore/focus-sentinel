import Foundation

/// **Why a stored property of a connection carries no drawn value** (focus-7ow).
///
/// Every escape from the totality check is one of these four, and each has to be written down at
/// the property. There is deliberately no default and no "unlisted means exempt": a property with
/// no entry at all is a **failure**, which is the whole mechanism. Adding a field and saying
/// nothing about it turns the lane red; adding a field and claiming an exemption is a diff a
/// reviewer can see and argue with.
public enum ShellUndrawnReason: String, Sendable, CaseIterable, Codable, Hashable {
    /// The connection's issue stamp. `ShellRenderReading` compares it itself, field by field
    /// against `expectedGeneration`, so echoing it as a value would assert it twice.
    case generation
    /// `didRender` / `didDraw` — the channel the report arrives on. A receipt cannot report
    /// itself.
    case receipt
    /// A closure only a **click** reaches. No lane in this programme holds the Accessibility
    /// grant it would take to press one, which is exactly why `{ _ in }` in their place survived
    /// two rounds of gates — so these are handed back through `ShellSettingsRendering` and driven
    /// by the self-check instead of being drawn.
    case sink
    /// The value is carried on a state this window shares with another surface and **this**
    /// window draws nothing from it. `CockpitState.isObservingActivity` is the live example: the
    /// cockpit's footer draws `sensing`, never this flag.
    case notDrawnOnThisSurface
}

/// **What echoes one stored property of a connection** (focus-7ow).
public enum ShellFieldEcho: Sendable {
    /// The property is drawn, and these fields are what report it. Every one of them must be a
    /// field the composition root recorded an expectation for, which is what chains this check
    /// into `ShellRenderFidelity`: mapped → expected → reported → equal.
    case drawn([ShellRenderedField])
    /// Descend. Every stored property of the value must itself be mapped, at `parent.child`.
    /// Used for the two values a view draws member by member — `CockpitConnection.state` and
    /// `ShellSettingsConnection.intervention` — rather than as one line.
    case composite
    /// Not drawn, with the reason.
    case undrawn(ShellUndrawnReason)
}

/// A connection struct whose every stored property is bound to the receipt that echoes it.
///
/// The map is keyed by **path**, so a `composite` property's members appear as `state.status`,
/// `state.priority`, and so on. Paths rather than a nested map because the failure a reader needs
/// to see is a path — `intervention.quietHours has no echo` — and because a flat table is the
/// same shape as the bijection lint this repository already uses to bind an enum's cases to a key
/// set.
public protocol ShellDrawnConnection {
    /// The type's name, for the reading. Written down rather than taken from `String(describing:)`
    /// so a rename cannot silently change what a gate log says it audited.
    static var connectionName: String { get }
    static var fieldEchoes: [String: ShellFieldEcho] { get }
}

/// **Whether every field of a connection is echoed by a receipt** (focus-7ow).
///
/// Four ways it fails, and they are four different mistakes:
///
/// | field | the mistake |
/// |---|---|
/// | `unmappedPaths` | a stored property nobody said anything about — *the invented-field case* |
/// | `strandedPaths` | an echo for a property that no longer exists: the map has drifted |
/// | `unreportedPaths` | mapped to a field the composition root records no expectation for, so the fidelity check would skip it |
/// | `walkedPaths.isEmpty` | nothing was audited at all, which would make the whole reading vacuous |
public struct ShellTotalityReading: Sendable, Equatable, Hashable {
    public let connection: String
    /// Every stored-property path the walk reached, in the order it reached them.
    public let walkedPaths: [String]
    public let unmappedPaths: [String]
    public let strandedPaths: [String]
    /// Each as `path → field`, so the line names both halves of the broken link.
    public let unreportedPaths: [String]

    public init(
        connection: String,
        walkedPaths: [String],
        unmappedPaths: [String],
        strandedPaths: [String],
        unreportedPaths: [String]
    ) {
        self.connection = connection
        self.walkedPaths = walkedPaths
        self.unmappedPaths = unmappedPaths
        self.strandedPaths = strandedPaths
        self.unreportedPaths = unreportedPaths
    }

    public var isTotal: Bool {
        !walkedPaths.isEmpty
            && unmappedPaths.isEmpty
            && strandedPaths.isEmpty
            && unreportedPaths.isEmpty
    }

    public var summary: String {
        if isTotal {
            return "\(connection): every one of \(walkedPaths.count) fields is echoed by a receipt"
        }
        var parts: [String] = []
        if walkedPaths.isEmpty { parts.append("nothing was audited") }
        if !unmappedPaths.isEmpty {
            parts.append("no echo declared for \(unmappedPaths.joined(separator: ", "))")
        }
        if !strandedPaths.isEmpty {
            parts.append("an echo for fields that do not exist: \(strandedPaths.joined(separator: ", "))")
        }
        if !unreportedPaths.isEmpty {
            parts.append(
                "the app records no expectation for \(unreportedPaths.joined(separator: ", "))"
            )
        }
        return "\(connection): " + parts.joined(separator: "; ")
    }

    public var dictionary: [String: Any] {
        [
            "connection": connection,
            "walkedPaths": walkedPaths,
            "fieldCount": walkedPaths.count,
            "unmappedPaths": unmappedPaths,
            "strandedPaths": strandedPaths,
            "unreportedPaths": unreportedPaths,
            "isTotal": isTotal,
            "summary": summary
        ]
    }
}

/// **The boundary, closed by construction rather than by the reviewer's imagination**
/// (focus-7ow).
///
/// ## The doctrine failure this replaces
///
/// Round 3 found eight no-op mutations that survived the whole gate. The fix enumerated the nine
/// values those eight mutations touched. Round 5 pointed at four more the enumeration had missed —
/// two of them boolean flips, so the result could not be vacuous — and they reproduced the round-3
/// invisibility signature verbatim: 286 ok against 286, an empty ok-assertion diff, a nineteen-
/// stage PASS, and four things on the screen saying something false. Curating receipt cases by
/// hand against a known mutant guarantees a next mutant.
///
/// So this walks the connection with `Mirror` and asserts that **every stored property it finds**
/// is bound to something. It cannot be written to a known failure, because it does not know what
/// the failure is: it knows only what the type has. A field added tomorrow is audited tomorrow.
///
/// ## Why `Mirror` and not a macro or a lint
///
/// A source lint would be a scan for spelling, and this repository has already been taught what
/// that is worth: `PreemptionCredit`'s ancestor lived in a host as a private method with a source
/// scan for a regression test, and an adversarial lens replaced its body with `return true` while
/// 824 tests stayed green. `Mirror` reads the compiled type. A property that exists is a property
/// this sees, whatever the source says.
public enum ShellConnectionTotality {
    /// - Parameters:
    ///   - connection: the value itself, walked live. No probe is needed and none is used:
    ///     `Mirror` over a struct lists every stored property whatever it currently holds, so a
    ///     `nil` optional is still a path the walk reaches.
    ///   - echoes: the type's own declaration.
    ///   - reported: the fields the composition root actually recorded an expectation for at the
    ///     moment it built this connection. This is the link into `ShellRenderFidelity` — a field
    ///     the root has no opinion about is skipped there, so a mapping to one would be a mapping
    ///     to nothing.
    public static func audit<Connection: ShellDrawnConnection>(
        _ connection: Connection,
        reported: Set<ShellRenderedField>
    ) -> ShellTotalityReading {
        audit(
            connectionName: Connection.connectionName,
            value: connection,
            echoes: Connection.fieldEchoes,
            reported: reported
        )
    }

    /// The same, for a caller that holds the pieces separately — the unit lane, which audits the
    /// map against the type with every field counted as reported, so that the two halves of the
    /// chain fail separately and legibly.
    public static func audit(
        connectionName: String,
        value: Any,
        echoes: [String: ShellFieldEcho],
        reported: Set<ShellRenderedField>
    ) -> ShellTotalityReading {
        var walked: [String] = []
        var unmapped: [String] = []
        var unreported: [String] = []

        walk(value, prefix: "", echoes: echoes, reported: reported,
             walked: &walked, unmapped: &unmapped, unreported: &unreported)

        let reachedPaths = Set(walked)
        let stranded = echoes.keys.filter { !reachedPaths.contains($0) }.sorted()

        return ShellTotalityReading(
            connection: connectionName,
            walkedPaths: walked,
            unmappedPaths: unmapped,
            strandedPaths: stranded,
            unreportedPaths: unreported
        )
    }

    private static func walk(
        _ value: Any,
        prefix: String,
        echoes: [String: ShellFieldEcho],
        reported: Set<ShellRenderedField>,
        walked: inout [String],
        unmapped: inout [String],
        unreported: inout [String]
    ) {
        for child in Mirror(reflecting: value).children {
            guard let label = child.label else { continue }
            let path = prefix.isEmpty ? label : "\(prefix).\(label)"
            walked.append(path)

            guard let echo = echoes[path] else {
                unmapped.append(path)
                continue
            }

            switch echo {
            case .undrawn:
                continue

            case .drawn(let fields):
                // A mapping to no field at all is a mapping to nothing, and would let a property
                // claim to be drawn while asserting the same as `.undrawn`.
                if fields.isEmpty {
                    unreported.append("\(path) → (no field)")
                    continue
                }
                for field in fields where !reported.contains(field) {
                    unreported.append("\(path) → \(field.rawValue)")
                }

            case .composite:
                // Descend through an optional's wrapper so `parent.child` is the path either way.
                // A `nil` composite has nothing to walk, and that is a hole this refuses to leave
                // silent — every composite in the shell is non-optional, and one that became
                // optional would arrive here as an unmapped-by-absence failure rather than as a
                // vacuous pass.
                let mirror = Mirror(reflecting: child.value)
                let inner: Any
                if mirror.displayStyle == .optional {
                    guard let wrapped = mirror.children.first?.value else {
                        unreported.append("\(path) → (composite is nil, nothing could be walked)")
                        continue
                    }
                    inner = wrapped
                } else {
                    inner = child.value
                }
                walk(inner, prefix: path, echoes: echoes, reported: reported,
                     walked: &walked, unmapped: &unmapped, unreported: &unreported)
            }
        }
    }
}
