import AppKit
import FocusCore
import SwiftUI

/// **One application on the presentation-exclusion list, as the pane draws it** (F-121,
/// focus-62o, focus-u3w).
///
/// The identifier and the name the person would recognise, together, because the pane cannot
/// draw one without the other and the list is keyed on the first: a row showing *Keynote* has to
/// be able to say `com.apple.iWork.Keynote` when it is removed, and a row showing a bundle
/// identifier is a row nobody can read.
public struct PresentationExclusion: Sendable, Equatable, Hashable, Identifiable {
    public let bundleID: String
    /// What `NSRunningApplication.localizedName` said, or the identifier when the application is
    /// not running and there is nobody to ask. **Never a window title** — the localised name of
    /// an application is a fact about the app, not about what is open in it (standing
    /// condition 1).
    public let displayName: String

    public var id: String { bundleID }

    public init(bundleID: String, displayName: String) {
        self.bundleID = bundleID
        self.displayName = displayName
    }

    /// One rendered line, for the receipt.
    public var rendered: String { "\(displayName) (\(bundleID))" }
}

/// **Which applications are running, by the name a person would recognise** (focus-62o, focus-u3w).
///
/// ## Why this needs no grant, and how that is known
///
/// `NSWorkspace.runningApplications` is a list of processes with a user interface and their
/// localised names. It reads no window, names no document and asks for nothing: probe P-79
/// measured the frontmost-application path as prompt-free and this is the same API family, and
/// R-33's lint keeps every prompting call out of the binary regardless. What it emphatically is
/// **not** is a window-title read — the name of an application is a fact about the application.
///
/// ## Why the reading is injectable
///
/// The list is a fact about the machine the app is running on, so a test that read the live one
/// would be a test of whatever happened to be open. The composition root supplies the live
/// reading; every lane supplies its own.
public enum RunningApplications {
    /// Applications a person could plausibly present from: ordinary windowed apps, named, not
    /// this one, sorted by the name they read.
    ///
    /// `.regular` and nothing else, because a menu-bar-only agent or a background service is not
    /// something anybody gives a presentation out of, and a list padded with them is a list
    /// nobody scrolls to the end of.
    @MainActor
    public static func choices(
        from applications: [NSRunningApplication] = NSWorkspace.shared.runningApplications,
        excluding ownBundleID: String = Bundle.main.bundleIdentifier ?? ""
    ) -> [PresentationExclusion] {
        var seen = Set<String>()
        return applications
            .filter { $0.activationPolicy == .regular }
            .compactMap { application -> PresentationExclusion? in
                guard
                    let bundleID = application.bundleIdentifier,
                    bundleID != ownBundleID,
                    seen.insert(bundleID).inserted
                else { return nil }
                return PresentationExclusion(
                    bundleID: bundleID,
                    displayName: application.localizedName ?? bundleID
                )
            }
            .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }
}

/// The Intervention pane's presentation-exclusion section (F-121, focus-62o, focus-u3w).
///
/// ## What was here before, and why it was deleted
///
/// A heading and a sentence: *"Nothing yet. Add an app here when Focus mistakes its full-screen
/// window for a presentation."* There was **no add affordance in that section and none anywhere
/// else in the application** — `SensitiveAppSeed.add` had no shipping call site at all, and the
/// presentation-exclusion list seeds empty, so the list was empty for every person for ever and
/// the section could never draw a row. Its Remove button was therefore unreachable too. A section
/// whose only user-reachable half is an instruction nobody can follow is worse than a dead
/// control, so it was deleted rather than reworded, and the capability's unreachability was
/// recorded on `focus-62o` rather than left in a comment.
///
/// This is that bead. The list, the rows, a Remove on each, and the half that was missing: an add
/// row naming the applications that are running right now, by the name their menus use.
///
/// ## Why a list of buttons and not a `Menu` or a `Picker`
///
/// Measured, not preferred: an AppKit-backed control does not rasterise under `ImageRenderer` —
/// a `Picker` renders as SwiftUI's unrenderable-view placeholder glyph on a white ground,
/// whatever appearance is injected — so a picker here would make any committed baseline a
/// picture of a broken render. A `Button` renders fine. The prep for this round says so in as
/// many words, and this is that note obeyed rather than rediscovered.
public struct PresentationExclusionSection: View {
    let excluded: [PresentationExclusion]
    let addable: [PresentationExclusion]
    let onAction: (InterventionSettingsAction) -> Void

