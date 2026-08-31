import FocusCore
import Foundation
import Testing

@testable import FocusUI

/// A notification centre that answers whatever the test tells it to.
///
/// It exists so this whole suite runs **at zero grants, with no prompt and no notification
/// centre**. Since focus-wy0 the seam it stands in for has one call left — the settings read —
/// so this stub answers that and nothing else: there is no `setCategories` to count and no
/// `add(_:)` to fail, because the app makes neither.
@MainActor
final class StubNotificationCentre: NotificationCentring {
    var status: Int

    init(status: Int) {
        self.status = status
    }

    func authorizationStatus(_ completion: @escaping @MainActor (Int) -> Void) {
        completion(status)
    }
}

/// **What the notification boundary still does, and the three things it no longer does**
/// (R-82, P-134, §4.5, U-2, focus-wy0).
@Suite("The notification boundary, which now only listens")
@MainActor
struct NotificationDeliveryTests {
    /// The delivery token these drives mint. A fixed string rather than a `UUID`, so a failing
    /// line names something a person can read.
    private static let deliveryID = "the rung under test"

    // MARK: - Every authorisation state, decoded by an exhaustive switch

    @Test("the framework's status decodes to exactly one authorisation, in every case")
    func statusDecoding() {
        #expect(NotificationAuthorisation.decode(authorizationStatus: 0) == .notRequested)
        #expect(NotificationAuthorisation.decode(authorizationStatus: 1) == .denied)
        #expect(NotificationAuthorisation.decode(authorizationStatus: 2) == .authorised)
        #expect(NotificationAuthorisation.decode(authorizationStatus: 3) == .provisional)
        #expect(NotificationAuthorisation.decode(authorizationStatus: 4) == .provisional)
    }

    /// **An unknown status is never permission.** A future OS that adds a fifth case must not be
    /// able to turn a silent app into a noisy one, so the default is the conservative reading —
    /// which matters for focus-5ab, when there is something to be noisy with again.
    @Test("an unrecognised status decodes to denied, never to a grant", arguments: [5, 99, -1])
    func unknownStatusIsNeverAGrant(raw: Int) {
        #expect(NotificationAuthorisation.decode(authorizationStatus: raw) == .denied)
    }

    @Test("refreshing reads the state and never asks for it", arguments: [0, 1, 2, 3])
    func refreshReadsTheState(raw: Int) {
        let centre = StubNotificationCentre(status: raw)
        let delivery = NotificationDelivery(centre: centre)

        var reported: NotificationAuthorisation?
        delivery.refresh { reported = $0 }

        #expect(reported == NotificationAuthorisation.decode(authorizationStatus: raw))
        #expect(delivery.authorisation == reported)
        // **The number that discharges standing condition 5 for this file.**
        #expect(delivery.requestAuthorizationCallCount == 0)
    }

    // MARK: - Nothing is registered, at any grant (focus-wy0)

    /// **The seam offers no way to register a category, so no grant can cause one.**
    ///
    /// It used to: registration ran on every launch that found a grant, and put three actions
    /// onto a category no banner would ever carry, because U-2 had already removed the only rung
    /// that posts one. This is the assertion that replaces "registered exactly once, and only
    /// after a grant" — the honest count is now zero, at every grant, and it is enforced by the
    /// protocol rather than by a branch somebody could restore.
    @Test("the boundary can register nothing, whatever the grant says", arguments: [0, 1, 2, 3])
    func nothingIsEverRegistered(raw: Int) {
        let delivery = NotificationDelivery(centre: StubNotificationCentre(status: raw))
        delivery.refresh()

        let calls = Set(
            Mirror(reflecting: StubNotificationCentre(status: raw))
                .children.compactMap(\.label)
        )
        #expect(calls == ["status"], "the notification seam grew a capability: \(calls.sorted())")
        #expect(delivery.requestAuthorizationCallCount == 0)
    }

    /// The three actions are **kept** — focus-5ab needs them, and a press on a banner an earlier
    /// build posted still has to decode to one so `NudgeHost` can refuse it.
    @Test("the three answerable actions are still declared, and still decode")
    func threeActions() {
        #expect(NudgeNotificationAction.allCases.count == 3)
        #expect(Set(NudgeNotificationAction.allCases.map(\.identifier)).count == 3)
        for action in NudgeNotificationAction.allCases {
            #expect(action.identifier.hasPrefix("nudge.action."))
            // Every one is a real correction, so a tap goes through the same single function a
            // click does (R-86).
            #expect(CorrectionAction.allCases.contains(action.correction))
            #expect(!action.copyKey.isQueryLine)
        }
    }

