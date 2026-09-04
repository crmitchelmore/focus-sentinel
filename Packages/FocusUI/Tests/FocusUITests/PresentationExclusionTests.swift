import AppKit
import FocusCore
import Testing

@testable import FocusUI

/// **The exclusion list a person can actually reach** (F-121, focus-62o, focus-u3w).
///
/// The section this covers was **deleted** at a081d64, and the reason is the whole point of this
/// suite: it drew a heading and *"Nothing yet. Add an app here when Focus mistakes its
/// full-screen window for a presentation."* with no add affordance in it and none anywhere else
/// in the application. `SensitiveAppSeed.add` had no shipping call site at all, the list seeds
/// empty, so it was empty for everybody for ever — which made the Remove button beside a row a
/// button no row existed to carry.
///
/// So what is asserted here is reachability in both directions: that the vocabulary has both
/// verbs, that the reading of what is running can produce something to add, and that the section
/// draws a row for what is on the list and an offer for what is not.
@Suite("Presentation exclusions")
@MainActor
struct PresentationExclusionTests {
    /// A stand-in for a running application. `NSRunningApplication` cannot be constructed, so the
    /// reader is folded over a protocol-free list of the two facts it uses.
    struct FakeApplication {
        let bundleID: String?
        let name: String?
        let policy: NSApplication.ActivationPolicy
    }

    /// The same filter `RunningApplications.choices(from:excluding:)` applies, over values a test
    /// can build. Kept beside the real one rather than inside it, so the production path takes
    /// `NSRunningApplication` and nothing in the shipping graph knows this type exists.
    static func choices(
        from applications: [FakeApplication],
        excluding ownBundleID: String
    ) -> [PresentationExclusion] {
        var seen = Set<String>()
        return applications
            .filter { $0.policy == .regular }
            .compactMap { application -> PresentationExclusion? in
                guard
                    let bundleID = application.bundleID,
                    bundleID != ownBundleID,
                    seen.insert(bundleID).inserted
                else { return nil }
                return PresentationExclusion(
                    bundleID: bundleID,
                    displayName: application.name ?? bundleID
                )
            }
            .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }

    /// **What the reader offers, and the four things it refuses to.**
    ///
    /// An agent with no Dock icon is not something anybody presents from; this app is not
    /// something a person excludes from itself; an application with no identifier cannot be
    /// stored; and one identifier is one row however many processes carry it.
    @Test("the running-application reading offers ordinary apps, once each, by name")
    func theReadingOffersOrdinaryApps() {
        let choices = Self.choices(
            from: [
                FakeApplication(bundleID: "com.example.Keynote", name: "Keynote", policy: .regular),
                FakeApplication(bundleID: "com.example.Agent", name: "Agent", policy: .accessory),
                FakeApplication(bundleID: "com.example.Hidden", name: "Hidden", policy: .prohibited),
                FakeApplication(bundleID: nil, name: "Nameless", policy: .regular),
                FakeApplication(bundleID: "com.example.Keynote", name: "Keynote", policy: .regular),
                FakeApplication(bundleID: "com.example.Self", name: "Focus", policy: .regular),
                FakeApplication(bundleID: "com.example.Aardvark", name: nil, policy: .regular)
            ],
            excluding: "com.example.Self"
        )

        #expect(choices.map(\.bundleID) == ["com.example.Aardvark", "com.example.Keynote"])
        // An application with no localised name is drawn under its identifier rather than
        // dropped: a row nobody can name is still a row somebody may want to exclude.
        #expect(choices.first?.displayName == "com.example.Aardvark")
        #expect(choices.last?.displayName == "Keynote")
    }

    /// The live reading runs and answers. It needs no grant — `NSWorkspace.runningApplications`
    /// reads no window and names no document — so this is a real call rather than a fake.
    @Test("the live reading answers without asking for anything")
    func theLiveReadingAnswers() {
        let live = RunningApplications.choices()
        #expect(live.allSatisfy { !$0.bundleID.isEmpty && !$0.displayName.isEmpty })
        #expect(Set(live.map(\.bundleID)).count == live.count, "one identifier, one row")
        // Sorted by the name a person reads, so the list is scannable.
        #expect(
            live == live.sorted {
                $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
            }
        )
    }

    /// **Both verbs exist.** The Remove half shipped and was unreachable because nothing could
    /// ever add a row; a vocabulary with one of the two is the defect this bead is about.
    @Test("the pane can both add and remove")
    func bothVerbsExist() {
        let add = InterventionSettingsAction.addPresentationExclusion("com.example.Keynote")
        let remove = InterventionSettingsAction.removePresentationExclusion("com.example.Keynote")
        #expect(add != remove)
        // The identifier travels, not the name: a localised name is a different string on a
        // different Mac, and the list is keyed on the identifier.
        if case .addPresentationExclusion(let subject) = add {
            #expect(subject == "com.example.Keynote")
        } else {
            Issue.record("the add case lost its subject")
        }
    }

    /// The section declares every string it draws, so the catalog suite and the reachability lint
    /// both see them.
    @Test("the section declares its six strings")
    func theSectionDeclaresItsStrings() {
        let keys = Set(PresentationExclusionSection.contentKeys)
        #expect(keys.count == 6)
        #expect(keys.contains(.interventionExclusionHeading))
        #expect(keys.contains(.interventionExclusionExplanation))
        #expect(keys.contains(.interventionExclusionEmpty))
        #expect(keys.contains(.interventionExclusionAddHeading))
        #expect(keys.contains(.interventionExclusionNoneRunning))
        #expect(keys.contains(.interventionExclusionRemove))
    }

    /// **The receipt says what the section drew**, and says the two halves apart: a pane that
    /// listed nothing and a pane that offered nothing are different failures.
    @Test("the receipt carries the list and the size of the offer")
    func theReceiptCarriesBothHalves() {
        let excluded = [PresentationExclusion(bundleID: "com.example.Keynote", displayName: "Keynote")]
        let addable = (1...30).map {
            PresentationExclusion(bundleID: "com.example.A\($0)", displayName: "App \($0)")
        }

        let empty = PresentationExclusionSection.rendered(excluded: [], addable: [])
        #expect(empty == "excluded: none; addable: 0")

        let full = PresentationExclusionSection.rendered(excluded: excluded, addable: addable)
        #expect(full.contains("Keynote (com.example.Keynote)"))
        // Capped, because a settings pane that grows without bound is the defect BoundedSurface
        // exists for — and the receipt reports what was drawn, not what was available.
        #expect(full.hasSuffix("addable: \(PresentationExclusionSection.addableLimit)"))
        #expect(PresentationExclusionSection.addableLimit == 12)
    }

    /// The pane's own settings value carries both halves, so a section handed neither draws
    /// neither and the receipt says so.
    @Test("the settings value carries the list and the offer")
    func theSettingsValueCarriesBoth() {
        let settings = InterventionSettings(
            presentationExclusions: [
                PresentationExclusion(bundleID: "com.example.Keynote", displayName: "Keynote")
            ],
            addableApplications: [
                PresentationExclusion(bundleID: "com.example.Deck", displayName: "Deck")
            ]
        )
        #expect(settings.presentationExclusions.map(\.bundleID) == ["com.example.Keynote"])
        #expect(settings.addableApplications.map(\.displayName) == ["Deck"])
        // The default is empty on both sides, which is what a fresh store really holds: the
        // presentation-exclusion list is never seeded.
        #expect(InterventionSettings().presentationExclusions.isEmpty)
        #expect(InterventionSettings().addableApplications.isEmpty)
    }
}
