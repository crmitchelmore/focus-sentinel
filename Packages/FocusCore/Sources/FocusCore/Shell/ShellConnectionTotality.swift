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
        var pruned: Set<String> = []

        walk(value, prefix: "", echoes: echoes, reported: reported,
             walked: &walked, unmapped: &unmapped, unreported: &unreported, pruned: &pruned)

        let reachedPaths = Set(walked)
        // **A path under a `nil` is not a stranded echo** (focus-cxs).
        //
        // `strandedPaths` answers *"the map names a property the type no longer has"*, and the
        // deep walk gave it a second way to fire that means nothing of the sort: the live cockpit
        // has no pending handoff, so `state.pendingHandoff` is `nil`, so `state.pendingHandoff.task`
        // is never reached — an absence of a **value**, not of a property.
        //
        // So the walk records where it pruned, and an echo below a pruned prefix is neither
        // stranded nor satisfied: it is simply not applicable to this value. The type-level
        // question — *does this property still exist?* — is asked by the unit lane, of a value
        // with every optional populated, where nothing is pruned and every declared path is
        // either reached or genuinely stranded.
        let stranded = echoes.keys
            .filter { path in
                !reachedPaths.contains(path)
                    && !pruned.contains(where: { path.hasPrefix($0 + ".") })
            }
            .sorted()

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
        unreported: inout [String],
        pruned: inout Set<String>
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
                // The subtree is pruned, and that is a decision rather than an oversight: nothing
                // *under* a value this window does not draw is drawn either. The exemption is
                // written down at the parent, where a reviewer can argue with it.
                pruned.insert(path)
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
                // **And then descend anyway** (focus-cxs). This is the round-6 residue, named by
                // round 6 itself: *"deeper structs are leaves"*. A `.drawn` binding stopped the
                // walk, so a field invented **inside** `PrioritySnapshot` or `InterventionSettings`
                // was reached by nothing — and the whole-value digest that was supposed to cover it
                // is computed on both sides from the same input, so it does not participate in the
                // comparison either. A three-line residue mutant gave 19/19 PASS, 303 ok against
                // 303 and an empty ok-assertion diff while three drawn things lied.
                descend(child.value, path: path, echoes: echoes, reported: reported,
                        walked: &walked, unmapped: &unmapped, unreported: &unreported,
                        pruned: &pruned)

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
                        pruned.insert(path)
                        continue
                    }
                    inner = wrapped
                } else {
                    inner = child.value
                }
                walk(inner, prefix: path, echoes: echoes, reported: reported,
                     walked: &walked, unmapped: &unmapped, unreported: &unreported,
                     pruned: &pruned)
            }
        }
    }

    /// Walk into a `.drawn` value if it is one of **ours** and has members of its own.
    ///
    /// A `nil` optional is simply nothing to walk — unlike a `nil` `.composite`, which is a hole,
    /// because a `.drawn` value has already bound itself to a receipt and the members underneath
    /// are additional detail rather than the whole of it.
    private static func descend(
        _ value: Any,
        path: String,
        echoes: [String: ShellFieldEcho],
        reported: Set<ShellRenderedField>,
        walked: inout [String],
        unmapped: inout [String],
        unreported: inout [String],
        pruned: inout Set<String>
    ) {
        let mirror = Mirror(reflecting: value)
        if mirror.displayStyle == .optional {
            guard let wrapped = mirror.children.first?.value else {
                // Nothing to walk, and nothing wrong: the value is absent, not the property.
                pruned.insert(path)
                return
            }
            descend(wrapped, path: path, echoes: echoes, reported: reported,
                    walked: &walked, unmapped: &unmapped, unreported: &unreported,
                    pruned: &pruned)
            return
        }
        guard isOurOwnStruct(value, mirror: mirror) else {
            // A leaf: one datum, and nothing below it to declare. Recorded as pruned so that an
            // echo somebody wrote for a member of a foreign type reads as stranded rather than
            // as satisfied.
            return
        }
        walk(value, prefix: path, echoes: echoes, reported: reported,
             walked: &walked, unmapped: &unmapped, unreported: &unreported, pruned: &pruned)
    }

    /// **Where the walk stops, decided by ownership rather than by a list of exceptions**
    /// (focus-cxs).
    ///
    /// A value type declared in one of this programme's own modules is *a bag of facts we are
    /// responsible for drawing*, so the walk goes into it and every member must be bound. Anything
    /// else — `UUID`, `Date`, `URL`, `Duration`, `Data`, an array, a set, a dictionary, an enum —
    /// is **one datum**, and is where a path ends.
    ///
    /// The rule is ownership and not a denylist on purpose. This repository has been taught twice
    /// what curating a list against a known failure is worth: round 4 enumerated the nine values
    /// one mutant touched and round 5 lied about four more. A denylist of "scalar-like Foundation
    /// types" would be the same instrument again — and it would also be wrong, because `Date`'s
    /// `Mirror` exposes `timeIntervalSinceReferenceDate` and `Duration`'s exposes `_low`/`_high`,
    /// which are storage details no window draws and no table should have to name.
    ///
    /// Enums stop the walk whatever module they come from: a case with a payload reflects as a
    /// child named after the case, so the *path* would depend on the value, and a table keyed by
    /// path could not name it. `ShellValueDigest` is what reads inside those.
    private static func isOurOwnStruct(_ value: Any, mirror: Mirror) -> Bool {
        guard mirror.displayStyle == .struct, !mirror.children.isEmpty else { return false }
        // `String(reflecting:)` on a metatype is the fully-qualified name — `FocusCore.CockpitState`,
        // `Foundation.Date` — so the module is everything before the first dot.
        let qualified = String(reflecting: type(of: value))
        guard let module = qualified.split(separator: ".").first else { return false }
        return module.hasPrefix("Focus")
    }
}