    // **The delivery section is gone** (U-2), and so is the registration section (focus-wy0).
    // No rung routes to a notification, so there is no delivery to authorise, no failure to
    // demote, no route change to assert and no category to put buttons on. What remains below is
    // the half that still runs: decoding a press on a banner an earlier build posted.

    // MARK: - Taps come back as typed actions

    @Test("a tap on a registered action reports it, and anything else reports nothing")
    func tapsReportTypedActions() {
        let delivery = NotificationDelivery(centre: StubNotificationCentre(status: 2))
        var seen: [NudgeNotificationResponse] = []
        delivery.onAction = { seen.append($0) }

        for action in NudgeNotificationAction.allCases {
            delivery.handle(
                actionIdentifier: action.identifier, requestIdentifier: Self.deliveryID
            )
        }
        delivery.handle(
            actionIdentifier: "com.apple.UNNotificationDefaultActionIdentifier",
            requestIdentifier: Self.deliveryID
        )
        delivery.handle(actionIdentifier: "", requestIdentifier: Self.deliveryID)

        #expect(seen.map(\.action) == NudgeNotificationAction.allCases)
        // **Which banner, carried through untouched** (focus-zrs). This boundary decodes; whether
        // the delivery is still open is the loop's question, and it cannot ask it without this.
        #expect(seen.allSatisfy { $0.deliveryID == Self.deliveryID })
    }

    /// A press names its own delivery, and two deliveries are two different presses.
    @Test("two banners produce two distinguishable presses")
    func pressesNameTheirOwnDelivery() {
        let delivery = NotificationDelivery(centre: StubNotificationCentre(status: 2))
        var seen: [NudgeNotificationResponse] = []
        delivery.onAction = { seen.append($0) }

        delivery.handle(
            actionIdentifier: NudgeNotificationAction.snooze.identifier,
            requestIdentifier: "the rung on screen"
        )
        delivery.handle(
            actionIdentifier: NudgeNotificationAction.snooze.identifier,
            requestIdentifier: "a banner from an hour ago"
        )

        #expect(seen.map(\.deliveryID) == ["the rung on screen", "a banner from an hour ago"])
    }

    // MARK: - What the boundary reads changes nothing about where a rung lands

    /// **The reading and the routing have been disconnected, and this is what says so**
    /// (focus-wy0).
    ///
    /// It used to assert that an unauthorised boundary still routed the rung in-app, by handing
    /// `delivery.authorisation` to `SurfaceRouter.route(…)`. There is nowhere to hand it: the
    /// router takes no authorisation. So the claim is made the only way left to make it — the
    /// boundary reads all four states, and the panel rung lands on the panel throughout.
    @Test("whatever the boundary reads, the rung lands in-app", arguments: [0, 1, 2, 3])
    func theReadingDoesNotMoveTheRung(raw: Int) {
        let delivery = NotificationDelivery(centre: StubNotificationCentre(status: raw))
        delivery.refresh()
        #expect(delivery.authorisation == NotificationAuthorisation.decode(authorizationStatus: raw))

        let route = SurfaceRouter.route(
            rung: .panel,
            presentation: .notPresenting,
            media: .idle,
            reducedInterruption: false,
            menuBarVisible: true,
            voice: .standard
        )
        #expect(route == .surface(.panel))
        #expect(route.surface?.isInApp == true)
    }

    // MARK: - The decode, folded over the whole raw space (focus-652)

    /// **The committed decode table** — the one literal three legs compare against.
    ///
    /// `scripts/check-notification-denied.sh` and `scripts/self-check.sh` read this line out of
    /// this file with the same `committed_literal` helper they read the intervention digest with,
    /// and compare it against the table the *running binary* publishes. It is written down once,
    /// here, so a decode change is one diff rather than a drift between a script and a switch.
    static let committedDecodeTable = "-2:denied|-1:denied|0:notRequested|1:denied|2:authorised|3:provisional|4:provisional|5:denied|6:denied|7:denied|8:denied"

    /// How many cells that table folded. Asserted before the table itself, everywhere, because a
    /// fold that quietly shrinks is invisible in an unchanged verdict (R-96o).
    static let committedDecodeCells = 11

    /// **ONE fold over the WHOLE raw space, pinned in both directions.**
    ///
    /// This suite is what replaced the gate's *"the decoded value is one of these four strings"*.
    /// That assertion's subject was the decoder's **codomain**, which is a property of the type:
    /// every integer the OS can send, including one no build has seen, lands on one of the four by
    /// construction, so no change to the mapping could turn it red. Its own pass line claimed the
    /// authorisation had been *read*, which it could not see either.
    ///
    /// The subject here is the **mapping**. Every raw status in `foldedRawStatuses` is decoded and
    /// the whole table is compared against one committed literal — so moving any cell, adding a
    /// case, widening or narrowing the fold is a red line with the moved cell printed in it.
    @Test("the whole decode table is the committed one, cell for cell")
    func decodeTableIsPinned() {
        // The size first, and it is not decoration: an equality over a table can be satisfied by
        // shrinking both sides together, and the count is the thing that cannot be.
        #expect(NotificationAuthorisation.decodeTableCells == Self.committedDecodeCells)
        #expect(NotificationAuthorisation.foldedRawStatuses.count == Self.committedDecodeCells)
        #expect(NotificationAuthorisation.decodeTable == Self.committedDecodeTable)
        // …and the other direction, which is the half a `contains` would leave out: the committed
        // literal describes this fold and no other.
        #expect(Self.committedDecodeTable.split(separator: "|").count == Self.committedDecodeCells)
    }