    init(
        excluded: [PresentationExclusion],
        addable: [PresentationExclusion],
        onAction: @escaping (InterventionSettingsAction) -> Void
    ) {
        self.excluded = excluded
        self.addable = addable
        self.onAction = onAction
    }

    @Environment(\.appearanceTraits) private var traits
    @Environment(\.shellTextScale) private var textScale
    @ScaledMetric(relativeTo: .body) private var spacing: CGFloat = 12

    /// The strings this section draws.
    nonisolated public static let contentKeys: [ShellStringKey] = [
        .interventionExclusionHeading,
        .interventionExclusionExplanation,
        .interventionExclusionEmpty,
        .interventionExclusionAddHeading,
        .interventionExclusionNoneRunning,
        .interventionExclusionRemove
    ]

    /// **How many applications the add row offers at once.**
    ///
    /// A person with thirty applications open does not want thirty buttons in a settings pane,
    /// and a settings pane that grows without bound is the defect `BoundedSurface` exists for.
    /// Twelve, and the rest are reachable the moment one of these is added or an app is quit —
    /// the list is a reading of what is running, so it changes on its own.
    public static let addableLimit = 12

    public var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.spacing(spacing / 2, scale: textScale)) {
            ShellText(.interventionExclusionHeading, role: .headline)
            ShellText(.interventionExclusionExplanation, role: .footnote)
                .foregroundStyle(DesignTokens.supportingTextColor(for: traits))
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)

            if excluded.isEmpty {
                ShellText(.interventionExclusionEmpty, role: .callout)
                    .foregroundStyle(DesignTokens.supportingTextColor(for: traits))
            } else {
                ForEach(excluded) { entry in
                    HStack(spacing: spacing / 2) {
                        // The application's own name is **data**, not prose: it is what the
                        // person's Mac calls that app, and routing it through a catalog would be
                        // translating somebody else's product name.
                        Text(verbatim: entry.displayName)
                            .font(DesignTokens.font(.callout, scale: textScale))
                        Spacer(minLength: 0)
                        Button {
                            onAction(.removePresentationExclusion(entry.bundleID))
                        } label: {
                            ShellText(.interventionExclusionRemove)
                        }
                        .accessibilityLabel(Text(verbatim: entry.displayName))
                        // Every control carries a tooltip (focus-8ski).
                        .shellHelp(.interventionExclusionRemoveHelp)
                    }
                }
            }

            ShellText(.interventionExclusionAddHeading, role: .callout)
                .padding(.top, spacing / 3)
            if addable.isEmpty {
                ShellText(.interventionExclusionNoneRunning, role: .footnote)
                    .foregroundStyle(DesignTokens.supportingTextColor(for: traits))
            } else {
                ForEach(addable.prefix(Self.addableLimit)) { candidate in
                    Button {
                        onAction(.addPresentationExclusion(candidate.bundleID))
                    } label: {
                        Text(verbatim: candidate.displayName)
                            .font(DesignTokens.font(.callout, scale: textScale))
                    }
                    .buttonStyle(.link)
                    .shellHelp(.interventionExclusionAddHelp)
                }
            }
        }
    }

    /// What this section drew, as one line the render report can carry.
    nonisolated public static func rendered(excluded: [PresentationExclusion], addable: [PresentationExclusion]) -> String {
        let list = excluded.isEmpty ? "none" : excluded.map(\.rendered).joined(separator: ", ")
        return "excluded: \(list); addable: \(min(addable.count, addableLimit))"
    }
}
