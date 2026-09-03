import FocusCore
import SwiftUI
import Testing

@testable import FocusUI

/// Hosts a component that wants a `@FocusState` binding.
///
/// Four of e02's surfaces take a `FocusState<FocusField?>.Binding` — the keyboard-traversal
/// contract is expressed by the cockpit owning one focus state and lending it out — and a
/// binding like that can only be made inside a `View`. This is the smallest thing that is one.
struct FocusHost<Content: View>: View {
    @FocusState private var focus: FocusField?
    let content: (FocusState<FocusField?>.Binding) -> Content

    init(@ViewBuilder content: @escaping (FocusState<FocusField?>.Binding) -> Content) {
        self.content = content
    }

    var body: some View {
        content($focus)
    }
}

/// The fixture values every priority render is drawn from.
///
/// Fixed, and fixed in a *file*: a baseline whose content depends on the clock, the locale or
/// the machine is a baseline that fails on somebody else's Tuesday. Every date here is an
/// explicit `timeIntervalSince1970` — `Date()` is banned repository-wide, tests included, for
/// exactly this reason (R-26).
enum PriorityFixture {
    /// 2026-01-01T00:00:00Z.
    static let now = Date(timeIntervalSince1970: 1_767_225_600)

    static let id = UUID(uuidString: "E0200000-0000-4000-A000-000000000001")!

    /// A real sentence, well-formed by the validator's rules: a leading imperative verb and a
    /// concrete outcome.
    static let intent = "Finish and submit the Q3 partnership proposal"

    /// 180 characters, for the F-147 resilience proofs. The promise is that this wraps and
    /// stays legible at the largest text size, so the fixture has to be long enough to make
    /// the promise mean something.
    static let longIntent = String(
        repeating: "Finish the quarterly partnership proposal and send it to legal. ",
        count: 3
    ).prefix(180).description

    static let contextItems: [ContextItemValue] = [
        ContextItemValue.app(
            bundleID: "com.apple.Safari",
            displayName: "Safari",
            addedAt: now,
            id: UUID(uuidString: "E0200000-0000-4000-A000-000000000011")!
        ),
        ContextItemValue.domain(
            origin: "https://docs.example.com",
            addedAt: now,
            id: UUID(uuidString: "E0200000-0000-4000-A000-000000000012")!
        )!,
        ContextItemValue.keyword(
            "partnership",
            addedAt: now,
            id: UUID(uuidString: "E0200000-0000-4000-A000-000000000013")!
        )!,
        ContextItemValue(
            id: UUID(uuidString: "E0200000-0000-4000-A000-000000000014")!,
            kind: .file,
            value: "/Users/example/Documents/proposal.pdf",
            displayName: "proposal.pdf",
            addedAt: now
        ),
        // A file whose disk went away. It is drawn as *missing*, with a Locate… action, and is
        // never removed — deleting somebody's context because a volume was unplugged is a bug,
        // not tidiness (R-22).
        ContextItemValue(
            id: UUID(uuidString: "E0200000-0000-4000-A000-000000000015")!,
            kind: .file,
            value: "/Volumes/Archive/last-year.key",
            displayName: "last-year.key",
            addedAt: now,
            availability: .missing
        ),
        // A kind written by a later version of the app. It renders as an inert chip rather
        // than crashing or vanishing — forward compatibility you can look at.
        ContextItemValue(
            id: UUID(uuidString: "E0200000-0000-4000-A000-000000000016")!,
            kind: ContextItemKind(rawValue: "person"),
            value: "someone",
            displayName: "someone",
            addedAt: now,
            availability: .unknownKind
        )
    ]

    static let rules: [PriorityRuleValue] = [
        PriorityRuleValue(
            id: UUID(uuidString: "E0200000-0000-4000-A000-000000000021")!,
            scope: .app,
            subject: "com.apple.Safari",
            verdict: .relevant,
            createdAt: now
        ),
        PriorityRuleValue(
            id: UUID(uuidString: "E0200000-0000-4000-A000-000000000022")!,
            scope: .domain,
            subject: "https://news.example.com",
            verdict: .unrelated,
            createdAt: now
        ),
        PriorityRuleValue(
            id: UUID(uuidString: "E0200000-0000-4000-A000-000000000023")!,
            scope: .session,
            subject: "proposal",
            verdict: .uncertain,
            createdAt: now
        )
    ]

