import AppKit
import FocusCore
import SwiftUI

/// **The app's own mark for a status, as ink** (focus-w41, e11 direction §1.2).
///
/// `FocusStatus.markAssetName` is a *name*: `FocusCore` imports Foundation and cannot name an
/// image, and the catalogue that holds the five marks ships with `FocusUI`, which owns every
/// pixel this app draws. This is the seam between the two, and it is the only place in the
/// repository that resolves a mark.
///
/// ## Why the family exists at all
///
/// The five states were SF Symbols until e11b — a filled circle, a diamond, a triangle, a
/// rectangle and a cup. They satisfied the doctrine `FocusStatus` states ("silhouettes are
/// deliberately unalike") but they were five unrelated objects, so the app's most-seen surface
/// said nothing about the app. The family keeps the ring — already the app icon's mark — and
/// **breaks the outline** per state rather than moving a dot inside a constant one, which at
/// 16 pt in monochrome is the difference between a signal and a hope.
///
/// ## What it costs, and what pays it back
///
/// A drawn asset loses two things an SF Symbol gives away: hierarchical rendering, and an
/// accessibility description the system wrote. The first is not missed — these are one-weight
/// outlines and hierarchical rendering had nothing to grade. The second is paid back in the
/// catalogue: `FocusStatus.markDescription` is an authored sentence per state, and
/// `image(for:)` puts it on the `NSImage` itself so it travels with the picture rather than
/// with whichever view happened to draw it.
///
/// ## Template, always
///
/// Every asset is declared `template-rendering-intent: template` and every pixel in it is black
/// with a coverage alpha. F-146 is that the menu bar decides the ink; a bitmap carrying its own
/// colours is the one thing that would break it, and it cannot happen by accident here because
/// there is no colour in the files.
public enum StatusMark {
    /// The mark as a SwiftUI image, ready to be tinted by `foregroundStyle`.
    ///
    /// `Image(_:bundle:)` against this package's own bundle, because the catalogue ships with
    /// `FocusUI` and not with the app.
    public static func image(for status: FocusStatus) -> Image {
        Image(status.markAssetName, bundle: .module)
            .renderingMode(.template)
    }

    /// The mark as an `NSImage`, template-rendered, carrying its own accessibility description.
    ///
    /// `nil` when the catalogue is not compiled — which is every SwiftPM lane, because SwiftPM
    /// copies an `.xcassets` verbatim (the same split `LocalizationLane` records for String
    /// Catalogs). The caller decides what to do about that; `MenuBarController` falls back to the
    /// SF Symbol the status still names, so a lane with no `Assets.car` draws *something* rather
    /// than an empty status item.
    public static func nsImage(for status: FocusStatus) -> NSImage? {
        guard let image = Bundle.module.image(forResource: status.markAssetName) else {
            return nil
        }
        image.isTemplate = true
        image.accessibilityDescription = status.markDescription
        return image
    }

    /// Whether this build can resolve the drawn family at all.
    ///
    /// The sibling of `DesignTokens.Palette.catalogIsCompiled`, published by the self-check for
    /// the same reason: a build that silently fell back to the SF Symbols would be a build
    /// wearing the old identity, and no snapshot of a package test would ever say so.
    public static var catalogIsCompiled: Bool {
        FocusStatus.allCases.allSatisfy {
            Bundle.module.image(forResource: $0.markAssetName) != nil
        }
    }
}
