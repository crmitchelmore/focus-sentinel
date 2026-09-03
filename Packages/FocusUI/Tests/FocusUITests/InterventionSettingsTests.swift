import FocusCore
import Foundation
import SwiftUI
import Testing

@testable import FocusUI

enum InterventionSettingsFixture {
    /// The commitment the usage rows are summed against.
    static let priority = UUID(uuidString: "5E771465-0000-4000-8000-000000000001")!

    /// The shipping default: quiet hours off, the Court's deck, nothing spent today. **This is
    /// the fresh-install state**, and the state the pane used to offer a system notification
    /// prompt in (focus-wy0).
    static let fresh = InterventionSettings()

    /// A day partway through, so the usage rows have something to say.
    static let midDay = InterventionSettings(
        // Folded from charges, because `InterruptionBudget` has no other producer (focus-d6r):
        // two questions under this commitment, one under an earlier one, and two accusations —
        // five interruptions, which the type derives rather than being told.
        usage: .spent(
            [
                InterruptionCharge(.query, priorityID: priority),
                InterruptionCharge(.query, priorityID: priority),
                InterruptionCharge(.query, priorityID: UUID()),
                InterruptionCharge(.accusation, priorityID: priority),
                InterruptionCharge(.accusation, priorityID: priority)
            ],
            underPriority: priority
        )
    )

    static let quiet = InterventionSettings(
        quietHours: InterventionSettingsView.startingWindow
    )

    static let reduced = InterventionSettings(
        voice: .silentVisual,
        reducedInterruption: true,
        reducedInterruptionIsForced: true
    )
}

/// **The pane that answers "where does a nudge appear, and when will it leave me alone"**
/// (R-98, R-82, R-92).
///
/// It used to answer a third question — *"what does this app do if I say no about
/// notifications"* — with a section, a "Turn on notifications" button and a routing column.
/// focus-wy0 removed all three, because the honest answer had become "nothing, and it will never
/// ask": no rung routes to a notification, so the button raised a real system prompt to buy a
/// capability the router could not spend.
@Suite("The Intervention settings pane")
@MainActor
struct InterventionSettingsTests {
    // MARK: - The rendered matrix IS the router's table

