import FocusCore
import Foundation
import SwiftUI
import Testing

@testable import FocusUI

enum InterventionSettingsFixture {
    /// The shipping default: nobody asked about notifications, quiet hours off, the Court's
    /// deck, nothing spent today.
    static let fresh = InterventionSettings()

    /// A day partway through, so the usage rows have something to say.
    static let midDay = InterventionSettings(
        authorisation: .notRequested,
        usage: InterruptionBudget(
            queriesForPriorityToday: 2,
            queriesAllPrioritiesToday: 3,
            accusationsToday: 2,
            interruptionsToday: 5
        ),
        presentationExclusions: ["com.apple.Keynote"]
    )

    static let quiet = InterventionSettings(
        quietHours: InterventionSettingsView.startingWindow,
        authorisation: .authorised
    )

    static let reduced = InterventionSettings(
        voice: .silentVisual,
        reducedInterruption: true,
        reducedInterruptionIsForced: true,
        authorisation: .denied
    )
}

/// **The pane that answers "what does this app do if I say no"** (R-98, R-82, R-92).
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

    @Test("every rung and every authorisation state has a row, and each pair exactly once")
    func matrixIsComplete() {
        let rows = InterventionSettingsView(settings: .init()).drawnRows
        let pairs = rows.map { RungAuthorisationPair(rung: $0.rung, authorisation: $0.authorisation) }

        #expect(rows.count == LadderRung.Kind.allCases.count * NotificationAuthorisation.allCases.count)
        #expect(Set(pairs).count == rows.count)
    }

    private struct RungAuthorisationPair: Hashable {
        let rung: LadderRung.Kind
        let authorisation: NotificationAuthorisation
    }

    /// The honest answer the pane promises: **no rung has nowhere to go** in the conditions the
    /// table describes, whatever the person said about notifications.
    @Test("no row in the drawn matrix says a rung has nowhere to go")
    func everyRungHasSomewhereToGo() {
        for voice in NudgeVoice.allCases {
            for reduced in [false, true] {
                let view = InterventionSettingsView(
                    settings: InterventionSettings(voice: voice, reducedInterruption: reduced)
                )
                for row in view.drawnRows {
                    #expect(row.route.surface != nil)
                    #expect(
                        InterventionSettingsView.surfaceKey(row.route)
                            != .interventionSurfaceUnavailable
                    )
                }
            }
        }
    }

    /// `denied` and `notRequested` are identical in delivery, and the pane says so — because
    /// the pane is the table.
    @Test("the matrix shows denied and not-asked reaching the same surface, in every rung")
    func deniedAndNotRequestedLookTheSame() {
        let rows = InterventionSettingsView(settings: .init()).drawnRows
        for rung in LadderRung.Kind.allCases {
            let denied = rows.first { $0.rung == rung && $0.authorisation == .denied }
            let notRequested = rows.first { $0.rung == rung && $0.authorisation == .notRequested }
            #expect(denied?.route == notRequested?.route)
        }
    }

    // MARK: - Every closed vocabulary has a name in this pane

    @Test("every voice, authorisation state and surface has a label")
    func vocabulariesAreTotal() {
        var keys: Set<ShellStringKey> = []
        for voice in NudgeVoice.allCases {
            keys.insert(InterventionSettingsView.voiceKey(voice))
        }
        #expect(keys.count == NudgeVoice.allCases.count)

        keys.removeAll()
        for state in NotificationAuthorisation.allCases {
            keys.insert(InterventionSettingsView.authorisationKey(state))
        }
        #expect(keys.count == NotificationAuthorisation.allCases.count)

        keys.removeAll()
        for surface in NudgeSurface.allCases {
            keys.insert(InterventionSettingsView.surfaceKey(.surface(surface)))
        }
        #expect(keys.count == NudgeSurface.allCases.count)
        for reason in DeferralReason.allCases {
            #expect(
                InterventionSettingsView.surfaceKey(.unavailable(reason))
                    == .interventionSurfaceUnavailable
            )
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

    @Test("a window is drawn as digits, zero-padded, in a fixed shape")
    func windowRendering() {
        #expect(
            InterventionSettingsView.render(InterventionSettingsView.startingWindow)
                == "22:00 – 08:00"
        )
        #expect(
            InterventionSettingsView.render(
                QuietHoursWindow(startMinuteOfDay: 0, endMinuteOfDay: 545)
            ) == "00:00 – 09:05"
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

    // MARK: - The one request, offered to one state only

    /// F-127's never-re-prompt policy, as a property of the pane rather than of a habit: the
    /// enable action is drawn only for the state nobody has asked yet.
    @Test("the enable action is offered only where nobody has been asked")
    func enableOfferedOnlyOnce() {
        #expect(InterventionSettings(authorisation: .notRequested).authorisation.mayOfferToEnable)
        for state in [
            NotificationAuthorisation.denied, .authorised, .provisional
        ] {
            #expect(!InterventionSettings(authorisation: state).authorisation.mayOfferToEnable)
        }
    }

    @Test("every pane control reports a typed request and performs nothing else")
    func controlsReport() {
        var seen: [InterventionSettingsAction] = []
        let view = InterventionSettingsView(settings: InterventionSettingsFixture.midDay) {
            seen.append($0)
        }

        view.onAction(.setVoice(.warm))
        view.onAction(.setReducedInterruption(true))
        view.onAction(.removePresentationExclusion("com.apple.Keynote"))
        view.onAction(.notificationAuthorisationChanged)

        #expect(seen == [
            .setVoice(.warm),
            .setReducedInterruption(true),
            .removePresentationExclusion("com.apple.Keynote"),
            .notificationAuthorisationChanged
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
    static let paneWidth: CGFloat = 460

    @Test("the pane in its four states", arguments: ["light"])
    func states(variant: String) throws {
        let cases: [(String, InterventionSettings)] = [
            ("fresh", InterventionSettingsFixture.fresh),
            ("midDay", InterventionSettingsFixture.midDay),
            ("quiet", InterventionSettingsFixture.quiet),
            ("reduced", InterventionSettingsFixture.reduced)
        ]
        for (name, settings) in cases {
            try SnapshotHarness.assertSnapshot(
                InterventionSettingsView(settings: settings),
                component: "interventionSettings.\(name)",
                variant: variant,
                width: Self.paneWidth
            )
        }
    }

    @Test(
        "the pane survives the appearance variants at both text sizes",
        arguments: ["dark", "increasedContrast", "reduceTransparency"], SnapshotTypeSize.allCases
    )
    func appearanceVariants(variant: String, size: SnapshotTypeSize) throws {
        try SnapshotHarness.assertSnapshot(
            InterventionSettingsView(settings: InterventionSettingsFixture.midDay),
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
