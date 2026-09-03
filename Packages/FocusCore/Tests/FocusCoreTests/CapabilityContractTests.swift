import Foundation
import Testing

@testable import FocusCore

/// 2026-01-01T00:00:00Z — the same reference instant every other suite here uses. No test
/// below reads a real clock.
private let now = Date(timeIntervalSince1970: 1_767_225_600)
private let later = now.addingTimeInterval(3_600)

@Suite("The capability fallback table is total")
struct CapabilityContractTotalityTests {
    /// The Court called this the most charter-critical row in the registry. A table with a
    /// hole in it is a promise with a hole in it, so the hole is what is asserted against.
    ///
    /// The `switch`es in `CapabilityContract` carry no `default:` arm anywhere, which means a
    /// thirteenth capability or an eleventh consumer stops the **build**. This test is the
    /// belt to that brace: it enumerates all one hundred and twenty pairs and asserts every
    /// one produces a declared answer.
    @Test("every one of the 120 capability × consumer pairs has a declared fallback")
    func tableIsTotal() {
        #expect(Capability.allCases.count == 12)
        #expect(SensingConsumer.allCases.count == 10)

        var seen: Set<String> = []
        for capability in Capability.allCases {
            for consumer in SensingConsumer.allCases {
                let fallback = CapabilityContract.fallback(for: capability, consumer: consumer)
                #expect(
                    !fallback.token.isEmpty,
                    "\(capability) × \(consumer) has no declared fallback"
                )
                seen.insert("\(capability.rawValue)|\(consumer.rawValue)")
            }
        }
        #expect(seen.count == 120)
        #expect(CapabilityContract.allCells.count == 120)
    }

    /// A `degraded` fallback must name a capability that is not the one it is falling back
    /// from — otherwise it is a cycle wearing a fallback's clothes.
    @Test("no fallback degrades a capability to itself")
    func noSelfDegradation() {
        for cell in CapabilityContract.allCells {
            if case .degraded(let destination) = cell.fallback {
                #expect(
                    destination != cell.capability,
                    "\(cell.consumer) degrades \(cell.capability) to itself"
                )
            }
        }
    }

    /// **The charter's tenet, as an assertion.** A tier-1 promise that evaporates when a
    /// permission is refused was never a tier-1 promise. It degrades, it suppresses, or it
    /// says plainly that this part is unavailable — but it does not silently vanish.
    @Test("no T1 consumer's fallback is featureAbsent, for any capability")
    func noTierOneConsumerLosesItsFeature() {
        for cell in CapabilityContract.allCells where cell.consumer.tier == .t1 {
            #expect(
                cell.fallback != .featureAbsent,
                "\(cell.consumer) (T1) declares featureAbsent for \(cell.capability)"
            )
        }
        // And the rule has teeth only if some consumer is T1.
        #expect(SensingConsumer.allCases.contains { $0.tier == .t1 })
    }

    /// The same claim, aimed exactly where the criterion aims it: a **denied** capability.
    @Test("a denied capability never leaves a T1 consumer with featureAbsent")
    func deniedCapabilityNeverAbsentsATierOneConsumer() {
        let allDenied = StaticCapabilityProbe(everything: .denied).probe(at: now)
        for capability in Capability.allCases {
            for consumer in SensingConsumer.allCases where consumer.tier == .t1 {
                let fallback = allDenied.fallback(for: capability, consumer: consumer)
                #expect(fallback != nil, "a denied capability must produce a fallback")
                #expect(
                    fallback != .featureAbsent,
                    "\(consumer) (T1) would vanish when \(capability) is denied"
                )
            }
        }
    }

    /// `.featureAbsent` is not banned outright — it is the honest answer for a T3 nicety, and
    /// a table in which nothing is ever absent would be a table that had stopped meaning
    /// anything.
    @Test("featureAbsent is reachable, and only for consumers below T1")
    func featureAbsentIsReachableBelowTierOne() {
        let absent = CapabilityContract.allCells.filter { $0.fallback == .featureAbsent }
        #expect(!absent.isEmpty)
        for cell in absent {
            #expect(cell.consumer.tier != .t1)
        }
    }

    /// Every suppression consumer errs quiet, never loud. The asymmetry is the whole design: a
    /// nudge that should not have fired costs trust, and one that did not fire costs a nudge.
    @Test("losing a suppression input makes the ladder quieter, never louder")
    func suppressionInputsFailQuiet() {
        for capability in [Capability.presentation, .microphoneActivity, .idle, .systemLifecycle] {
            #expect(
                CapabilityContract.fallback(for: capability, consumer: .nudgeLadder) == .suppressOnly,
                "\(capability) missing must not let the ladder fire more freely"
            )
        }
        #expect(
            CapabilityContract.fallback(for: .presentation, consumer: .presentationSuppression)
                == .suppressOnly
        )
        #expect(
            CapabilityContract.fallback(for: .microphoneActivity, consumer: .mediaSuppression)
                == .suppressOnly
        )
    }

    /// The camera half is held off on **every** rig, so the media rule was built to work
    /// without it. Its absence is a documented degradation onto the microphone, not a loss —
    /// "nothing degrades that the microphone half provides".
    @Test("the held-off camera degrades media suppression onto the microphone, and nothing more")
    func cameraDegradesOntoTheMicrophone() {
        #expect(
            CapabilityContract.fallback(for: .cameraActivity, consumer: .mediaSuppression)
                == .degraded(to: .microphoneActivity)
        )
        #expect(
            CapabilityContract.fallback(for: .cameraActivity, consumer: .nudgeLadder)
                == .degraded(to: .microphoneActivity)
        )
    }

    /// **The Privacy pane may not tell a person they are running a reduced product because of a
    /// permission this app never wanted** (focus-i1g, U-2).
    ///
    /// The defect this pins was user-reachable on **every fresh install**: `.notifications` sits
    /// at `.notRequested` there, so `CapabilityMatrixView` drew its fallback lines, and the
    /// `.nudgeLadder` cell said `.degraded(to: .frontmostApplication)` — rendered as *"Falls back
    /// to 'Which app is in front' and keeps working"*. One settings tab away the app says every
    /// step of a nudge appears inside Focus and it never asks permission to send one. Both cannot
    /// be true.
    ///
    /// The suite could not see it because the only assertion aimed at this row —
    /// `suppressionInputsFailQuiet` — checks the *suppress-only* direction over four other
    /// capabilities. Nothing pinned this cell, so the number of tests that would have failed if
    /// the ladder had quietly grown a dependence on notifications was zero.
    ///
    /// So the claim is asserted in the direction that makes it true rather than as a literal:
    /// **no consumer degrades on notifications, because no rung can route to one.** The second
    /// half is enumerated over the router's whole input space rather than asserted about the one
    /// call the author had in mind — if a future rung ever *does* route to a notification, this
    /// fails here and the contract must be re-argued before the pane can go on saying nothing
    /// depends on it.
    @Test("nothing degrades without notifications, because no rung can route to one")
    func notificationsCostThisLadderNothing() {
        for consumer in SensingConsumer.allCases {
            #expect(
                CapabilityContract.fallback(for: .notifications, consumer: consumer)
                    == .fullFunction,
                """
                \(consumer) declares a degraded behaviour for a missing notification grant. \
                The Privacy pane renders that sentence to every fresh install, where the \
                capability is .notRequested — so it must be true of the shipping router, or \
                deleted.
                """
            )
        }

        // …and here is why it is true, over the router's whole input space rather than at the one
        // call this file's author had in mind. `SurfaceRouterTests.everyCell` is the same 160-cell
        // fold `noCellReachesANotification` uses, borrowed rather than copied so the two claims
        // cannot come to disagree about what "every cell" means.
        var cells = 0
        SurfaceRouterTests.everyCell { rung, _, _, _, _, voice, route in
            cells += 1
            #expect(
                route.surface != .notification,
                "\(rung)/\(voice) routes to a notification, so the contract cell above is a lie"
            )
        }
        #expect(
            cells == SurfaceRouterTests.cellCount,
            "the router's input space changed under this claim"
        )
    }

    /// Lock detection's primary signal *is* an ordinary activation — `com.apple.loginwindow`
    /// becoming frontmost, 1.5 ms before the undocumented notification (probe P-87). So this
    /// degradation is very nearly the same mechanism, not a consolation prize.
    @Test("lifecycle degrades onto the frontmost application, which is where it came from")
    func lifecycleDegradesOntoFrontmost() {
        #expect(
            CapabilityContract.fallback(for: .systemLifecycle, consumer: .lifecyclePause)
                == .degraded(to: .frontmostApplication)
        )
    }

    /// The cheapest-signal-first cascade, read out of the table rather than out of the policy.
    @Test("classification degrades down the cascade, tier by tier")
    func classificationDegradesDownTheCascade() {
        #expect(
            CapabilityContract.fallback(for: .accessibilityWindowContext, consumer: .classification)
                == .degraded(to: .windowMetadata)
        )
        #expect(
            CapabilityContract.fallback(for: .windowMetadata, consumer: .classification)
                == .degraded(to: .frontmostApplication)
        )
        // The charter requires a heuristic fallback to be always present, so the model's
        // absence is a degradation and never a feature going away.
        #expect(
            CapabilityContract.fallback(for: .onDeviceModel, consumer: .classification)
                == .degraded(to: .frontmostApplication)
        )
    }
}

