import SwiftUI

/// The one margin every dialog draws (focus-udn9). See `DesignTokens.dialogInset` for the
/// number and for why it does not grow with the text.
extension View {
    /// The margin between a dialog's edge and its content.
    ///
    /// Applied once, at the outermost edge of a sheet, a floating panel's content or a Settings
    /// pane — never nested, and never beside a second `.padding(…)` of its own.
    func dialogInset() -> some View {
        padding(DesignTokens.dialogInset)
    }

    /// The margin inside a popover's content. See `DesignTokens.popoverInset`.
    func popoverInset() -> some View {
        padding(DesignTokens.popoverInset)
    }
}
