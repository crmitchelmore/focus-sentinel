import Foundation
import Testing

@testable import FocusCore

/// 2026-01-01T00:00:00Z. No test here reads a real clock.
private let now = Date(timeIntervalSince1970: 1_767_225_600)

private func activation(
    _ bundleIdentifier: String?,
    name: String? = nil,
    pid: pid_t = 501
) -> FrontmostActivation {
    FrontmostActivation(
        bundleIdentifier: bundleIdentifier,
        localizedName: name,
        pid: pid,
        at: now
    )
}

@Suite("The sensitivity gate stands down first")
struct SensitivityGateTests {
    private let gate = SensitivityGate()

    /// Every seeded entry, one by one. "The list works" is not a claim; "each of these
    /// twenty-one bundle identifiers suppresses" is.
    @Test("every built-in entry suppresses, with reason builtInList")
    func everyBuiltInEntrySuppresses() {
        for bundleIdentifier in SensitivityGate.builtInSensitiveBundleIDs {
            let decision = gate.evaluate(activation(bundleIdentifier))
            #expect(
                decision.suppressionReason == .builtInList,
                "\(bundleIdentifier) did not suppress"
            )
            #expect(decision.clearedActivation == nil)
        }
        #expect(SensitivityGate.builtInSensitiveBundleIDs.count == 21)
    }

    /// The list is conservative on purpose, and this is the entry that says so. Messages is a
    /// private-messaging app *and* a work tool for a great many people; deciding that for
    /// somebody would be the app having an opinion about who they talk to.
    @Test("Messages is deliberately absent from the seed and offered as a suggestion instead")
    func messagesIsNotSeeded() {
        #expect(!SensitivityGate.builtInSensitiveBundleIDs.contains("com.apple.MobileSMS"))
        #expect(SensitivityGate.suggestedSensitiveBundleIDs.contains("com.apple.MobileSMS"))
        #expect(gate.evaluate(activation("com.apple.MobileSMS")).clearedActivation != nil)
    }

    @Test("a user-added entry suppresses, with reason userList")
    func userEntrySuppresses() {
        let withUserEntry = SensitivityGate(userAdded: ["com.example.TherapyNotes"])
        let decision = withUserEntry.evaluate(activation("com.example.TherapyNotes"))
        #expect(decision.suppressionReason == .userList)

        // And the same application clears through a gate that does not hold their list.
        #expect(gate.evaluate(activation("com.example.TherapyNotes")).clearedActivation != nil)
    }

    /// A process with no bundle identifier is exactly the one not to look at more closely.
    /// Six of ninety-two running processes had none when this was measured (probe P-83).
    @Test("an unbundled activation suppresses, with reason unbundled")
    func unbundledActivationSuppresses() {
        let decision = gate.evaluate(activation(nil, name: "npm exec something"))
        #expect(decision.suppressionReason == .unbundled)
        #expect(decision.clearedActivation == nil)
    }

    /// The user's own list wins where both would fire, so the surface can tell them it was
    /// their choice rather than the app's.
    @Test("a bundle identifier on both lists reports the user's list")
    func userListWinsOverBuiltIn() {
        let both = SensitivityGate(userAdded: ["com.apple.keychainaccess"])
        #expect(both.evaluate(activation("com.apple.keychainaccess")).suppressionReason == .userList)
    }

    @Test("an ordinary application clears, carrying its own identifier, pid and instant")
    func ordinaryApplicationClears() {
        let decision = gate.evaluate(activation("com.apple.dt.Xcode", pid: 9_001))
        let cleared = decision.clearedActivation
        #expect(cleared?.bundleIdentifier == "com.apple.dt.Xcode")
        #expect(cleared?.pid == 9_001)
        #expect(cleared?.at == now)
        #expect(decision.suppressionReason == nil)
    }

    /// **The ruling, as an API-surface assertion.**
    ///
    /// `ClearedActivation`'s memberwise initialiser is `fileprivate`, and the only file that
    /// can reach it holds the gate and nothing else. Verified by compiling a planted call from
    /// *this test target* — which has `@testable` access to everything internal — and watching
    /// it fail:
    ///
    /// ```
    /// error: 'ClearedActivation' initializer is inaccessible due to 'fileprivate'
    ///        protection level
    /// ```
    ///
    /// So a deeper read of a sensitive application does not compile, and the runtime half
    /// below is only the belt to that brace: there is no synthesised route in either — the
    /// type is not `Decodable`, so it cannot be conjured out of a file, and not
    /// `ExpressibleByStringLiteral`, so it cannot be written as a literal.
    @Test("a ClearedActivation can only be produced by the gate")
    func clearedActivationHasNoOtherRouteIn() {
        #expect(
            !(ClearedActivation.self is any Decodable.Type),
            "a Decodable ClearedActivation could be conjured from a file"
        )
        #expect(!(ClearedActivation.self is any ExpressibleByStringLiteral.Type))

        // Every one that exists came out of a decision, and a suppressed decision holds none.
        let suppressed = gate.evaluate(activation("com.apple.Passwords"))
        #expect(suppressed.clearedActivation == nil)
    }

    /// The effective list is what Privacy settings shows, and it is the union of the two —
    /// never one or the other.
    @Test("the effective list is the built-in list plus the user's own")
    func effectiveListIsTheUnion() {
        let withUser = SensitivityGate(userAdded: ["com.example.One", "com.example.Two"])
        #expect(withUser.effectiveBundleIDs.count == SensitivityGate.builtInSensitiveBundleIDs.count + 2)
        #expect(withUser.effectiveBundleIDs.isSuperset(of: SensitivityGate.builtInSensitiveBundleIDs))
    }

    /// Nothing here reads a screen, a title or a URL — the gate's only input is a bundle
    /// identifier, and a gate handed *only* a bundle identifier answers identically.
    @Test("the decision depends on the bundle identifier and on nothing else")
    func decisionDependsOnlyOnTheBundleIdentifier() {
        let plain = activation("com.1password.1password")
        let dressedUp = FrontmostActivation(
            bundleIdentifier: "com.1password.1password",
            localizedName: "Ledger — Q4 payroll.numbers",
            pid: 777,
            at: now.addingTimeInterval(999),
            dwellSeconds: 1_234
        )
        #expect(gate.evaluate(plain).suppressionReason == gate.evaluate(dressedUp).suppressionReason)
    }
}