    static func priority(
        intent: String = PriorityFixture.intent,
        timebox: TimeboxState = .running(remaining: .seconds(19 * 60))
    ) -> PrioritySnapshot {
        PrioritySnapshot(
            id: id,
            intent: intent,
            doneWhen: "The signed PDF is in the shared folder and legal has replied",
            createdAt: now,
            lastActivatedAt: now,
            timeboxSeconds: 25 * 60,
            startedAt: now,
            timebox: timebox,
            contextItems: contextItems,
            rules: rules,
            assessment: .wellFormed
        )
    }

    static let recent: [RecentPriority] = [
        RecentPriority(
            id: id,
            intent: intent,
            doneWhen: "The signed PDF is in the shared folder",
            contextItemCount: 6,
            lastActivatedAt: now,
            isActive: true
        ),
        RecentPriority(
            id: UUID(uuidString: "E0200000-0000-4000-A000-000000000031")!,
            intent: "Rewrite the onboarding checklist",
            doneWhen: nil,
            contextItemCount: 2,
            lastActivatedAt: now.addingTimeInterval(-86_400)
        ),
        RecentPriority(
            id: UUID(uuidString: "E0200000-0000-4000-A000-000000000032")!,
            intent: "Reply to the accessibility audit",
            doneWhen: "Every finding has an owner",
            contextItemCount: 0,
            lastActivatedAt: now.addingTimeInterval(-172_800),
            completedAt: now.addingTimeInterval(-170_000)
        )
    ]

    /// An incoming handoff carrying every flag the confirm surface has to disclose, so the
    /// baseline shows the *worst* case rather than the tidy one.
    static let handoff = HandoffRequest(
        verb: .start,
        task: "Draft the migration note for the storage change",
        doneWhen: "The note is in the shared folder",
        flags: [
            .taskTruncated(originalLength: 5_019),
            .controlCharactersStripped,
            .duplicateKeysIgnored(["task"]),
            .unknownQueryItems(["project", "assignee"])
        ]
    )

    /// The committed cockpit, drawn as the app really looks once it is running.
    ///
    /// From e03 the fixture is **watching**, with the capability matrix the rig actually
    /// measured at zero grants (`CapabilityFixture.asMeasured`) and a session in `.focus`. That
    /// matters for the baseline's value as evidence: an unobserved matrix would draw eight
    /// standing lines of "never asked for" under a window whose whole point is one sentence, and
    /// a picture of that would be a picture of a state the app is only ever in for the instant
    /// before its first probe.
    static func cockpit(intent: String = PriorityFixture.intent) -> CockpitState {
        CockpitState(
            status: .uncertain,
            storeOpened: true,
            isObservingActivity: true,
            priority: priority(intent: intent),
            recent: recent,
            session: SessionFixture.session(phase: .focus),
            sensing: SensingSummary(
                isObserving: true,
                isPausedByUser: false,
                liveObserverCount: 12,
                redundantActivations: 3,
                lifecycle: .active,
                isUserIdle: false,
                media: .idle,
                cameraReason: .noDevices,
                presentation: .notPresenting,
                isOnSecondaryDisplay: false
            ),
            capabilities: CapabilityFixture.asMeasured
        )
    }
}

/// Every e02 surface the snapshot matrix covers.
///
/// **What is deliberately absent, and why.** Measured on this machine and recorded in e01's
/// `SnapshotTests`: an AppKit-backed control does not rasterise under `ImageRenderer` — a
/// `TextField` or a `Picker` draws SwiftUI's yellow "unrenderable view" placeholder whatever
/// appearance is injected. So the capture field, the quick-capture panel and the completion
/// sheet are not here: committing those renders would mean committing a picture of a broken
/// control and calling it a baseline. They are covered by structural tests instead, and by the
/// TCC-gated live frames where AppKit draws them for real.
///
/// The context pack and the rules pane *are* here, in their read-only form. Both hide their
/// composing controls when no mutation host is attached, so what renders is exactly the chips
/// and rows — which is the part these baselines exist to watch.
enum PriorityComponent: String, CaseIterable, Sendable {
    case priorityHero
    case priorityHeroEmpty
    case cockpitWithPriority
    case contextPack
    case taskRules
    case timeboxRunning
    case timeboxOvertime
    case recentPriorities
    case ritualBanner
    case handoffConfirm

    /// Everything wraps inside a fixed width, so growing text grows the *height* — which is
    /// what the dynamic-type and pseudo-localisation assertions read.
    var width: CGFloat? {
        // The handoff sheet commits a width now, so it is photographed at the width it commits
        // to, plus the harness's own 16-point padding on each side (focus-nu6).
        self == .handoffConfirm ? ShellSurfaceBounds.handoffSheetWidth + 32 : 520
    }

