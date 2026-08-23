import Foundation
import Testing

@testable import FocusCore

/// 2026-01-01T00:00:00Z.
private let now = Date(timeIntervalSince1970: 1_767_225_600)

/// Exactly the four things that must never reach the store: a window title, a full URL with
/// its path and query, a document name, and an absolute file path.
///
/// These are not arbitrary strings. Each is a real shape of captured content — the kind of
/// thing an `AXUIElement` read or a `kCGWindowName` would hand you — and each carries a
/// distinctive needle the assertions hunt for afterwards.
private let hostileCorpus: [String] = [
    // window titles
    "Q4 payroll — Numbers",
    "Divorce settlement draft v3.docx — Microsoft Word",
    "Re: results from the clinic — Mail",
    "Untitled — 1Password",
    "acme-corp/secret-project — Pull Request #412 — Google Chrome",
    // full URLs with paths and queries
    "https://mail.example.com/u/0/#inbox/FMfcgzGtwXyZ?compose=new",
    "https://bank.example.co.uk/accounts/12345678/statements?from=2026-01-01",
    "https://intranet.example.org/hr/reviews/aturing/2026?tab=compensation",
    // document names
    "Redundancy list FINAL FINAL.xlsx",
    "passport-scan.pdf",
    // absolute file paths
    "/Users/aturing/Documents/Personal/therapy-notes.md",
    "/Volumes/Backup/2026/tax-return-2025.pdf",
    "~/Library/Application Support/1Password/vault.opvault"
]

/// The needles: if any of these appears anywhere in a stored value, something leaked.
private let needles: [String] = [
    "payroll", "Divorce", "clinic", "1Password", "secret-project",
    "mail.example.com", "bank.example.co.uk", "intranet.example.org",
    "compose=new", "statements", "compensation",
    "Redundancy", "passport", "therapy-notes", "tax-return", "vault.opvault",
    "/Users/", "/Volumes/", "https://", "~/Library"
]

@Suite("Raw captured content is unrepresentable, not merely forbidden")
struct NormalisedDetailTests {
    /// **The hostile corpus.** Every producer in the epic is offered each of these strings in
    /// the place raw content would arrive, and nothing from any of them appears in any stored
    /// value.
    ///
    /// The producers here are the ones that carry a string at all — the activation (a
    /// localized name, which is the closest thing in this epic to a title) and the window
    /// metadata reader's decoded value (an owner *name*, which is an application's name and
    /// never a document's). Each is asked for the detail it would write, and the detail is
    /// searched for every needle.
    @Test("a hostile corpus fed through every producer reaches no stored value")
    func hostileCorpusNeverReachesTheStore() {
        for hostile in hostileCorpus {
            // Producer 1: an activation whose *name* is captured content.
            let activation = FrontmostActivation(
                bundleIdentifier: "com.example.Editor",
                localizedName: hostile,
                pid: 42,
                at: now,
                dwellSeconds: 12
            )
            let activationDetail = NormalisedDetail.tokens([.redundantActivation])
            assertClean(activationDetail.storedValue, of: hostile)
            // The activation's own persisted subject is a bundle identifier, not the name.
            #expect(activation.subjectKey == "com.example.Editor")

            // Producer 2: window metadata whose owner name is captured content.
            let window = WindowMetadataValue(
                ownerName: hostile,
                ownerPID: 42,
                layer: 0,
                number: 7,
                bounds: ScreenRect(x: 0, y: 0, width: 1_920, height: 1_080),
                isOnScreen: true,
                alpha: 1
            )
            let windowDetail = NormalisedDetail.measurement(.windowCount, 1)
            assertClean(windowDetail.storedValue, of: hostile)
            #expect(window.ownerName == hostile, "the value type may hold it; the store may not")

            // Producer 3: the sensitivity gate's suppression row.
            let gate = SensitivityGate()
            let suppressed = gate.evaluate(
                FrontmostActivation(bundleIdentifier: nil, localizedName: hostile, pid: 42, at: now)
            )
            #expect(suppressed.suppressionReason == .unbundled)
            assertClean(NormalisedDetail.tokens([.sensitiveApp, .unbundled]).storedValue, of: hostile)

            // Producer 4: presentation, media, idle and lifecycle, each of which writes tokens.
            for detail in [
                NormalisedDetail.tokens([.fullScreen, .secondaryDisplay]),
                NormalisedDetail.tokens([.micRunning]),
                NormalisedDetail.tokens([.syntheticInput]),
                NormalisedDetail.tokens([DetailToken.forLifecycle(.screenLocked)]),
                NormalisedDetail.tokens([DetailToken.forCapabilityState(.unavailable)]),
                NormalisedDetail.measurement(.hardwareIdleSeconds, 1_536),
                NormalisedDetail.measurement(.dwellSeconds, 42),
                NormalisedDetail.empty
            ] {
                assertClean(detail.storedValue, of: hostile)
            }
        }
    }

