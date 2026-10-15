import Foundation
import Testing

@testable import FocusCore

/// **The boundary is closed by construction, and this is what proves it** (focus-7ow).
///
/// ## The doctrine failure these tests exist to end
///
/// Five consecutive rounds of this epic wrote the proof to the known failure. Round 3 found eight
/// no-op mutations that survived the whole nineteen-stage gate; round 4's fix enumerated the nine
/// values those eight mutations touched, and nothing else. Round 5 then built a residue mutant out
/// of four values nobody had enumerated — two of them boolean flips, so the result could not be
/// vacuous — and it reproduced the round-3 invisibility signature verbatim: 286 ok-assertions
/// against 286, an EMPTY ok-assertion diff, a nineteen-stage PASS, and four things on the screen
/// saying something false.
///
/// Fixing the four by hand would have bought a seventh round. What is asserted here instead is
/// **totality**: every stored property of a connection struct is bound to a receipt, the binding
/// is checked against the compiled type with `Mirror` rather than against a memory of it, and a
/// field nobody bound is a failure whatever anybody intended.
///
/// The three suites below are the three ways that can break, and each is proved *failing* on a
/// type invented for the purpose — because a totality check nobody has seen fail on a field they
/// invented is not a totality check.
@Suite("Totality: every field of a connection is echoed by a receipt")
struct ShellConnectionTotalityTests {

    // MARK: - The mechanism, proved failing

    /// A connection with three fields, two of them bound.
    private struct PartlyBoundConnection: ShellDrawnConnection {
        let intent: String
        let count: Int
        /// The field somebody added and said nothing about.
        let inventedField: Bool

        static var connectionName: String { "PartlyBoundConnection" }
        static var fieldEchoes: [String: ShellFieldEcho] {
            [
                "intent": .drawn([.priorityIntent]),
                "count": .drawn([.recentCount])
            ]
        }
    }

    @Test("a field nobody bound to a receipt fails the audit by name")
    func anUnboundFieldFails() {
        let reading = ShellConnectionTotality.audit(
            PartlyBoundConnection(intent: "x", count: 1, inventedField: true),
            reported: Set(ShellRenderedField.allCases)
        )

        #expect(!reading.isTotal, "a connection with an unbound field passed the audit")
        #expect(reading.unmappedPaths == ["inventedField"])
        #expect(reading.summary.contains("inventedField"), "the failure did not name the field")
    }

    /// The reverse half of the bijection: an echo for a field that is not there any more.
    private struct DriftedConnection: ShellDrawnConnection {
        let intent: String

        static var connectionName: String { "DriftedConnection" }
        static var fieldEchoes: [String: ShellFieldEcho] {
            [
                "intent": .drawn([.priorityIntent]),
                "removedLastRound": .drawn([.status])
            ]
        }
    }

    @Test("an echo for a field that no longer exists fails the audit")
    func aStrandedEchoFails() {
        let reading = ShellConnectionTotality.audit(
            DriftedConnection(intent: "x"),
            reported: Set(ShellRenderedField.allCases)
        )

        #expect(!reading.isTotal)
        #expect(reading.strandedPaths == ["removedLastRound"])
    }

    /// Bound to a field, but to one the composition root records no expectation for — which
    /// `ShellRenderFidelity` **skips**, so the binding would be a binding to nothing.
    @Test("a field bound to something nobody expects fails the audit")
    func anUnexpectedFieldFails() {
        let reading = ShellConnectionTotality.audit(
            connectionName: "PartlyBoundConnection",
            value: PartlyBoundConnection(intent: "x", count: 1, inventedField: true),
            echoes: [
                "intent": .drawn([.priorityIntent]),
                "count": .drawn([.recentCount]),
                "inventedField": .drawn([.storeStatus])
            ],
            // The root has an opinion about the first two and none about the third.
            reported: [.priorityIntent, .recentCount]
        )

        #expect(!reading.isTotal)
        #expect(reading.unreportedPaths == ["inventedField → storeStatus"])
    }