    /// Whether a pseudo-localised pass means anything for this component.
    ///
    /// `priorityHero` draws one thing: the user's own sentence, through `Text(verbatim:)`,
    /// because it is data and not prose. Pseudo-localising it would correctly change nothing,
    /// so asserting "more ink" over it would be asserting that the hero *is* translated — the
    /// opposite of what F-149 wants.
    var drawsLocalisedProse: Bool { self != .priorityHero }

    /// Whether Increase Contrast has anything to change in this component.
    ///
    /// `DesignTokens.emphasis(for:)` is the whole of the shell's Increase Contrast response:
    /// it thickens borders, drives outline opacity to 1, and **promotes secondary text** to
    /// the primary label colour. A component with a border or a supporting line therefore has
    /// to render differently, and every one of them does — asserted below.
    ///
    /// A committed priority is the one surface with neither. It is a single run of
    /// `Palette.primaryText` at the hero role: no outline to thicken and no secondary colour
    /// to promote, because it is already drawn in the strongest colour the palette has.
    /// Measured: `priorityHero.light` and `priorityHero.increasedContrast` are pixel-identical.
    ///
    /// The alternative would be to invent a difference — a heavier weight, a rule underneath —
    /// so that an assertion could find one. That would be a style change wearing an
    /// accessibility argument, and it would make the *empty* hero's real promotion (the prompt
    /// is supporting-coloured, so it does move, and `priorityHeroEmpty` asserts it) harder to
    /// see rather than easier. So the exemption is named here, for one case, with its reason.
    var respondsToIncreasedContrast: Bool { self != .priorityHero }

    @MainActor
    var view: AnyView {
        switch self {
        case .priorityHero:
            AnyView(PriorityHeroView(intent: PriorityFixture.intent))
        case .priorityHeroEmpty:
            AnyView(PriorityHeroView(intent: nil))
        case .cockpitWithPriority:
            // The elapsed figure is passed in, as it is in the app: there is no clock in this
            // view and no timer anywhere in the programme, so the baseline is a picture at a
            // fixed instant rather than a race with the machine that renders it.
            AnyView(
                CockpitView(
                    state: PriorityFixture.cockpit(),
                    sessionElapsedSeconds: SessionFixture.elapsedSeconds
                )
            )
        case .contextPack:
            AnyView(
                FocusHost { focus in
                    ContextChipRow(items: PriorityFixture.contextItems, focus: focus)
                }
            )
        case .taskRules:
            AnyView(
                FocusHost { focus in
                    TaskRulesView(rules: PriorityFixture.rules, focus: focus)
                }
            )
        case .timeboxRunning:
            AnyView(
                FocusHost { focus in
                    TimeboxControl(
                        timeboxSeconds: 25 * 60,
                        state: .running(remaining: .seconds(19 * 60)),
                        focus: focus
                    )
                }
            )
        case .timeboxOvertime:
            AnyView(
                FocusHost { focus in
                    TimeboxControl(
                        timeboxSeconds: 25 * 60,
                        state: .overtime(over: .seconds(7 * 60)),
                        focus: focus
                    )
                }
            )
        case .recentPriorities:
            AnyView(RecentPrioritiesView(rows: PriorityFixture.recent))
        case .ritualBanner:
            AnyView(
                FocusHost { focus in
                    RitualBanner(answer: {}, dismiss: {}, focus: focus)
                }
            )
        case .handoffConfirm:
            AnyView(
                // `screens: []` — no display, so the sheet's container draws its column whole
                // (focus-nu6). `ImageRenderer` cannot draw the scroll view it reaches for past a
                // ceiling, and the ceiling is read from the live display, so a picture of the
                // bounded sheet would have dimensions that followed the monitor.
                HandoffConfirmationSheet(
                    request: PriorityFixture.handoff,
                    current: PriorityFixture.priority(),
                    replace: {},
                    cancel: {},
                    screens: []
                )
            )
        }
    }
}

