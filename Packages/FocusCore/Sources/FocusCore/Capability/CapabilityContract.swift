import Foundation

/// The degradation matrix: what **every** consumer does when **every** capability is missing.
///
/// The Feasibility Court called this the most charter-critical row in the registry, so it
/// ships as an artefact a test can prove rather than as a sentence in a document. One hundred
/// and thirty cells, all of them written out.
///
/// ## Why this is a nested exhaustive `switch` and not a dictionary
///
/// A dictionary can be missing a key, and a missing key becomes a runtime `nil` that some
/// call site turns into a default nobody chose. A `switch` over two `CaseIterable` enums with
/// **no `default:` arm anywhere** cannot be missing a cell: adding a thirteenth capability or
/// an eleventh consumer stops the build until somebody decides what it does. That is what
/// "every capability declares its no-permission behaviour" means as a compile-time fact, and
/// the totality test beside it is the belt to this brace.
///
/// ## The one rule that binds the table's contents
///
/// **No T1 consumer's fallback may be `.featureAbsent`.** A promise the product is built on
/// cannot evaporate because a permission was refused or a device is missing; it degrades, or
/// it suppresses, or it tells the user plainly that this part is unavailable — with **no call
/// to action**, because a call to action would be an ask in disguise. `.featureAbsent` is
/// therefore available only to T2 and T3 consumers, and a test enforces that rather than a
/// comment.
public enum CapabilityContract {
    /// What `consumer` does when `capability` is not `.available`.
    ///
    /// - Returns: the declared fallback. Total by construction.
    public static func fallback(
        for capability: Capability,
        consumer: SensingConsumer
    ) -> CapabilityFallback {
        switch consumer {

        // The timeline is a record of bundle identifiers and instants. Everything else on the
        // row is enrichment, and a row without its enrichment is still a true row.
        case .activationTimeline:
            switch capability {
            case .frontmostApplication: return .showUnavailable
            case .displayGeometry: return .degraded(to: .frontmostApplication)
            case .windowMetadata, .idle, .systemLifecycle, .presentation,
                 .microphoneActivity, .cameraActivity, .accessibilityWindowContext,
                 .screenCapture, .notifications, .onDeviceModel, .calendarEvents:
                return .fullFunction
            }

        // Dwell needs activations. Without idle or lifecycle it still measures dwell — it just
        // counts an empty chair as time at the desk, which is a worse figure and not no figure.
        case .dwellAttribution:
            switch capability {
            case .frontmostApplication: return .showUnavailable
            case .idle, .systemLifecycle: return .degraded(to: .frontmostApplication)
            case .windowMetadata, .displayGeometry, .presentation, .microphoneActivity,
                 .cameraActivity, .accessibilityWindowContext, .screenCapture,
                 .notifications, .onDeviceModel, .calendarEvents:
                return .fullFunction
            }

        // Secondary-display fairness is a T2 nicety with three hard inputs and no substitute
        // for any of them: without a frontmost PID there is nothing to filter the window list
        // by, and a bounds test without that filter matches the Dock for ever (probe P-78).
        case .displayFairness:
            switch capability {
            case .frontmostApplication, .windowMetadata, .displayGeometry:
                return .featureAbsent
            case .idle, .systemLifecycle, .presentation, .microphoneActivity,
                 .cameraActivity, .accessibilityWindowContext, .screenCapture,
                 .notifications, .onDeviceModel, .calendarEvents:
                return .fullFunction
            }

        // Presentation detection is a quorum of three signals. Lose one and it leans on the
        // others; lose the subject itself and it stands down, because "I cannot tell whether
        // you are presenting" must never resolve to "so I will interrupt you".
        case .presentationSuppression:
            switch capability {
            case .presentation, .frontmostApplication: return .suppressOnly
            case .windowMetadata: return .degraded(to: .presentation)
            case .idle, .systemLifecycle, .displayGeometry, .microphoneActivity,
                 .cameraActivity, .accessibilityWindowContext, .screenCapture,
                 .notifications, .onDeviceModel, .calendarEvents:
                return .fullFunction
            }

        // The microphone half stands on its own evidence and ships. The camera half is held
        // off on every Mac, so this rule was designed from the start to work without it —
        // which is why its absence is a documented degradation and not a loss.
        case .mediaSuppression:
            switch capability {
            case .microphoneActivity: return .suppressOnly
            case .cameraActivity: return .degraded(to: .microphoneActivity)
            case .frontmostApplication, .windowMetadata, .idle, .systemLifecycle,
                 .displayGeometry, .presentation, .accessibilityWindowContext,
                 .screenCapture, .notifications, .onDeviceModel, .calendarEvents:
                return .fullFunction
            }

        // Lock detection's **primary** signal is an ordinary activation — `com.apple.loginwindow`
        // becoming frontmost, measured 1.5 ms before the undocumented distributed notification
        // (probe P-87). So the lifecycle capability degrading to the frontmost one is not a
        // consolation prize; it is very nearly the same mechanism.
        case .lifecyclePause:
            switch capability {
            case .systemLifecycle: return .degraded(to: .frontmostApplication)
            case .frontmostApplication: return .showUnavailable
            case .windowMetadata, .idle, .displayGeometry, .presentation,
                 .microphoneActivity, .cameraActivity, .accessibilityWindowContext,
                 .screenCapture, .notifications, .onDeviceModel, .calendarEvents:
                return .fullFunction
            }

        case .idlePause:
            switch capability {
            case .idle: return .showUnavailable
            case .frontmostApplication, .windowMetadata, .systemLifecycle, .displayGeometry,
                 .presentation, .microphoneActivity, .cameraActivity,
                 .accessibilityWindowContext, .screenCapture, .notifications, .onDeviceModel, .calendarEvents:
                return .fullFunction
            }

        // The cheapest-signal-first cascade, described as a table. Each tier degrades to the
        // one below it, and the model degrades to the heuristic — which the charter requires
        // to be always present and independently tested, never a fallback in name only.
        case .classification:
            switch capability {
            case .frontmostApplication: return .showUnavailable
            case .windowMetadata, .onDeviceModel: return .degraded(to: .frontmostApplication)
            case .accessibilityWindowContext: return .degraded(to: .windowMetadata)
            case .idle, .systemLifecycle, .displayGeometry, .presentation,
                 .microphoneActivity, .cameraActivity, .screenCapture, .notifications, .calendarEvents:
                return .fullFunction
            }

        // Every missing suppression input makes the ladder quieter, never louder. That
        // asymmetry is the whole design: a nudge that should not have fired costs trust, and a
        // nudge that did not fire costs a nudge.
        //
        // **`.notifications` is `.fullFunction`, and that is a fact about the router rather than
        // a kindness** (focus-i1g, U-2). It used to say `.degraded(to: .frontmostApplication)`,
        // which the Privacy pane rendered — on every fresh install, where the capability sits at
        // `.notRequested` — as *"Falls back to 'Which app is in front' and keeps working"*. There
        // is nothing to fall back **from**: `SurfaceRouter.route(rung:…)` takes no authorisation
        // and has only an `.ambient` and a `.panel` branch, no production code reads
        // `Capability.notifications` at all, and the Release self-check asserts that no rung
        // routes to a notification. So the pane was telling a person they were running a reduced
        // product — on the one surface whose contract is to say plainly what it cannot do, and
        // which carries no call to action they could have used to resolve it — about a permission
        // this app was repaired never to want. `notificationsCostThisLadderNothing` pins the cell
        // and enumerates the router that justifies it.
        case .nudgeLadder:
            switch capability {
            case .frontmostApplication: return .showUnavailable
            case .windowMetadata, .onDeviceModel:
                return .degraded(to: .frontmostApplication)
            case .accessibilityWindowContext: return .degraded(to: .windowMetadata)
            case .cameraActivity: return .degraded(to: .microphoneActivity)
            case .idle, .systemLifecycle, .displayGeometry, .presentation,
                 .microphoneActivity:
                return .suppressOnly
            case .screenCapture, .notifications, .calendarEvents: return .fullFunction
            }

        // **`.calendarEvents` is `.fullFunction` in every row** (focus-cal). The calendar is an
        // enrichment the person switches on: it refuses a timebox that would run into a meeting
        // and keeps the ladder quiet while one is under way. Without it the app does exactly
        // what it did before the switch existed — so no consumer degrades, and `.suppressOnly`
        // would be wrong in the ladder's row: it would quiet the ladder on every default install,
        // where the capability sits at `.notRequested`.
        //
        // A T3 nicety, and the one consumer permitted to simply not be there.
        case .analytics:
            switch capability {
            case .frontmostApplication: return .featureAbsent
            case .displayGeometry: return .degraded(to: .frontmostApplication)
            case .windowMetadata, .idle, .systemLifecycle, .presentation,
                 .microphoneActivity, .cameraActivity, .accessibilityWindowContext,
                 .screenCapture, .notifications, .onDeviceModel, .calendarEvents:
                return .fullFunction
            }
        }
    }

    /// Every cell, as a value — for the totality test, and for the Privacy surface that
    /// renders the table for the user to read.
    public static var allCells: [(capability: Capability, consumer: SensingConsumer, fallback: CapabilityFallback)] {
        Capability.allCases.flatMap { capability in
            SensingConsumer.allCases.map { consumer in
                (capability, consumer, fallback(for: capability, consumer: consumer))
            }
        }
    }
}