@Suite("Frontmost activations are recorded, never dropped")
struct FrontmostActivationTests {
    /// A dropped event is a hole in the timeline, and a hole is worse than a row that says
    /// "something without a bundle identifier was here".
    @Test("an unbundled activation is filed under a synthesised key")
    func unbundledActivationIsKeyed() {
        #expect(activation(nil, name: "universalaccessd").subjectKey == "unbundled:universalaccessd")
        #expect(activation(nil).subjectKey == "unbundled:unknown")
        #expect(activation(nil).isUnbundled)
        #expect(!activation("com.apple.finder").isUnbundled)
        #expect(activation("com.apple.finder").subjectKey == "com.apple.finder")
    }

    /// Debouncing turns on subject identity and on nothing else. Measured cause (probe P-82):
    /// entering full screen produced activate → deactivate → activate → deactivate for **one**
    /// bundle identifier inside 22 ms.
    @Test("two activations of the same bundle are the same subject, whatever else differs")
    func sameSubjectIgnoresEverythingElse() {
        let first = FrontmostActivation(bundleIdentifier: "com.apple.Safari", pid: 1, at: now)
        let second = FrontmostActivation(
            bundleIdentifier: "com.apple.Safari",
            localizedName: "Safari",
            pid: 2,
            at: now.addingTimeInterval(0.022),
            dwellSeconds: 0.022
        )
        #expect(first.isSameSubject(as: second))

        let other = FrontmostActivation(bundleIdentifier: "com.apple.finder", pid: 1, at: now)
        #expect(!first.isSameSubject(as: other))

        // Two different unbundled processes are two different subjects.
        #expect(!activation(nil, name: "npm").isSameSubject(as: activation(nil, name: "node")))
    }
}
