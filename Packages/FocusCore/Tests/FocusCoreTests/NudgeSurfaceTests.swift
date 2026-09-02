import Foundation
import Testing

@testable import FocusCore

/// The surfaces, and the notification authorisation reduced to what it now is: **four names for
/// a reading, with no behaviour attached to any of them** (R-82, F-73, P-134, focus-wy0).
@Suite("Nudge surfaces")
struct NudgeSurfaceTests {
    @Test("there are exactly four surfaces, three of them in-app")
    func fourSurfaces() {
        #expect(NudgeSurface.allCases.count == 4)
        #expect(
            Set(NudgeSurface.allCases) == [.menuBar, .panel, .notification, .popoverBadge]
        )

        let inApp = NudgeSurface.allCases.filter(\.isInApp)
        #expect(Set(inApp) == [.menuBar, .panel, .popoverBadge])
        #expect(inApp.count == 3)
    }

    /// **The reason the `notification-denied` gate stage can exist at all.** Every rung has an
    /// in-app surface, so all three are deliverable with no grant of any kind — which is what
    /// discharges standing condition 5 for this epic.
    @Test("exactly one surface needs an authorisation, and it is the notification")
    func onlyOneSurfaceNeedsAGrant() {
        let gated = NudgeSurface.allCases.filter(\.requiresNotificationAuthorisation)
        #expect(gated == [.notification])
        for surface in NudgeSurface.allCases where surface.isInApp {
            #expect(!surface.requiresNotificationAuthorisation)
        }
    }

    /// **Two questions that were one predicate, and the cell where they part company**
    /// (focus-uru, focus-k42).
    ///
    /// `offersAnAnswer` asks *"can a person looking at this surface answer the nudge on it?"*;
    /// `holdsTheInterruptionSlot` asks *"is this surface occupied the moment a nudge lands on
    /// it?"*. They agree on three surfaces and differ on the badge, for one reason: the popover
    /// opens only when somebody clicks the status item, so a nudge routed there is answerable
    /// once looked at and has reached nobody until then.
    ///
    /// Asserted as an enumeration with the difference named, so that collapsing them back into
    /// one predicate — in either direction — is a red run. Collapsing towards the slot brings
    /// back focus-uru's unanswerable badge; collapsing towards the answer brings back focus-k42's
    /// badge that withholds every accusation for the rest of the session.
    ///
    /// **They differ on two surfaces now, and the second one is a ruling** (focus-3vb). A
    /// notification offers no answer because nothing can post one — no rung routes there since
    /// U-2, and P-134 measured `add(_:)` failing at zero grants — and the fold that ships in the
    /// **Release** binary collects the routes whose surface offers no answer, so this cell
    /// answering `true` made the one whole-space fold blind to the one outcome U-2 forbids. It
    /// still holds the slot, and the asymmetry is deliberate: the conservative direction for
    /// *"could the person answer this?"* is `false` and for *"is the screen taken?"* is `true`.
    @Test("answerability and slot ownership are different questions, and differ on two surfaces")
    func answerabilityIsNotSlotOwnership() {
        #expect(Set(NudgeSurface.allCases.filter(\.offersAnAnswer)) == [.panel, .popoverBadge])
        #expect(Set(NudgeSurface.allCases.filter(\.holdsTheInterruptionSlot))
            == [.panel, .notification])

        let disagree = NudgeSurface.allCases.filter {
            $0.offersAnAnswer != $0.holdsTheInterruptionSlot
        }
        #expect(
            Set(disagree) == [.popoverBadge, .notification],
            "the two predicates parted company somewhere new"
        )

        // The glyph is the one surface that is neither, and that is R-87: it is a state rather
        // than a sentence, it stays on through a snooze, and there is nothing on it to press.
        #expect(!NudgeSurface.menuBar.offersAnAnswer)
        #expect(!NudgeSurface.menuBar.holdsTheInterruptionSlot)
    }

    // MARK: - The authorisation states

    /// **A nudge that takes no screen must be visible in the menu bar, or it is visible
    /// nowhere** (focus-mkk, focus-2xw).
    ///
    /// The join, and it is deliberately *derived* from two predicates that were written for other
    /// reasons rather than restated as a third table. `holdsTheInterruptionSlot` is `false` for
    /// exactly the two surfaces that raise no window — the glyph and the badge — and those are
    /// exactly the two whose entire physical presence is the status item. So a surface that does
    /// not hold the slot and does not mark the item is a nudge with nowhere to be, which is what
    /// both beads measured: an ambient rung charged as a delivery against a menu bar that never
    /// changed, and a badge nudge waiting behind a click nothing had asked for.
    ///
    /// Written as an equality over `allCases` rather than four assertions, so a fifth surface
    /// cannot be added on one side of it.
    @Test("exactly the surfaces that raise no window mark the status item")
    func everySurfaceWithoutAWindowMarksTheItem() {
        for surface in NudgeSurface.allCases {
            #expect(
                surface.menuBarAttention.marksTheItem == !surface.holdsTheInterruptionSlot,
                """
                \(surface.rawValue) holds the slot: \(surface.holdsTheInterruptionSlot), \
                marks the item: \(surface.menuBarAttention.marksTheItem) — a nudge that takes \
                no screen and marks no item has reached nobody
                """
            )
        }
    }

    /// **The mark asks for a click exactly when there is an answer waiting that landing did not
    /// deliver** (focus-mkk, focus-2xw, R-87).
    ///
    /// Derived from `offersAnAnswer` and `reachesThePersonOnLanding` — neither of which was
    /// written for the menu bar — so the two marks cannot be collapsed into one without failing.
    ///
    /// Collapsing towards `.waiting` would invite a click onto the ambient rung, which R-87 says
    /// has nothing on it to answer and nothing about it that may be taken down: the person clicks
    /// and finds a glyph. Collapsing towards `.noticing` is focus-2xw itself, restated one level
    /// up — a nudge that *is* an accusation or a question, saying "nothing to answer".
    @Test("the mark invites a click only where an unopened answer is waiting")
    func onlyAnUnopenedAnswerInvitesAClick() {
        for surface in NudgeSurface.allCases {
            let waiting = surface.offersAnAnswer && !surface.reachesThePersonOnLanding
            #expect(
                surface.menuBarAttention.invitesAClick == waiting,
                """
                \(surface.rawValue) offers an answer: \(surface.offersAnAnswer), reaches on \
                landing: \(surface.reachesThePersonOnLanding), invites a click: \
                \(surface.menuBarAttention.invitesAClick)
                """
            )
        }
        // And the badge is the one that does, so the fold above is not vacuously satisfied by an
        // empty set — the shape `everyAccusationRouteCanBeAnswered` had when it was a tautology.
        #expect(
            NudgeSurface.allCases.filter(\.menuBarAttention.invitesAClick) == [.popoverBadge]
        )
    }

    /// Every mark has a sentence, and the unmarked item has none.
    ///
    /// The half a visual mark cannot cover: `MenuBarController.announceStatusChange` was keyed to
    /// `FocusStatus` and a rung landing changes no status, so somebody using VoiceOver was told
    /// nothing at all. A mark with no words would repair focus-2xw for sighted people alone.
    ///
    /// And `.unmarked` must stay wordless: an empty phrase appended to the status label reads as
    /// a pause to somebody listening, and would bless a catalog key nothing says.
    @Test("every mark carries a sentence, and the unmarked item carries none")
    func everyMarkHasASentence() {
        for attention in MenuBarAttention.allCases {
            #expect(
                (attention.copyKey != nil) == attention.marksTheItem,
                "\(attention.rawValue) marks the item: \(attention.marksTheItem), key: \(attention.copyKey ?? "none")"
            )
            #expect((attention.copyResource != nil) == attention.marksTheItem)
        }
        #expect(MenuBarAttention.allCases.compactMap(\.copyKey).count == 2)
    }

    /// The rank is the order of `allCases`, and `MenuBarPresentation.attention` takes the
    /// stronger of its two readings on the strength of it: a question waiting behind the click
    /// must not be reported as "nothing to answer" because an ambient rung is also up.
    @Test("waiting outranks noticing, which outranks an unmarked item")
    func theMarksAreOrdered() {
        #expect(MenuBarAttention.allCases == [.unmarked, .noticing, .waiting])
        #expect(MenuBarAttention.unmarked < .noticing)
        #expect(MenuBarAttention.noticing < .waiting)
        #expect(Swift.max(MenuBarAttention.noticing, .waiting) == .waiting)
    }

    @Test("there are exactly four authorisation states")
    func fourAuthorisationStates() {
        #expect(NotificationAuthorisation.allCases.count == 4)
        #expect(
            Set(NotificationAuthorisation.allCases)
                == [.authorised, .denied, .notRequested, .provisional]
        )
    }

    /// **R-82.2 in its final form** (focus-wy0). The ruling was that `denied` and `notRequested`
    /// are identical in what may be *delivered* and differ only in what may be *offered*. Both
    /// halves are now vacuous by construction, and the type says so rather than a test asserting
    /// it: nothing is delivered, so `permitsDelivery` is gone; nothing is offered, so
    /// `mayOfferToEnable` is gone with the button it gated. All four states behave identically
    /// because none of them reaches any behaviour at all.
    ///
    /// What is left is a name for a reading, and this is the assertion that keeps it that way: a
    /// property added back here would be a decision taken on a value nothing is entitled to
    /// decide on.
    @Test("no authorisation state carries any behaviour, in any of the four")
    func theAuthorisationDecidesNothing() {
        let fields = Set(
            NotificationAuthorisation.allCases.flatMap {
                Mirror(reflecting: $0).children.compactMap(\.label)
            }
        )
        #expect(fields.isEmpty, "an authorisation state grew a stored fact: \(fields.sorted())")

        // The one thing it still does: name itself, stably, for a report to print.
        #expect(
            NotificationAuthorisation.allCases.map(\.rawValue)
                == ["authorised", "denied", "notRequested", "provisional"]
        )
    }

    // MARK: - SurfaceRoute

    /// A route is not an `Optional<NudgeSurface>`: an absent surface has a reason, and the
    /// reason is what the record carries and what a person is told.
    @Test("a route answers exactly one of surface and deferral reason")
    func routeAnswersOneQuestion() {
        let routes: [SurfaceRoute] =
            NudgeSurface.allCases.map { .surface($0) }
            + DeferralReason.allCases.map { .unavailable($0) }

        for route in routes {
            let present = [route.surface != nil, route.deferralReason != nil].filter { $0 }
            #expect(present.count == 1, "\(route) answered more or fewer than one question")
        }
    }

    /// The one sanctioned bridge from a route to a delivery, so "no surface" and "deferred"
    /// cannot drift apart.
    @Test("a route becomes the delivery it describes, and a deferral is never a delivery")
    func routeBecomesItsDelivery() {
        for surface in NudgeSurface.allCases {
            #expect(SurfaceRoute.surface(surface).delivery == .delivered(surface))
            #expect(SurfaceRoute.surface(surface).delivery.deferralReason == nil)
        }
        for reason in DeferralReason.allCases {
            #expect(SurfaceRoute.unavailable(reason).delivery == .deferred(reason))
            #expect(SurfaceRoute.unavailable(reason).delivery.surface == nil)
        }
    }

    @Test("surfaces and authorisation states round-trip through Codable on their raw values")
    func codableRoundTrip() throws {
        for surface in NudgeSurface.allCases {
            let data = try JSONEncoder().encode(surface)
            #expect(try JSONDecoder().decode(NudgeSurface.self, from: data) == surface)
        }
        for state in NotificationAuthorisation.allCases {
            let data = try JSONEncoder().encode(state)
            #expect(try JSONDecoder().decode(NotificationAuthorisation.self, from: data) == state)
        }
    }
}