    /// An empty binding would otherwise be a way of writing `.undrawn` without saying so.
    @Test("a field bound to no field at all fails the audit")
    func anEmptyBindingFails() {
        let reading = ShellConnectionTotality.audit(
            connectionName: "PartlyBoundConnection",
            value: PartlyBoundConnection(intent: "x", count: 1, inventedField: true),
            echoes: [
                "intent": .drawn([]),
                "count": .drawn([.recentCount]),
                "inventedField": .undrawn(.notDrawnOnThisSurface)
            ],
            reported: [.recentCount]
        )

        #expect(!reading.isTotal)
        #expect(reading.unreportedPaths == ["intent → (no field)"])
    }

    /// Nothing walked is not "nothing wrong". A connection with no stored properties at all, or
    /// an audit pointed at the wrong value, would otherwise pass every clause vacuously.
    private struct EmptyConnection: ShellDrawnConnection {
        static var connectionName: String { "EmptyConnection" }
        static var fieldEchoes: [String: ShellFieldEcho] { [:] }
    }

    @Test("an audit that walked nothing is not total")
    func aVacuousAuditFails() {
        let reading = ShellConnectionTotality.audit(
            EmptyConnection(),
            reported: Set(ShellRenderedField.allCases)
        )
        #expect(!reading.isTotal, "an audit that walked no fields at all passed")
    }

    // MARK: - Descent

    private struct Inner {
        let shown: String
        let alsoShown: Bool
    }

    private struct CompositeConnection: ShellDrawnConnection {
        let inner: Inner

        static var connectionName: String { "CompositeConnection" }
        static var fieldEchoes: [String: ShellFieldEcho] {
            [
                "inner": .composite,
                "inner.shown": .drawn([.priorityIntent])
                // `inner.alsoShown` is deliberately absent.
            ]
        }
    }

    @Test("a composite descends, and an unbound member of it fails by its path")
    func descentReachesMembers() {
        let reading = ShellConnectionTotality.audit(
            CompositeConnection(inner: Inner(shown: "x", alsoShown: true)),
            reported: Set(ShellRenderedField.allCases)
        )

        #expect(!reading.isTotal)
        #expect(reading.unmappedPaths == ["inner.alsoShown"])
        #expect(reading.walkedPaths.contains("inner.shown"))
    }

    // MARK: - Descent past a `.drawn` binding (focus-cxs)

    private struct DeeperStill {
        let named: String
    }

    private struct Deep {
        let shown: String
        /// A struct inside a struct: the level round 6 could not see.
        let deeper: DeeperStill
    }

    /// A connection whose one field is `.drawn` — bound to a receipt, exactly as
    /// `CockpitConnection.state.priority` was — and which holds a value with members of its own.
    private struct DrawnCompositeConnection: ShellDrawnConnection {
        let priority: Deep

        static var connectionName: String { "DrawnCompositeConnection" }
        static var fieldEchoes: [String: ShellFieldEcho] {
            [
                "priority": .drawn([.priorityDetail]),
                "priority.shown": .drawn([.priorityIntent]),
                "priority.deeper": .drawn([.priorityDetail])
                // `priority.deeper.named` is deliberately absent: the invented field, two levels
                // below the connection struct.
            ]
        }
    }

    /// **A `.drawn` binding no longer stops the walk** (focus-cxs).
    ///
    /// This is round 6's own named residue, driven: *"deeper structs are leaves, covered by a
    /// whole-value digest that does not participate in the comparison"*. A field bound to a receipt
    /// used to be the end of the path, so a property invented inside the value it named was reached
    /// by nothing at all — and the digest cannot catch it, because the composition root and the
    /// window both compute the digest from the same input.
    @Test("a field bound to a receipt still descends, and an unbound member two levels down fails")
    func drawnValuesDescendToTheirLeaves() {
        let reading = ShellConnectionTotality.audit(
            DrawnCompositeConnection(priority: Deep(shown: "x", deeper: DeeperStill(named: "y"))),
            reported: Set(ShellRenderedField.allCases)
        )

        #expect(!reading.isTotal, "a field invented two levels down passed the audit")
        #expect(reading.unmappedPaths == ["priority.deeper.named"])
        #expect(reading.walkedPaths.contains("priority.deeper"))
    }