    /// **The assertion this pane exists for.** R-82 makes the routing table a value precisely so
    /// this pane can render it; if the pane derived its own rows the copy would be free to drift
    /// from the behaviour, which is the failure the ruling is about.
    @Test(
        "the rendered matrix equals SurfaceRouter's own table, for every voice and both flags",
        arguments: NudgeVoice.allCases, [false, true]
    )
    func matrixEqualsTheRouter(voice: NudgeVoice, reduced: Bool) {
        let view = InterventionSettingsView(
            settings: InterventionSettings(voice: voice, reducedInterruption: reduced)
        )
        #expect(
            view.drawnRows == SurfaceRouter.table(reducedInterruption: reduced, voice: voice)
        )
    }

    /// **Every rung has exactly one row, and no rung has four** (focus-wy0).
    ///
    /// The matrix was a rung × authorisation cross product. Since U-2 the four rows a rung
    /// produced were identical — same route, four headings — so the pane was drawing a
    /// consequence the router does not produce. This fails if the column comes back.
    @Test("every rung has a row, and exactly one")
    func matrixIsComplete() {
        let rows = InterventionSettingsView(settings: .init()).drawnRows

        #expect(rows.count == LadderRung.Kind.allCases.count)
        #expect(rows.map(\.rung) == LadderRung.Kind.allCases)
        #expect(Set(rows.map(\.rung)).count == rows.count)
    }

    /// The honest answer the pane promises: **no rung has nowhere to go** in the conditions the
    /// table describes, **and every row the pane lays out has a sentence for its surface**.
    ///
    /// The second half is the one focus-pzl added, and it is the guard that replaces two deleted
    /// strings. `surfaceKey` is partial now: `.surface(.notification)` and `.unavailable` answer
    /// `nil`, because the pane had shipped copy for both and no route could produce either.
    /// `routingMatrix` draws no row for a `nil`, so this is what stops that silence being a
    /// silence — the day `SurfaceRouter` produces a route with no sentence, this fails here
    /// rather than dropping a rung out of the pane on somebody's Mac.
    @Test("every drawn row goes somewhere, and every drawn row has a sentence for where")
    func everyDrawnRowHasASentence() {
        var drawn: Set<ShellStringKey> = []
        for voice in NudgeVoice.allCases {
            for reduced in [false, true] {
                let view = InterventionSettingsView(
                    settings: InterventionSettings(voice: voice, reducedInterruption: reduced)
                )
                #expect(!view.drawnRows.isEmpty)
                for row in view.drawnRows {
                    #expect(row.route.surface != nil)
                    let key = InterventionSettingsView.surfaceKey(row.route)
                    #expect(
                        key != nil,
                        """
                        \(voice.rawValue)/reduced=\(reduced) drew \(row.rung.rawValue) with no \
                        sentence for \(row.route)
                        """
                    )
                    if let key { drawn.insert(key) }
                }
            }
        }
        // Non-vacuity, and the census the deletion rests on: over the whole cross-product the
        // pane reaches exactly three surfaces. A fourth appearing here means a route came back.
        #expect(
            drawn == [
                .interventionSurfaceMenuBar,
                .interventionSurfacePanel,
                .interventionSurfacePopoverBadge
            ],
            "the pane reached \(drawn.map(\.rawValue).sorted())"
        )
    }

    /// **The pane cannot draw a notification authorisation, because it does not hold one**
    /// (focus-wy0).
    ///
    /// This replaces "the matrix shows denied and not-asked reaching the same surface": that was
    /// true because nothing read the value, and a pane asserting agreement between four headings
    /// over one route is a pane certifying its own repetition. The claim that matters now is that
    /// the field is not there to be drawn — so no state of it can reach a person, and no fresh
    /// install can be shown an offer to change it.
    @Test("nothing in what the pane is handed names a notification authorisation")
    func thePaneHoldsNoAuthorisation() {
        let fields = Mirror(reflecting: InterventionSettingsFixture.fresh)
            .children.compactMap(\.label).sorted()

        #expect(!fields.contains("authorisation"), "the pane got its authorisation back: \(fields)")
        // **And no presentation-exclusion list**, which went with the section that instructed
        // the person to add an app the application offered no way to add (focus-1qm).
        #expect(fields == [
            "quietHours", "reducedInterruption", "reducedInterruptionIsForced", "usage", "voice"
        ])
        // …and the only requests it can make are the three that change a setting.
        #expect(!InterventionSettingsView(settings: .init()).drawnRows.isEmpty)
    }

    // MARK: - Every closed vocabulary has a name in this pane

    /// **The voices are total; the surfaces are deliberately not** (focus-pzl).
    ///
    /// This asserted that every `NudgeSurface` and every `DeferralReason` had a label, and it was
    /// the proof that let two unreachable sentences ship: `NudgeSurface.notification` is declared
    /// and reached by nothing, `.unavailable` cannot come out of `SurfaceRouter.table(…)` at all,
    /// and a test that walks `allCases` through a mapping function cannot tell a route the pane
    /// draws from a route the pane can be handed. What the pane *draws* is asserted by
    /// `everyDrawnRowHasASentence`, over the router's own output.
    ///
    /// So the surface half is inverted: the two routes outside the pane's domain must have **no**
    /// sentence, which is what stops the copy coming back without a route to reach it.
    @Test("every voice has a label, and no route outside the pane's domain has one")
    func vocabulariesAreTotal() {
        var keys: Set<ShellStringKey> = []
        for voice in NudgeVoice.allCases {
            keys.insert(InterventionSettingsView.voiceKey(voice))
        }
        #expect(keys.count == NudgeVoice.allCases.count)

        for surface in NudgeSurface.allCases where surface != .notification {
            #expect(InterventionSettingsView.surfaceKey(.surface(surface)) != nil)
        }
        #expect(InterventionSettingsView.surfaceKey(.surface(.notification)) == nil)
        for reason in DeferralReason.allCases {
            #expect(InterventionSettingsView.surfaceKey(.unavailable(reason)) == nil)
        }

        // The three that remain read differently from one another, so the column is a column.
        let sentences = NudgeSurface.allCases
            .compactMap { InterventionSettingsView.surfaceKey(.surface($0)) }
            .map { ShellStrings.string($0) }
        #expect(sentences.count == 3)
        #expect(Set(sentences).count == 3, "two surfaces read the same: \(sentences)")
    }

    // MARK: - The two columns, and neither may do the other's job (focus-91d)

    /// **The vocabulary the surface column owns**, derived from the surface labels themselves
    /// rather than written down as a list somebody has to maintain.
    ///
    /// Words of three letters or more, from every drawn `NudgeSurface` label. The unavailable
    /// label used to be excluded by hand here — *"Nowhere right now"* names an absence, not a
    /// surface — and since focus-pzl there is no such label to exclude: `surfaceKey` answers
    /// `nil` for every route this pane cannot be handed, so `compactMap` is the exclusion.
    static func surfaceVocabulary() -> Set<String> {
        var words: Set<String> = []
        for surface in NudgeSurface.allCases {
            guard let key = InterventionSettingsView.surfaceKey(.surface(surface)) else { continue }
            let label = String(localized: ShellStrings.resource(key))
            words.formUnion(Self.words(in: label))
        }
        return words
    }

    /// Articles. They belong to no column: a rung named *"The next step"* would share "the" with
    /// *"The menu-bar popover"* and be describing nothing about a surface.
    static let articles: Set<String> = ["the", "and"]

    static func words(in sentence: String) -> Set<String> {
        Set(
            sentence.lowercased()
                .split(whereSeparator: { !$0.isLetter && $0 != "-" })
                .map(String.init)
                .filter { $0.count >= 3 }
        ).subtracting(Self.articles)
    }

    /// **A routing row must never name a rung by an affordance its own surface does not offer**
    /// (focus-91d).
    ///
    /// ## The defect
    ///
    /// `nudge.rung.panel` was *"A small panel you can answer"* and the pane draws it beside the
    /// route. Under the Silent-and-visual deck the row read **"A small panel you can answer │
    /// Menu bar"**: a panel, in the menu bar, where nothing can be answered — on the one surface
    /// whose whole design principle (R-82) is that it *is* the behaviour, so the copy cannot
    /// drift. And it was not one deck. With reduced interruption on — a checkbox, and what macOS
    /// Reduce Motion forces — every deck drew "A small panel you can answer │ The menu-bar
    /// popover". `nudge.rung.ambient` had the mirror of it: *"A quiet change in the menu bar"*,
    /// which puts the surface column's answer in the rung column and reads as a tautology beside
    /// it.
    ///
    /// ## The rule, rather than the cell
    ///
    /// The rung column names the **step**; the surface column names the **place**. Neither may
    /// do the other's job, and that is checkable without knowing which deck anybody is holding:
    /// no rung's label may use any word the surface labels use. A rung named for a surface is
    /// wrong wherever it is drawn — including the popover's *"Current nudge: …"* belief row, which
    /// draws the same `copyResource` with no second column to correct it, which is why the fold
    /// below covers every rung and not only the rows this pane happens to lay out.
    @Test(
        "no rung is named for a surface, in any deck or either flag",
        .enabled(if: LocalizationLane.catalogsAreCompiled)
    )
    func noRungIsNamedForASurface() {
        let forbidden = Self.surfaceVocabulary()
        #expect(!forbidden.isEmpty, "the surface labels resolved to nothing, so this proves nothing")

        // Every rung, wherever it is drawn — the pane's rung column and the popover's belief row
        // read the same resource.
        for rung in LadderRung.Kind.allCases {
            let label = String(localized: rung.copyResource)
            #expect(label != rung.copyKey, "\(rung.rawValue) resolved to its own key")
            let overlap = Self.words(in: label).intersection(forbidden).sorted()
            #expect(
                overlap.isEmpty,
                """
                the rung \(rung.rawValue) is named by the surface column's own vocabulary \
                \(overlap): "\(label)". The rung column says which step; the surface column \
                says where it appears.
                """
            )
        }

        // And every row this pane actually lays out, over every deck and both flags — because
        // the defect was a *pair* of cells, and a rung label can only be judged beside the
        // surface it was drawn next to.
        for voice in NudgeVoice.allCases {
            for reduced in [false, true] {
                let view = InterventionSettingsView(
                    settings: InterventionSettings(voice: voice, reducedInterruption: reduced)
                )
                for row in view.drawnRows {
                    let rung = String(localized: row.rung.copyResource)
                    // A row with no key is not drawn at all, and `everyDrawnRowHasASentence`
                    // is where that is a failure rather than a skip.
                    guard let key = InterventionSettingsView.surfaceKey(row.route) else { continue }
                    let surface = String(localized: ShellStrings.resource(key))
                    #expect(
                        rung != surface,
                        "\(voice.rawValue)/reduced=\(reduced) drew one sentence twice: \(rung)"
                    )
                    #expect(
                        Self.words(in: rung).intersection(Self.words(in: surface)).isEmpty,
                        """
                        \(voice.rawValue)/reduced=\(reduced) drew "\(rung) │ \(surface)", \
                        which names the rung by its surface
                        """
                    )
                }
            }
        }
    }

    // MARK: - Quiet hours: off by default, and no bundled window (R-85)

    @Test("the shipped default is no window at all")
    func quietHoursDefaultIsOff() {
        #expect(InterventionPolicy.quietHoursDefault == nil)
        #expect(InterventionSettingsFixture.fresh.quietHours == nil)
        #expect(!QuietHours.off.isEnabled)
    }

    /// The starting window is the beginning of an edit somebody deliberately began, not the
    /// app's opinion about their evenings — so it exists only in the pane, never in the policy.
    @Test("switching quiet hours on begins an edit rather than applying a shipped opinion")
    func turningQuietHoursOnStartsAnEdit() {
        var seen: [InterventionSettingsAction] = []
        let view = InterventionSettingsView(settings: .init()) { seen.append($0) }

        view.onAction(.setQuietHours(InterventionSettingsView.startingWindow))
        view.onAction(.setQuietHours(nil))

        #expect(seen == [
            .setQuietHours(InterventionSettingsView.startingWindow),
            .setQuietHours(nil)
        ])
        // …and the policy is untouched by it.
        #expect(InterventionPolicy.quietHoursDefault == nil)
    }

    @Test("moving a boundary wraps midnight rather than clamping or going negative")
    func boundariesWrap() {
        let window = QuietHoursWindow(startMinuteOfDay: 15, endMinuteOfDay: 1_425)

        let earlier = InterventionSettingsView.moved(window, startBy: -30)
        #expect(earlier.startMinuteOfDay == 1_425)

        let later = InterventionSettingsView.moved(window, endBy: 30)
        #expect(later.endMinuteOfDay == 15)

        // Every reachable position stays inside a day, in both directions.
        var walked = window
        for _ in 0..<100 {
            walked = InterventionSettingsView.moved(walked, startBy: 30, endBy: -30)
            #expect((0..<InterventionSettingsView.minutesPerDay).contains(walked.startMinuteOfDay))
            #expect((0..<InterventionSettingsView.minutesPerDay).contains(walked.endMinuteOfDay))
        }
    }

    /// **The window is drawn in the person's own clock** (focus-43k).
    ///
    /// Red before this round on the `en_US` half: `render` was `String(format: "%02d:%02d")`
    /// twice with an authored en dash, so a Mac set to a 12-hour clock was shown `22:00 – 08:00`.
    /// The 24-hour half is what it always drew, and it still must — a locale whose clock is
    /// 24-hour keeps its zero-padded digits. The separator is the catalog's, so it is asserted
    /// through the same key the row draws rather than as a literal a translation could not move.
    @Test(
        "a window is drawn in the locale's own clock, joined by the catalog's separator",
        .enabled(if: LocalizationLane.catalogsAreCompiled)
    )
    func windowRendering() {
        let separator = String(localized: ShellStrings.resource(.interventionQuietHoursRange))
        #expect(separator.contains("%1$@") && separator.contains("%2$@"))

        let british = InterventionSettingsView.render(
            InterventionSettingsView.startingWindow, locale: Locale(identifier: "en_GB")
        )
        #expect(british == String(format: separator, arguments: ["22:00", "08:00"]))
        #expect(
            InterventionSettingsView.render(
                QuietHoursWindow(startMinuteOfDay: 0, endMinuteOfDay: 545),
                locale: Locale(identifier: "en_GB")
            ) == String(format: separator, arguments: ["00:00", "09:05"])
        )

        // A 12-hour clock: `10:00 PM – 8:00 AM`-shaped. The space before the day period is the
        // locale's own (a narrow no-break space on current macOS), so the shape is asserted
        // rather than the exact bytes.
        let american = InterventionSettingsView.render(
            InterventionSettingsView.startingWindow, locale: Locale(identifier: "en_US")
        )
        #expect(american.hasPrefix("10:00"), "en_US drew \(american)")
        #expect(american.contains("PM") && american.contains("AM"), "en_US drew \(american)")
        #expect(!american.contains("22:00"), "en_US drew a 24-hour clock: \(american)")
        #expect(
            InterventionSettingsView.clock(8 * 60, locale: Locale(identifier: "en_US")).hasPrefix("8:00")
        )
    }

    // MARK: - The caps are mirrors, not a second copy

    /// A threshold written down twice is a threshold that drifts, so the pane holds none of its
    /// own: this asserts the numbers it draws come from `InterventionPolicy` and e04's
    /// `RelevancePolicy`, unchanged.
    @Test("the caps and thresholds shown are the policy's own values")
    func capsAreMirrors() {
        #expect(InterventionPolicy.dailyQueryCap == 4)
        #expect(InterventionPolicy.dailyQueryCapAllPriorities == 5)
        #expect(InterventionPolicy.dailyAccusationCap == 6)
        #expect(InterventionPolicy.dailyInterruptionCap == 8)
        // The ordering the pane's four rows imply, asserted so the rows cannot describe a
        // budget arrangement the controller does not implement.
        #expect(
            InterventionPolicy.dailyInterruptionCap
                < InterventionPolicy.dailyQueryCap + InterventionPolicy.dailyAccusationCap
        )
        #expect(
            InterventionPolicy.dailyQueryCap <= InterventionPolicy.dailyQueryCapAllPriorities
        )
        #expect(InterventionPolicy.queryCooldown == RelevancePolicy.lookBackSpan)
        #expect(InterventionPolicy.queryDwellThreshold * 2 == RelevancePolicy.sustainedDriftThreshold)
    }

    // MARK: - No control on this pane asks for a permission (focus-wy0)

    /// **The pane has no request that could reach a system permission dialog.**
    ///
    /// This replaces "the enable action is offered only where nobody has been asked", which was
    /// F-127's never-re-prompt policy applied to a prompt that should not have existed at all:
    /// `mayOfferToEnable` was `notRequested` alone, `notRequested` is what every fresh install
    /// reports, and the button behind it called the real `UNUserNotificationCenter` for a
    /// capability no rung could use. Every action this pane can raise is now a setting change,
    /// and the vocabulary is closed — a case added here has to be justified against this test.
    @Test("every request the pane can make changes a setting, and none asks for a permission")
    func noControlAsksForAPermission() {
        // A **total** switch, so a case added to the vocabulary is a compile error here rather
        // than a control this test silently stops covering.
        func changesASetting(_ action: InterventionSettingsAction) -> Bool {
            switch action {
            case .setVoice, .setReducedInterruption, .setQuietHours:
                true
            }
        }
        #expect(changesASetting(.setVoice(.warm)))
        #expect(changesASetting(.setReducedInterruption(true)))
        #expect(changesASetting(.setQuietHours(nil)))

        var seen: [InterventionSettingsAction] = []
        let view = InterventionSettingsView(settings: InterventionSettingsFixture.midDay) {
            seen.append($0)
        }

        view.onAction(.setVoice(.warm))
        view.onAction(.setReducedInterruption(true))
        view.onAction(.setQuietHours(nil))

        #expect(seen == [
            .setVoice(.warm),
            .setReducedInterruption(true),
            .setQuietHours(nil)
        ])
    }

    // MARK: - The tab

    @Test("the Settings window has three full tabs and the new one is named")
    func settingsTabs() {
        #expect(SettingsTab.allCases == [.general, .intervention, .privacy])
        #expect(SettingsTab.intervention.titleKey == .interventionTitle)
        #expect(Set(SettingsTab.allCases.map(\.systemImage)).count == SettingsTab.allCases.count)
    }
}