@Suite("Capability states and the matrix")
struct CapabilityMatrixTests {
    @Test("all five states exist and each is reachable with an injected adapter")
    func allFiveStatesAreReachable() {
        #expect(CapabilityState.allCases.count == 5)
        for state in CapabilityState.allCases {
            let matrix = StaticCapabilityProbe(everything: state).probe(at: now)
            for capability in Capability.allCases {
                #expect(matrix.state(of: capability) == state)
            }
        }
    }

    @Test("only .available is usable, and only .denied is something the user could change")
    func stateSemantics() {
        #expect(CapabilityState.available.isUsable)
        for state in CapabilityState.allCases where state != .available {
            #expect(!state.isUsable)
        }
        #expect(CapabilityState.denied.isUserReversible)
        // Not a refusal: nobody denied the Mac a camera it does not have, and offering to fix
        // it would be an insult.
        #expect(!CapabilityState.unavailable.isUserReversible)
        #expect(!CapabilityState.restricted.isUserReversible)
        #expect(!CapabilityState.notRequested.isUserReversible)
    }

    @Test("an unobserved capability reads as notRequested rather than as an absence")
    func unobservedReadsAsNotRequested() {
        let empty = CapabilityMatrix()
        #expect(empty.state(of: .microphoneActivity) == .notRequested)
        #expect(empty.observation(of: .microphoneActivity) == nil)
        #expect(empty.allStates.count == 12, "twelve rows, always")

        let unobserved = CapabilityMatrix.unobserved(at: now)
        for capability in Capability.allCases {
            #expect(unobserved.state(of: capability) == .notRequested)
        }
    }

