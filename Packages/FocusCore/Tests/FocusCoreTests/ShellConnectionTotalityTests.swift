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

    // MARK: - The real connection

    /// `CockpitConnection`'s own table, against `CockpitConnection` itself.
    ///
    /// This is the test the invented-field proof is run against: add a stored property to
    /// `CockpitConnection`, say nothing about it, and this goes red naming the property.
    @Test("every field of CockpitConnection is bound to a receipt")
    @MainActor
    func theCockpitConnectionIsTotal() {
        let reading = ShellConnectionTotality.audit(
            CockpitConnection(
                state: .ready,
                actions: nil,
                sessionActions: nil,
                sessionElapsedSeconds: nil,
                lastActiveBundleID: nil
            ),
            reported: Set(ShellRenderedField.allCases)
        )

        #expect(reading.isTotal, "\(reading.summary)")
        // Non-vacuity: the walk has to have reached the state's members, not stopped at `state`.
        #expect(reading.walkedPaths.contains("state.storeIsReady"))
        #expect(reading.walkedPaths.contains("state.showsRitualPrompt"))
        #expect(
            reading.walkedPaths.count >= 19,
            "the walk reached only \(reading.walkedPaths.count) fields: \(reading.walkedPaths)"
        )
    }
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