    /// The other half of the rule, and the reason it is ownership rather than a list of exceptions:
    /// a foreign value is **one datum**, whatever its `Mirror` happens to expose. `Date` reflects
    /// as `timeIntervalSinceReferenceDate` and `Duration` as `_low`/`_high` — storage details no
    /// window draws and no table should have to name.
    private struct ForeignLeafConnection: ShellDrawnConnection {
        let stamp: Date
        let span: Duration
        let identifier: UUID
        let location: URL

        static var connectionName: String { "ForeignLeafConnection" }
        static var fieldEchoes: [String: ShellFieldEcho] {
            [
                "stamp": .drawn([.priorityDetail]),
                "span": .drawn([.priorityDetail]),
                "identifier": .drawn([.priorityDetail]),
                "location": .drawn([.privacyStorePath])
            ]
        }
    }

    @Test("a value from another module is one datum, and the walk stops there")
    func foreignValuesAreLeaves() {
        let reading = ShellConnectionTotality.audit(
            ForeignLeafConnection(
                stamp: Date(timeIntervalSince1970: 0),
                span: .seconds(3),
                identifier: UUID(),
                location: URL(fileURLWithPath: "/tmp/focus")
            ),
            reported: Set(ShellRenderedField.allCases)
        )

        #expect(reading.isTotal, "\(reading.summary)")
        #expect(reading.walkedPaths == ["stamp", "span", "identifier", "location"])
    }

    // MARK: - The real connection

    /// `CockpitConnection`'s own table, against `CockpitConnection` itself.
    ///
    /// This is the test the invented-field proof is run against: add a stored property to
    /// `CockpitConnection` — **or to anything it holds** — say nothing about it, and this goes red
    /// naming the path.
    ///
    /// ## Why every optional is populated
    ///
    /// Because a `nil` has no members to walk (focus-cxs). The composition root audits the **live**
    /// connection, where `pendingHandoff` is `nil` almost always and `priority` is `nil` before a
    /// person has committed to anything — so the live audit answers a question about the values of
    /// the moment. The question about the **type** is this one, and it can only be asked of a value
    /// that has every branch of itself filled in.
    @Test("every field of CockpitConnection, to the leaves, is bound to a receipt")
    @MainActor
    func theCockpitConnectionIsTotal() {
        let reading = ShellConnectionTotality.audit(
            CockpitConnection(
                state: Self.fullyPopulatedState,
                actions: nil,
                sessionActions: nil,
                sessionElapsedSeconds: 42,
                lastActiveBundleID: "com.apple.Safari"
            ),
            reported: Set(ShellRenderedField.allCases)
        )

        #expect(reading.isTotal, "\(reading.summary)")
        // Non-vacuity, **one level down**: round 6 closed the boundary at the connection struct and
        // named its own residue — *"deeper structs are leaves"* — so a field invented inside
        // `PrioritySnapshot` was reached by nothing while a three-line mutant gave 19/19 PASS with
        // an empty ok-assertion diff. These are the paths that were unreachable.
        for member in [
            "state.storeOpened",
            "state.lastWriteFailed",
            "state.showsRitualPrompt",
            "state.priority.intent",
            "state.priority.timebox",
            "state.priority.assessment",
            "state.session.phase",
            "state.session.pauseCauses",
            "state.pendingHandoff.flags",
            "state.sensing.isOnSecondaryDisplay",
            "state.capabilities.observations"
        ] {
            let reached = reading.walkedPaths.contains(member)
            #expect(reached, "the walk never reached \(member)")
        }
        let count = reading.walkedPaths.count
        #expect(count >= 45, "the walk reached only \(count) fields: \(reading.walkedPaths)")
    }