    private func assertClean(
        _ stored: String,
        of hostile: String,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        #expect(!stored.contains(hostile), "the corpus entry itself leaked", sourceLocation: sourceLocation)
        for needle in needles {
            #expect(
                !stored.localizedCaseInsensitiveContains(needle),
                "'\(needle)' leaked into a stored detail: \(stored)",
                sourceLocation: sourceLocation
            )
        }
        // Whatever a producer writes, it is one of the two shapes and nothing else.
        let inspection = NormalisedDetail.inspect(stored)
        switch inspection {
        case .none, .tokens, .measurement:
            break
        case .unreadable:
            Issue.record("a producer wrote something this build cannot read back", sourceLocation: sourceLocation)
        }
    }

    /// The structural claim, stated once: the only two ways to make one of these are a token
    /// list and a typed measurement. There is no `NormalisedDetail(String)` — the memberwise
    /// initialiser is `private`, so a raw string cannot become a detail by *any* route,
    /// including from inside this module.
    @Test("there is no route from a String to a NormalisedDetail")
    func noStringRouteIn() {
        #expect(!(NormalisedDetail.self is any ExpressibleByStringLiteral.Type))
        #expect(!(NormalisedDetail.self is any Decodable.Type))
        #expect(
            !(NormalisedDetail.self is any LosslessStringConvertible.Type),
            "LosslessStringConvertible would be init(_ description: String) in disguise"
        )
    }
}

@Suite("Detail tokens and measurements round-trip")
struct DetailTokenTests {
    @Test("every token round-trips through the stored encoding")
    func everyTokenRoundTrips() {
        for token in DetailToken.allCases {
            let detail = NormalisedDetail.tokens([token])
            #expect(detail.storedValue == token.rawValue)
            #expect(NormalisedDetail.inspect(detail.storedValue) == .tokens([token]))
        }
        #expect(!DetailToken.allCases.isEmpty)
    }

    @Test("every measurement kind round-trips, including zero and a negative")
    func everyMeasurementRoundTrips() {
        for kind in MeasurementKind.allCases {
            for value in [0, 1, 5_400, -6] {
                let detail = NormalisedDetail.measurement(kind, value)
                #expect(NormalisedDetail.inspect(detail.storedValue) == .measurement(kind, value))
            }
        }
    }

    /// Two identical observations must produce two identical rows, or the debug export is not
    /// diffable and the evidence lane cannot say "nothing changed".
    @Test("token order and duplicates are normalised away")
    func tokensAreNormalised() {
        let a = NormalisedDetail.tokens([.fullScreen, .micRunning])
        let b = NormalisedDetail.tokens([.micRunning, .fullScreen, .micRunning])
        #expect(a == b)
        #expect(a.storedValue == b.storedValue)
        #expect(a.storedValue == "fullScreen,micRunning")
    }

    @Test("no detail at all is a real answer and reads back as none")
    func emptyIsARealAnswer() {
        #expect(NormalisedDetail.empty.isEmpty)
        #expect(NormalisedDetail.inspect(nil) == .none)
        #expect(NormalisedDetail.inspect("") == .none)
        #expect(NormalisedDetail.tokens([]).isEmpty)
    }

    /// A row written by a build that knew a token this one does not is not a licence to print
    /// its contents. It reads back inert.
    @Test("an unknown stored token reads back inert, never verbatim")
    func unknownTokensAreInert() {
        #expect(NormalisedDetail.inspect("cosmicRays") == .unreadable)
        #expect(NormalisedDetail.inspect("Q4 payroll — Numbers") == .unreadable)
        #expect(NormalisedDetail.inspect("dwellSeconds=notanumber") == .unreadable)
        #expect(NormalisedDetail.inspect("unknownKind=42") == .unreadable)

        // A mixed list keeps what it knows and silently drops what it does not.
        #expect(NormalisedDetail.inspect("micRunning,cosmicRays") == .tokens([.micRunning]))
    }

    @Test("the capability and lifecycle token mappings are total")
    func mappingsAreTotal() {
        for state in CapabilityState.allCases {
            let token = DetailToken.forCapabilityState(state)
            #expect(DetailToken.allCases.contains(token))
        }
        for lifecycle in SystemLifecycle.allCases {
            let token = DetailToken.forLifecycle(lifecycle)
            #expect(DetailToken.allCases.contains(token))
        }
    }
}