@Suite("Intervention settings snapshots", .enabled(if: LocalizationLane.catalogsAreCompiled))
@MainActor
struct InterventionSettingsSnapshotTests {
    /// The width the pane commits to, plus the harness's own 16-point padding on each side, so
    /// the pane is proposed exactly `settingsWidth` (focus-nu6). `screens: []` at every call site
    /// below is what makes the picture machine-independent: the container's ceiling is derived
    /// from the live display, and a baseline whose dimensions follow the monitor is not one.
    static let paneWidth: CGFloat = ShellSurfaceBounds.settingsWidth + 32

    /// The four states, as four **independent** cases rather than one loop.
    ///
    /// A loop stops at its first `throw`, so a run that had lost more than one baseline — or a
    /// change that moved more than one state — reported the first and hid the rest, and a
    /// reviewer re-ran the gate once per picture to see them all. One case per state says
    /// everything that moved in one run.
    @Test(
        "the pane in its four states",
        arguments: ["fresh", "midDay", "quiet", "reduced"]
    )
    func states(_ state: String) throws {
        let settings: InterventionSettings
        switch state {
        case "fresh": settings = InterventionSettingsFixture.fresh
        case "midDay": settings = InterventionSettingsFixture.midDay
        case "quiet": settings = InterventionSettingsFixture.quiet
        case "reduced": settings = InterventionSettingsFixture.reduced
        default:
            Issue.record("no fixture named \(state)")
            return
        }
        // Pinned to a named locale, so the quiet-hours clock in the picture is a fact about the
        // code and not about the Mac that recorded it (focus-43k).
        try SnapshotHarness.assertSnapshot(
            InterventionSettingsView(settings: settings, screens: [])
                .environment(\.locale, Locale(identifier: "en_GB")),
            component: "interventionSettings.\(state)",
            variant: "light",
            width: Self.paneWidth
        )
    }

