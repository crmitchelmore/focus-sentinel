import AppKit
import Foundation
import SwiftUI
import Testing

@testable import FocusUI

/// F-02 and F-147, as a structural assertion rather than a matter of taste.
///
/// The promise is that the priority is *always* more prominent than anything else the app
/// draws — "always more prominent than any analytics" is the Court's wording, and e09 is the
/// epic that will be tempted to break it. Two things make that checkable:
///
/// 1. **The hero is the largest role.** `priorityHero > largeTitle ≥ every other role`, at
///    every text scale. A later epic that gives a secondary surface a bigger font has to
///    declare a role for it, and this suite fails the moment that role outranks the hero.
/// 2. **The hero is used once.** A type role used twice is no longer a hero; it is a heading
///    style. The scan below reads the package's own sources and requires exactly one use
///    site, in the one view whose whole job is to draw the priority.
///
/// Both run headless, with no window and no grant.
@Suite("Type hierarchy")
struct TypeHierarchyTests {
    // MARK: - The hero outranks everything

    @Test("the priority hero is strictly larger than every other type role")
    func heroOutranksEveryOtherRole() {
        let hero = DesignTokens.pointSize(.priorityHero)

        for role in DesignTokens.FontRole.allCases where role != .priorityHero {
            let other = DesignTokens.pointSize(role)
            #expect(
                hero > other,
                "priorityHero (\(hero)pt) is not larger than \(role.rawValue) (\(other)pt)"
            )
        }
    }

    @Test("largeTitle is the largest of the system roles, and the hero is derived from it")
    func largeTitleLeadsTheSystemRoles() {
        let largeTitle = DesignTokens.pointSize(.largeTitle)

        for role in DesignTokens.FontRole.allCases
        where role != .priorityHero && role != .largeTitle {
            #expect(
                largeTitle >= DesignTokens.pointSize(role),
                "largeTitle is smaller than \(role.rawValue)"
            )
        }

        // Derived, not hardcoded: the hero follows the system-wide Text Size setting because
        // its base is whatever the system says `.largeTitle` is worth today.
        #expect(
            DesignTokens.pointSize(.priorityHero)
                == largeTitle * DesignTokens.FontRole.heroScale
        )
        #expect(DesignTokens.FontRole.heroScale == 1.6)
    }

    @Test("the ordering survives the largest text scale")
    func orderingHoldsAtEveryScale() {
        for scale in ShellTextScale.allCases {
            let hero = DesignTokens.pointSize(.priorityHero, scale: scale)
            for role in DesignTokens.FontRole.allCases where role != .priorityHero {
                #expect(
                    hero > DesignTokens.pointSize(role, scale: scale),
                    "\(role.rawValue) overtakes the hero at \(scale.rawValue)"
                )
            }
        }

        // And the scale is a scale: the hero itself grows with it, rather than being pinned.
        #expect(
            DesignTokens.pointSize(.priorityHero, scale: .accessibilityLarge)
                > DesignTokens.pointSize(.priorityHero, scale: .standard)
        )
    }

    @Test("the hero is semibold, and no system role forces a weight of its own")
    func onlyTheHeroForcesAWeight() {
        #expect(DesignTokens.FontRole.priorityHero.weight == .semibold)
        for role in DesignTokens.FontRole.allCases where role != .priorityHero {
            #expect(
                role.weight == nil,
                "\(role.rawValue) forces a weight, so a call site's own .fontWeight would be ignored"
            )
        }
    }

    // MARK: - The hero is used exactly once

    @Test("the priority-hero role has exactly one use site in the whole package")
    func heroIsUsedExactlyOnce() throws {
        let uses = try Self.heroUseSites()

        #expect(
            uses.count == 1,
            "the priority hero must be drawn once and only once; found \(uses.count): \(uses.map(\.description).joined(separator: ", "))"
        )
        #expect(
            uses.first?.file == "PriorityHeroView.swift",
            "the hero role belongs to the view that draws the priority, not to \(uses.first?.file ?? "nothing")"
        )
    }

    // MARK: - Scanning the package's own sources

    /// One line of source that names the hero role.
    struct UseSite: CustomStringConvertible {
        let file: String
        let line: Int

        var description: String { "\(file):\(line)" }
    }

    /// `FocusUI`'s source directory, found from this file rather than from a bundle: the
    /// question is about the *sources*, and a test bundle does not contain them.
    static var sourceDirectory: URL {
        URL(filePath: #filePath)
            .deletingLastPathComponent()   // …/Tests/FocusUITests
            .deletingLastPathComponent()   // …/Tests
            .deletingLastPathComponent()   // …/FocusUI
            .appending(path: "Sources", directoryHint: .isDirectory)
            .appending(path: "FocusUI", directoryHint: .isDirectory)
    }

    /// The file that declares the role. Its own `case .priorityHero:` branches are the
    /// declaration, not a use of it.
    static let declarationFile = "DesignTokens.swift"

    /// `.priorityHero` as a whole member name.
    ///
    /// The word boundary is load-bearing: a plain substring search also matches the catalog
    /// key `.priorityHeroEmpty`, which is a *string*, not the type role, and counting it would
    /// make this assertion fail for a reason that has nothing to do with the hierarchy.
    static let heroReference = try! NSRegularExpression(pattern: #"\.priorityHero\b"#)

    static func heroUseSites() throws -> [UseSite] {
        var sites: [UseSite] = []
        let enumerator = FileManager.default.enumerator(
            at: sourceDirectory,
            includingPropertiesForKeys: nil
        )
        let files = (enumerator?.allObjects as? [URL] ?? [])
            .filter { $0.pathExtension == "swift" }
            .filter { $0.lastPathComponent != declarationFile }

        #expect(!files.isEmpty, "no sources found at \(sourceDirectory.path(percentEncoded: false))")

        for file in files.sorted(by: { $0.path < $1.path }) {
            let text = try String(contentsOf: file, encoding: .utf8)
            for (offset, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                // A comment naming the role is documentation, not a second hero.
                if trimmed.hasPrefix("//") || trimmed.hasPrefix("*") || trimmed.hasPrefix("/*") {
                    continue
                }
                let lineText = String(line)
                let range = NSRange(lineText.startIndex..<lineText.endIndex, in: lineText)
                if heroReference.firstMatch(in: lineText, range: range) != nil {
                    sites.append(UseSite(file: file.lastPathComponent, line: offset + 1))
                }
            }
        }
        return sites
    }
}
