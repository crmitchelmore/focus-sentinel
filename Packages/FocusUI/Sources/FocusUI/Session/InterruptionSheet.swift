import AppKit
import FocusCore
import SwiftUI

/// Stopping a session, and saying why (F-101).
///
/// ## What it asks for, and what it promises
///
/// A reason, an optional note about where to pick the work up, and the last application that
/// was in front — which the app already knows, as a bundle identifier, and resolves to a real
/// name and icon through `NSWorkspace` with no grant of any kind (probe P-67).
///
/// It promises **nothing else**. It does not offer to reopen a document, restore a scroll
/// position or reach into another application: the Feasibility Court cut that half of F-101,
/// and no string in this file implies otherwise. What comes back at restart is the same task
/// and the words the person wrote, and that is all it was ever going to be.
///
/// ## Stop is enabled with every field empty
///
/// Reflection is offered, never extracted. The reason picker starts on `.user` — the honest
/// default for a sheet a person opened by pressing a button — and the note is optional. There
/// is no validation here and nothing is ever refused.
///
/// ## Why this is not in the snapshot matrix
///
/// Measured on this machine and recorded in e01's `SnapshotTests`: an AppKit-backed control
/// does not rasterise under `ImageRenderer`. A `TextField` or a `Picker` draws SwiftUI's yellow
/// "unrenderable view" placeholder whatever appearance is injected, so a committed baseline of
/// this sheet would be a picture of a broken control. It is covered structurally instead, and
/// by the TCC-gated live frames where AppKit draws it for real.
public struct InterruptionSheet: View {
    /// The last application in front that was not this one, as a bundle identifier. `nil` when
    /// nothing has been observed — a first launch, or sensing switched off.
    public let lastActiveBundleID: String?

    /// Stop the session, with the reason and the note as they stand.
    public let stop: (InterruptionReason, String?) -> Void

    /// Close the sheet and change nothing.
    public let cancel: () -> Void

    @Environment(\.appearanceTraits) private var traits
    @Environment(\.shellTextScale) private var textScale
    @FocusState private var focus: FocusField?
    @ScaledMetric(relativeTo: .body) private var spacing: CGFloat = 12

    @State private var reason: InterruptionReason = .user
    @State private var note: String = ""

    public init(
        lastActiveBundleID: String? = nil,
        stop: @escaping (InterruptionReason, String?) -> Void,
        cancel: @escaping () -> Void
    ) {
        self.lastActiveBundleID = lastActiveBundleID
        self.stop = stop
        self.cancel = cancel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            ShellText(.sessionInterruptHeading, role: .title3)

            ShellText(.sessionInterruptExplanation, role: .callout)
                .foregroundStyle(DesignTokens.supportingTextColor(for: traits))
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)

            reasonPicker
            noteField
            lastActive

            HStack(spacing: spacing) {
                Spacer(minLength: 0)

                Button {
                    cancel()
                } label: {
                    ShellText(.sessionInterruptCancel)
                }
                .keyboardShortcut(.cancelAction)
                .focused($focus, equals: .interruptCancel)

                Button {
                    let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
                    stop(reason, trimmed.isEmpty ? nil : trimmed)
                } label: {
                    ShellText(.sessionInterruptConfirm)
                }
                // Enabled with every field empty. Reflection is offered, never extracted.
                .keyboardShortcut(.defaultAction)
                .focused($focus, equals: .interruptConfirm)
            }
        }
        .padding(spacing * 2)
        .frame(minWidth: 420, alignment: .leading)
        .defaultFocus($focus, .interruptReason)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(ShellStrings.resource(.sessionInterruptHeading)))
    }

    // MARK: - The reason

    private var reasonPicker: some View {
        VStack(alignment: .leading, spacing: spacing / 3) {
            ShellText(.sessionInterruptReasonLabel, role: .caption)
                .foregroundStyle(DesignTokens.supportingTextColor(for: traits))

            Picker(selection: $reason) {
                ForEach(InterruptionReason.allCases, id: \.self) { value in
                    ShellText(Self.labelKey(for: value)).tag(value)
                }
            } label: {
                ShellText(.sessionInterruptReasonLabel)
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .focused($focus, equals: .interruptReason)
            .accessibilityLabel(Text(ShellStrings.resource(.sessionInterruptReasonLabel)))
        }
    }

    // MARK: - The restart point

    private var noteField: some View {
        VStack(alignment: .leading, spacing: spacing / 3) {
            ShellText(.sessionInterruptNoteLabel, role: .caption)
                .foregroundStyle(DesignTokens.supportingTextColor(for: traits))

            TextField(
                text: $note,
                prompt: Text(ShellStrings.resource(.sessionInterruptNotePrompt))
            ) {
                ShellText(.sessionInterruptNoteLabel)
            }
            .labelsHidden()
            .font(DesignTokens.font(.body, scale: textScale))
            .focused($focus, equals: .interruptNote)
            .accessibilityLabel(Text(ShellStrings.resource(.sessionInterruptNoteLabel)))
        }
    }

    // MARK: - The context the app already has

    /// One application, by bundle identifier — and nothing else.
    ///
    /// Not a window title, not a document, not a URL. The identifier is data rather than prose,
    /// so where no installed application answers to it the identifier itself is drawn verbatim
    /// rather than routed through a catalog.
    @ViewBuilder
    private var lastActive: some View {
        VStack(alignment: .leading, spacing: spacing / 3) {
            ShellText(.sessionInterruptLastActiveLabel, role: .caption)
                .foregroundStyle(DesignTokens.supportingTextColor(for: traits))

            if let bundleID = lastActiveBundleID {
                let info = InstalledApplication.info(bundleID: bundleID)
                Label {
                    Text(verbatim: info?.name ?? bundleID)
                        .font(DesignTokens.font(.callout, scale: textScale))
                        .lineLimit(1)
                        .truncationMode(.middle)
                } icon: {
                    if let icon = info?.icon {
                        Image(nsImage: icon).resizable().frame(width: 16, height: 16)
                    } else {
                        Image(systemName: "app.dashed")
                    }
                }
            } else {
                ShellText(.sessionInterruptLastActiveNone, role: .callout)
                    .foregroundStyle(DesignTokens.supportingTextColor(for: traits))
            }
        }
    }

    // MARK: - Labels

    /// The catalog key for one interruption reason. `FocusCore` returns the typed value; the
    /// words for it live here (plan R-52).
    nonisolated public static func labelKey(for reason: InterruptionReason) -> ShellStringKey {
        switch reason {
        case .user: .sessionInterruptReasonUser
        case .priorityChanged: .sessionInterruptReasonPriorityChanged
        case .appQuit: .sessionInterruptReasonAppQuit
        case .systemRestart: .sessionInterruptReasonSystemRestart
        case .timeboxAbandoned: .sessionInterruptReasonTimeboxAbandoned
        }
    }
}