    /// **The same window on a 12-hour clock** (focus-43k). The baseline above is the 24-hour
    /// picture; this is the one a person in the United States sees, and it is committed because a
    /// formatter change is exactly the kind that produces a plausible-looking wrong string.
    @Test("the quiet-hours window on a 12-hour clock")
    func quietHoursOnATwelveHourClock() throws {
        try SnapshotHarness.assertSnapshot(
            InterventionSettingsView(settings: InterventionSettingsFixture.quiet, screens: [])
                .environment(\.locale, Locale(identifier: "en_US")),
            component: "interventionSettings.quiet.en_US",
            variant: "light",
            width: Self.paneWidth
        )
    }

    @Test(
        "the pane survives the appearance variants at both text sizes",
        arguments: ["dark", "increasedContrast", "reduceTransparency"], SnapshotTypeSize.allCases
    )
    func appearanceVariants(variant: String, size: SnapshotTypeSize) throws {
        try SnapshotHarness.assertSnapshot(
            InterventionSettingsView(settings: InterventionSettingsFixture.midDay, screens: []),
            component: "interventionSettings",
            variant: variant,
            textScale: size.textScale,
            width: Self.paneWidth
        )
    }

    /// Reduced interruption changes the routing table the pane renders, so it must change the
    /// picture — otherwise the pane would be promising something the router does not do.
    @Test("turning interruption down changes the matrix a person is shown")
    func reducedInterruptionChangesTheMatrix() throws {
        let normal = try SnapshotHarness.render(
            InterventionSettingsView(settings: InterventionSettingsFixture.fresh),
            traits: SnapshotHarness.variantTraits(named: "light"),
            width: Self.paneWidth,
            name: "interventionSettings.distinctness.normal"
        )
        let reduced = try SnapshotHarness.render(
            InterventionSettingsView(settings: InterventionSettingsFixture.reduced),
            traits: SnapshotHarness.variantTraits(named: "light"),
            width: Self.paneWidth,
            name: "interventionSettings.distinctness.reduced"
        )
        #expect(PNGCompare.areDistinct(normal.pixels, reduced.pixels))
    }
}