    /// The user's answer is not a prompt to try again. `.notRequested` is the state that means
    /// "we have not asked yet", and letting a denial decay into it is exactly how an app comes
    /// to ask a second time.
    @Test("a denied capability never transitions back to notRequested")
    func denialDoesNotDecayIntoAQuestion() {
        var matrix = CapabilityMatrix()
        matrix = matrix.recording(.notifications, as: .denied, at: now)
        #expect(matrix.state(of: .notifications) == .denied)

        matrix = matrix.recording(.notifications, as: .notRequested, at: later)
        #expect(matrix.state(of: .notifications) == .denied, "the denial decayed into a question")
        #expect(matrix.observation(of: .notifications)?.observedAt == now, "and it was not restamped")
    }

    /// Live state is authoritative, so a user who changes their mind in System Settings is
    /// believed immediately. That is the *other* half of never re-asking.
    @Test("a denied capability may become available again without being asked")
    func denialLiftsWhenTheUserChangesTheirMind() {
        var matrix = CapabilityMatrix()
        matrix = matrix.recording(.notifications, as: .denied, at: now)
        matrix = matrix.recording(.notifications, as: .available, at: later)
        #expect(matrix.state(of: .notifications) == .available)
    }

    @Test("educationShownAt is written exactly once and survives a later observation")
    func educationIsWrittenOnce() {
        var matrix = CapabilityMatrix()
        matrix = matrix.recording(.notifications, as: .denied, at: now)
        #expect(matrix.observation(of: .notifications)?.educationShownAt == nil)

        matrix = matrix.recordingEducationShown(for: .notifications, at: now)
        #expect(matrix.observation(of: .notifications)?.educationShownAt == now)

        // A second explanation does not re-arm the first.
        matrix = matrix.recordingEducationShown(for: .notifications, at: later)
        #expect(matrix.observation(of: .notifications)?.educationShownAt == now)

        // Nor does re-observing the capability.
        matrix = matrix.recording(.notifications, as: .denied, at: later)
        #expect(matrix.observation(of: .notifications)?.educationShownAt == now)

        // And a capability nobody has observed has nothing to explain.
        let empty = CapabilityMatrix().recordingEducationShown(for: .idle, at: now)
        #expect(empty.observation(of: .idle) == nil)
    }

