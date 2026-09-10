import AppKit
import FocusCore
import Testing
import SwiftUI
@testable import FocusUI

@Suite("Companion artwork", .enabled(if: LocalizationLane.catalogsAreCompiled))
@MainActor
struct CompanionArtworkTests {
    @Test("the runtime asset catalogue contains both companion compositions", arguments: ["CompanionHeader", "CompanionHeaderWide"])
    func headerIsInTheRuntimeCatalogue(name: String) throws {
        let image = try #require(ShellStrings.bundle.image(forResource: name))
        #expect(image.size.width > image.size.height)
        #expect(image.size.height > 0)
    }
    @Test("the companion survives narrow and wide native windows", arguments: [248, 336, 448, 720, 1200])
    func headerAcrossWindowWidths(width: Int) throws {
        try SnapshotHarness.assertSnapshot(
            CompanionHeader { Text("Focus Sentinel").font(.title2) },
            component: "companionHeader.width\(width)", variant: "light", width: CGFloat(width)
        )
    }
}