    /// Every optional filled in and every composite non-empty, so the walk has something to reach
    /// at every path the type declares.
    static let fullyPopulatedState = CockpitState(
        status: .relevant,
        storeOpened: true,
        isObservingActivity: true,
        priority: PrioritySnapshot(
            id: UUID(uuidString: "70741117-0000-4000-8000-000000000001")!,
            intent: "Write the Q3 proposal for Acme",
            doneWhen: "the draft is sent",
            createdAt: Date(timeIntervalSince1970: 1_767_225_600),
            lastActivatedAt: Date(timeIntervalSince1970: 1_767_229_200),
            timeboxSeconds: 1_800,
            startedAt: Date(timeIntervalSince1970: 1_767_229_200),
            timebox: .none,
            contextItems: [],
            rules: [],
            assessment: .notAssessable
        ),
        recent: [
            RecentPriority(
                id: UUID(uuidString: "70741117-0000-4000-8000-000000000002")!,
                intent: "Review the compliance pack"
            )
        ],
        pendingHandoff: HandoffRequest(
            verb: .start,
            task: "Draft the incident note",
            doneWhen: "it is posted",
            flags: [],
            context: [HandoffContextItem(kind: .domain, value: "https://status.example.com")]
        ),
        showsRitualPrompt: true,
        session: SessionSnapshot(
            sessionID: UUID(uuidString: "70741117-0000-4000-8000-000000000003")!,
            taskID: UUID(uuidString: "70741117-0000-4000-8000-000000000001")!,
            phase: .focus,
            startedAt: Date(timeIntervalSince1970: 1_767_229_200)
        ),
        sensing: SensingSummary(isObserving: true, liveObserverCount: 4),
        verdict: nil,
        capabilities: CapabilityMatrix()
    )
}

/// **The digest, which is the other half of "not enumerated"** (focus-7ow).
///
/// A field added to `PrioritySnapshot` is in the reported string the day it is added, with nobody
/// editing anything. These assert that property directly, on a type invented for it.
@Suite("A whole value, derived rather than enumerated")
struct ShellValueDigestTests {
    private struct Before {
        var intent: String
        var doneWhen: String?
    }

    private struct After {
        var intent: String
        var doneWhen: String?
        var addedLater: Int
    }

    @Test("a field added to a value changes its digest without anybody editing a list")
    func aNewFieldIsInTheDigest() {
        let before = ShellValueDigest.describe(Before(intent: "ship it", doneWhen: nil))
        let after = ShellValueDigest.describe(
            After(intent: "ship it", doneWhen: nil, addedLater: 7)
        )
        #expect(before != after)
        #expect(after.contains("addedLater=7"))
    }

    @Test("nil is a reading, not an absence")
    func nilIsSpelled() {
        #expect(ShellValueDigest.describe(nil) == "none")
        #expect(ShellValueDigest.describe(Before(intent: "x", doneWhen: nil)).contains("doneWhen=none"))
    }

    @Test("two values that differ only inside a nested field have different digests")
    func nestedDifferencesShow() {
        let a = ShellValueDigest.describe(Before(intent: "x", doneWhen: "tests pass"))
        let b = ShellValueDigest.describe(Before(intent: "x", doneWhen: "tests fail"))
        #expect(a != b)
    }

    @Test("a list is its contents, in the order it is drawn in")
    func listOrderIsPartOfTheReading() {
        #expect(ShellValueDigest.describe(["a", "b"]) != ShellValueDigest.describe(["b", "a"]))
        #expect(ShellValueDigest.describe([String]()) == "[]")
    }

    /// The digest crosses a gate log, so it has to be legible: a `UUID` rendered as sixteen
    /// `UInt8` children would make a failing line unreadable.
    @Test("the leaves are spelled the way a person reads them")
    func leavesAreLegible() {
        let id = UUID()
        #expect(ShellValueDigest.describe(id) == id.uuidString)
        #expect(ShellValueDigest.describe(true) == "true")
        #expect(ShellValueDigest.describe(URL(fileURLWithPath: "/tmp/x")) == "/tmp/x")
    }
}