    @Test("an available capability produces no fallback, because nothing is falling back")
    func availableCapabilitiesHaveNoFallback() {
        let matrix = StaticCapabilityProbe(everything: .available).probe(at: now)
        for capability in Capability.allCases {
            for consumer in SensingConsumer.allCases {
                #expect(matrix.fallback(for: capability, consumer: consumer) == nil)
            }
        }
    }

    /// The four non-available states all produce the same declared fallback, because the
    /// fallback is about what the consumer *does*, not about why the capability is missing.
    /// Why it is missing is what the surface says; what to do about it is this.
    @Test("every non-available state produces the declared fallback")
    func everyNonAvailableStateFallsBack() {
        for state in CapabilityState.allCases where state != .available {
            let matrix = StaticCapabilityProbe(everything: state).probe(at: now)
            for capability in Capability.allCases {
                for consumer in SensingConsumer.allCases {
                    #expect(
                        matrix.fallback(for: capability, consumer: consumer)
                            == CapabilityContract.fallback(for: capability, consumer: consumer)
                    )
                }
            }
        }
    }
}

@Suite("The zero-grant expectation this epic ships")
struct CapabilityZeroGrantExpectationTests {
    /// Seven available, two unavailable, three not requested — each with a measured or a
    /// declared reason, and none of them a denial, because in e03 nothing is ever asked.
    @Test("seven capabilities are available at zero grants and none is denied")
    func zeroGrantShape() {
        let matrix = CapabilityMatrix.zeroGrantExpectation(at: now)

        let available = Capability.allCases.filter { matrix.state(of: $0) == .available }
        #expect(
            Set(available) == [
                .frontmostApplication, .windowMetadata, .idle, .systemLifecycle,
                .displayGeometry, .presentation, .microphoneActivity
            ]
        )
        #expect(available.count == 7)

        // Not a denial. There is no camera on the rig, and the deeper camera path has never
        // been observed for prompts on any rig, so it is held off on all of them.
        #expect(matrix.state(of: .cameraActivity) == .unavailable)
        // Parked by the Court, not refused by anyone.
        #expect(matrix.state(of: .screenCapture) == .unavailable)

        for capability in [
            Capability.accessibilityWindowContext, .notifications, .onDeviceModel
        ] {
            #expect(matrix.state(of: capability) == .notRequested)
        }

        // Nothing is denied, because nothing was asked. That is the whole epic in one line.
        #expect(!Capability.allCases.contains { matrix.state(of: $0) == .denied })
    }

    /// A facility this epic depends on may not be sitting at `.notRequested` while the app
    /// runs: that would mean nobody had ever looked.
    @Test("no capability e03 uses is left notRequested")
    func nothingThisEpicUsesIsUnprobed() {
        let matrix = CapabilityMatrix.zeroGrantExpectation(at: now)
        for capability in CapabilityMatrix.capabilitiesUsedInThisEpic {
            #expect(matrix.state(of: capability) != .notRequested)
            #expect(matrix.state(of: capability) == .available)
        }
        #expect(CapabilityMatrix.capabilitiesUsedInThisEpic.count == 7)
        #expect(!CapabilityMatrix.capabilitiesUsedInThisEpic.contains(.cameraActivity))
    }

    /// With the camera held off, the media rule still works — on the microphone alone — and
    /// the two suppression consumers say so.
    @Test("on this rig the held-off camera leaves media suppression running on the microphone")
    func cameraHoldLeavesTheMicrophoneRuleIntact() {
        let matrix = CapabilityMatrix.zeroGrantExpectation(at: now)
        #expect(
            matrix.fallback(for: .cameraActivity, consumer: .mediaSuppression)
                == .degraded(to: .microphoneActivity)
        )
        #expect(matrix.isAvailable(.microphoneActivity))
        #expect(matrix.fallback(for: .microphoneActivity, consumer: .mediaSuppression) == nil)
    }
}