/// The F-157 snapshot lane, extended to e02's surfaces.
///
/// Same machinery as e01's: `ImageRenderer` inside the ordinary unit lane, with every
/// appearance variant and every text size **injected** rather than read from the system, so a
/// Mac with every accessibility setting switched off still renders all five variants
/// deterministically.
///
/// Lane-gated on compiled String Catalogs, and that is not a convenience: under `swift test`
/// SwiftPM copies the catalogs verbatim, so every label would render as its own key and the
/// baselines would be pictures of `priority.timebox.label`.
@Suite("Priority snapshots", .enabled(if: LocalizationLane.catalogsAreCompiled))
@MainActor
struct PrioritySnapshotTests {
    @Test(
        "every priority surface matches its baseline in every appearance variant",
        arguments: PriorityComponent.allCases, AppearanceTraits.namedVariants.map(\.name)
    )
    func componentMatchesBaseline(component: PriorityComponent, variant: String) throws {
        for size in SnapshotTypeSize.allCases {
            try SnapshotHarness.assertSnapshot(
                component.view,
                component: component.rawValue,
                variant: variant,
                textScale: size.textScale,
                width: component.width
            )
        }
    }

    @Test("light and dark are different pictures", arguments: PriorityComponent.allCases)
    func lightAndDarkDiffer(component: PriorityComponent) throws {
        let light = try render(component, variant: "light")
        let dark = try render(component, variant: "dark")
        let differs = PNGCompare.areDistinct(light.pixels, dark.pixels)
        #expect(differs, "\(component.rawValue) ignores dark mode")
    }

    @Test(
        "increased contrast changes the picture",
        arguments: PriorityComponent.allCases.filter(\.respondsToIncreasedContrast)
    )
    func increasedContrastDiffers(component: PriorityComponent) throws {
        let plain = try render(component, variant: "light")
        let contrasted = try render(component, variant: "increasedContrast")
        let differs = PNGCompare.areDistinct(plain.pixels, contrasted.pixels)
        #expect(differs, "\(component.rawValue) ignores Increase Contrast")
    }

    /// The one exemption above, pinned so it cannot quietly widen.
    ///
    /// If a later change gives the committed hero a border, a supporting line or any other
    /// contrast-sensitive ornament, this test fails and the exemption has to be deleted —
    /// which is the point. An exemption nobody re-reads is an exemption that spreads.
    @Test("the committed priority hero is the only Increase Contrast exemption")
    func theHeroIsTheOnlyIncreasedContrastExemption() throws {
        let exempt = PriorityComponent.allCases.filter { !$0.respondsToIncreasedContrast }
        #expect(exempt == [.priorityHero])

        let plain = try render(.priorityHero, variant: "light")
        let contrasted = try render(.priorityHero, variant: "increasedContrast")
        #expect(
            !PNGCompare.areDistinct(plain.pixels, contrasted.pixels),
            "the priority hero now responds to Increase Contrast — remove its exemption"
        )
    }

    /// Every context-item kind has to be told apart without colour.
    ///
    /// The chips encode their kind in an SF Symbol silhouette and their availability in a
    /// second one, never in a tint — which is the same shape+label rule e01 applied to the
    /// status badge (F-146). This is the assertion that keeps it true.
    @Test("every context-chip kind renders distinctly without colour")
    func contextChipKindsAreDistinctWithoutColour() throws {
        let traits = AppearanceTraits(colorScheme: .light, differentiateWithoutColor: true)
        var renders: [(name: String, snapshot: Snapshot)] = []

        for item in PriorityFixture.contextItems {
            let name = "contextChip.differentiateWithoutColor.\(item.kind.rawValue).\(item.availability)"
            renders.append(
                (
                    item.displayName,
                    try SnapshotHarness.render(
                        ContextChip(item: item),
                        traits: traits,
                        width: nil,
                        name: name
                    )
                )
            )
        }

        for (index, subject) in renders.enumerated() {
            for other in renders[(index + 1)...] {
                let differs = PNGCompare.areDistinct(subject.snapshot.pixels, other.snapshot.pixels)
                #expect(
                    differs,
                    "\(subject.name) and \(other.name) render identically without colour"
                )
            }
        }
    }

    /// A timebox that has run over must not look like one that has not.
    @Test("running and overtime are different pictures")
    func timeboxStatesAreDistinct() throws {
        let running = try render(.timeboxRunning, variant: "light")
        let overtime = try render(.timeboxOvertime, variant: "light")
        #expect(PNGCompare.areDistinct(running.pixels, overtime.pixels))
    }

    // MARK: -

    private func render(_ component: PriorityComponent, variant: String) throws -> Snapshot {
        try SnapshotHarness.render(
            component.view,
            traits: SnapshotHarness.variantTraits(named: variant),
            width: component.width,
            name: "\(component.rawValue).distinctness.\(variant)"
        )
    }
}