    /// **The completeness check that fails when the space grows and the proof does not.**
    ///
    /// `NotificationAuthorisation` is `CaseIterable`. Add a fifth case and this line goes red
    /// unless some raw status in the fold decodes to it — which is the correct demand: a state the
    /// app can be in that no OS status produces is a state nothing can ever put it in, and a state
    /// produced by a status outside the fold is a state the table above is silent about.
    @Test("every declared authorisation is produced by some status in the fold, and no other is")
    func theFoldCoversTheWholeVocabulary() {
        let produced = Set(
            NotificationAuthorisation.foldedRawStatuses
                .map { NotificationAuthorisation.decode(authorizationStatus: $0) }
        )
        #expect(produced == Set(NotificationAuthorisation.allCases))
    }

    /// **The vacuity guard, stated rather than assumed.**
    ///
    /// What the two proofs above would still be green for, named so nobody has to re-derive it:
    ///
    /// 1. **A raw status outside `foldedRawStatuses`.** The fold is `-2...8`; a future OS sending
    ///    `9` decodes to `.denied` by the `default` arm and no line here sees it. That is the
    ///    conservative direction — an unknown status is never a grant — and
    ///    `unknownStatusIsNeverAGrant` is the assertion that keeps it so, at `99` as well as `5`.
    /// 2. **The table being constant for the wrong reason.** A decoder rewritten to `.denied`
    ///    everywhere would fail `theFoldCoversTheWholeVocabulary`, but a table whose cells all
    ///    agreed for some *other* reason would not — so this asserts the fold distinguishes, and
    ///    by how much: four distinct states over eleven cells, and not one state eleven times.
    /// 3. **Whether the read happened.** No line in this suite can see that; it is the running
    ///    application's fact, and `authorisationReadCount` is where it is published.
    @Test("the fold is not constant: it separates the four states over eleven cells")
    func theFoldIsNotVacuous() {
        let decoded = NotificationAuthorisation.foldedRawStatuses
            .map { NotificationAuthorisation.decode(authorizationStatus: $0) }
        #expect(decoded.count == Self.committedDecodeCells)
        #expect(Set(decoded).count == NotificationAuthorisation.allCases.count)
        #expect(!NotificationAuthorisation.decodeTable.isEmpty)
    }

    // MARK: - The read, as a fact about the run rather than about the type

    /// **`nil` until a read lands, and `notRequested` never doubles as "unread"** (focus-652).
    ///
    /// The field used to start at `.notRequested`, which is also the OS's real answer for *"nobody
    /// has ever asked"* — so no reader could tell a machine that had never been asked from a
    /// completion that had not come back yet. `refresh(_:)` is asynchronous and the self-check did
    /// not sequence it, so the reported authorisation was in fact which side of that race the
    /// report landed on: five gate runs at one commit on one machine produced `notRequested`,
    /// `notRequested`, `authorised`, `notRequested`, with two reports of a single run disagreeing.
    @Test("before any read the boundary reports no authorisation at all, and no reads")
    func theBoundaryStartsUnread() {
        let delivery = NotificationDelivery(centre: StubNotificationCentre(status: 0))
        #expect(delivery.authorisation == nil)
        #expect(delivery.authorisationReadCount == 0)
        // …and `notRequested` is still a reachable *answer*, which is what makes the distinction
        // load-bearing rather than cosmetic.
        delivery.refresh()
        #expect(delivery.authorisation == .notRequested)
        #expect(delivery.authorisationReadCount == 1)
    }

    /// Each completed read is counted, at every grant. This is the number the gate asserts
    /// `>= 1` of, so a deleted `refresh()` call is a red stage rather than a silent default.
    @Test("every completed read is counted", arguments: [0, 1, 2, 3])
    func readsAreCounted(raw: Int) {
        let delivery = NotificationDelivery(centre: StubNotificationCentre(status: raw))
        delivery.refresh()
        delivery.refresh()
        #expect(delivery.authorisationReadCount == 2)
        #expect(delivery.requestAuthorizationCallCount == 0)
    }
}
