import Foundation

/// Whether this Mac can be asked, and if not, why not — **in this programme's vocabulary, not
/// the framework's.**
///
/// `FoundationModels` is named in exactly one file in this repository and that file is in
/// `Packages/FocusModel` (`check-forbidden.sh` R-117a counts them). So the availability reading
/// crosses the package boundary as one of these cases, and everything downstream — the
/// capability matrix, the self-check, the composed ladder — reads a `FocusCore` enum. That is
/// also what lets `FocusSensing`'s platform probe report a real answer without importing a
/// framework its row does not permit.
///
/// ## R-108's two prohibitions are why the "not enabled" case is a state and not a prompt
///
/// **The app never asks a person to enable Apple Intelligence.** No prompt, no nag, no
/// `openSettings` deep link presented as a precondition, no *"unlock smarter focus"* copy. A
/// person who has it on gets a better app; a person who does not is never told they are missing
/// out. So these cases exist to be *reported* in the Privacy pane's capability matrix and
/// nowhere else, and none of them reaches a button — which `check-strings.sh` enforces for the
/// whole epic.
///
/// **And the app never triggers or waits on an asset download.** `.availability` is a read.
/// `.modelNotReady` means *not available, until the OS says otherwise*: nothing polls for it
/// (R-117e) and nothing requests it (R-117d).
public enum ModelTierAvailability: String, Sendable, CaseIterable, Codable, Hashable {
    /// The system model answered that it is ready.
    case available
    /// The person has not turned Apple Intelligence on. **Not something this app asks about.**
    case appleIntelligenceNotEnabled
    /// Enabled, but the asset is not on the disk yet. We do not fetch it and we do not wait.
    case modelNotReady
    /// This Mac does not offer the model at all.
    case deviceNotEligible
    /// Available, but the machine is hot or on Low Power Mode (R-107). A person whose fan spins
    /// up must not watch the app change its mind about what their work is — so this stops new
    /// requests and never revokes what is already known.
    case suppressedByResources
    /// A case this OS reports that this build has no name for. Read as unavailable, always: a
    /// state we cannot name is not a state we may treat as ready.
    case unknown

    /// Whether the model rung may be composed into the ladder.
    public var isExecutable: Bool { self == .available }

    /// The capability matrix's answer, total over every case.
    ///
    /// `CapabilityProbing` used to hardcode `.onDeviceModel: .notRequested`, which stopped
    /// being true the moment the app could read the availability — *"nothing has been asked"*
    /// is a lie about a build that asks. `.notRequested` survives for exactly one case: a build
    /// composed with no model port has genuinely not looked.
    ///
    /// Nothing here is `.denied`. `.denied` means *the user said no to us*, and this app asks
    /// nobody anything: Apple Intelligence being off is a setting of theirs we read and never
    /// touch, which is `.unavailable` — *the platform does not offer it here* — and not a
    /// refusal aimed at us.
    public var capabilityState: CapabilityState {
        switch self {
        case .available: .available
        case .appleIntelligenceNotEnabled, .modelNotReady, .deviceNotEligible,
             .suppressedByResources, .unknown: .unavailable
        }
    }
}
