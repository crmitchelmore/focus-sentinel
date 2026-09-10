import FocusCore
import Foundation
import Testing

@testable import FocusUI

/// **The nudge asks the same seam "Back to …" asks, and keeps the answer** (focus-ebv, R-88).
@Suite("Subject naming")
@MainActor
struct SubjectNamingTests {
    private static let safari = "com.apple.Safari"
    private static let figma = "com.figma.Desktop"

    private static func workspace() -> StubReturnWorkspace {
        let workspace = StubReturnWorkspace()
        workspace.runningNames[safari] = "Safari"
        return workspace
    }

    private static func query(_ identifier: String) throws -> QuerySubject {
        try #require(
            QuerySubject.derive(
                judgedSubject: identifier,
                explanation: Explanation.make(
                    stage: .heuristic,
                    band: .low,
                    clauses: [.insufficientEvidence(reason: .noNegativeBasis)],
                    stamp: .current
                )
            )
        )
    }

    // MARK: - The name, from the seam that already had it

    /// The defect in one assertion: the same workspace call that produced *"Back to Pages"*
    /// produces the word the sentence uses, and the key is untouched beside it.
    @Test("a running application is named, and the key it is filed under is not touched")
    func namesARunningApplication() throws {
        let naming = SubjectNaming(workspace: Self.workspace())
        let subject = try #require(naming.subject(Self.safari))
        #expect(subject.displayName == "Safari")
        #expect(subject.identifier == Self.safari)
    }

    @Test("a question's subject is named the same way, with no failure case to handle")
    func namesAQuestionsSubject() throws {
        let naming = SubjectNaming(workspace: Self.workspace())
        #expect(naming.subject(of: try Self.query(Self.safari)).displayName == "Safari")
        #expect(naming.subject(of: try Self.query(Self.safari)).identifier == Self.safari)
    }

    // MARK: - Not running is not the same as not installed (focus-7gc)

    /// The sentence and the button under it ask the disk the same question.
    ///
    /// Before this, `SubjectNaming` asked only whether the subject was **running**, so a panel
    /// about an application that had quit said *"You've been in com.figma.Desktop"* — focus-ebv's
    /// own defect, one branch further down.
    @Test("an application that is installed but not running is named from its bundle")
    func installedApplicationsAreNamed() throws {
        let workspace = Self.workspace()
        let url = URL(fileURLWithPath: "/Applications/Figma.app")
        workspace.installedURLs[Self.figma] = url
        workspace.installedNames[url] = "Figma"

        let subject = try #require(SubjectNaming(workspace: workspace).subject(Self.figma))
        #expect(subject.displayName == "Figma")
        #expect(subject.identifier == Self.figma)
        // The disk is asked only after the running lookup came back with nothing.
        #expect(workspace.lookups == [Self.figma])
        #expect(workspace.bundleLookups == [url])
    }

    /// The answer read from the disk is **not** memoised, because it cannot change under a
    /// reader — and leaving it out is what keeps the promise that an application asked about
    /// before it finished launching answers with its running name next time.
    @Test("an installed name gives way to the running one, and a running one is kept")
    func theInstalledNameIsNotLearned() throws {
        let workspace = Self.workspace()
        let url = URL(fileURLWithPath: "/Applications/Figma.app")
        workspace.installedURLs[Self.figma] = url
        workspace.installedNames[url] = "Figma"
        let naming = SubjectNaming(workspace: workspace)

        #expect(try #require(naming.subject(Self.figma)).displayName == "Figma")
        workspace.runningNames[Self.figma] = "Figma Beta"
        #expect(try #require(naming.subject(Self.figma)).displayName == "Figma Beta")
        // And now it is, because a running name is one a live surface could see change.
        workspace.runningNames.removeValue(forKey: Self.figma)
        #expect(try #require(naming.subject(Self.figma)).displayName == "Figma Beta")
    }

    // MARK: - What it does when there is no name

    /// The bead's own question, answered: the sentence is the identifier, never nothing.
    @Test("an application that is neither running nor installed renders its identifier")
    func unnamedApplicationsFallBackToTheIdentifier() throws {
        let naming = SubjectNaming(workspace: Self.workspace())
        let subject = try #require(naming.subject(Self.figma))
        #expect(subject.displayName == Self.figma)
        #expect(!subject.displayName.isEmpty)
    }

    /// Every way a lookup can answer with something that is not a name, on both branches.
    /// `FileManager.displayName` really does return `"   "` for a bundle called `   .app` —
    /// measured — so the whitespace row is a state of the world rather than a defensive case.
    @Test(
        "a name that is only whitespace is no name, whichever lookup produced it",
        arguments: ["", "   ", "\n\t"]
    )
    func blankNamesAreNoName(blank: String) throws {
        let running = Self.workspace()
        running.runningNames[Self.figma] = blank
        #expect(try #require(SubjectNaming(workspace: running).subject(Self.figma))
            .displayName == Self.figma)

        let installed = Self.workspace()
        let url = URL(fileURLWithPath: "/Applications/Figma.app")
        installed.installedURLs[Self.figma] = url
        installed.installedNames[url] = blank
        #expect(try #require(SubjectNaming(workspace: installed).subject(Self.figma))
            .displayName == Self.figma)
    }

    /// Drift across several applications names nobody, and naming is not where that changes.
    @Test("there is nothing to name for an absent subject")
    func absentSubjectsNameNobody() {
        let naming = SubjectNaming(workspace: Self.workspace())
        for identifier in [nil, "", "   "] as [String?] {
            #expect(naming.subject(identifier) == nil)
        }
    }

    // MARK: - Learned once, kept for the session

    /// A sticky panel must not rewrite its own sentence while somebody is reading it. The count
    /// is the assertion: a second ask would be a second chance to disagree.
    @Test("the workspace is asked once per identifier, however often the surface redraws")
    func theNameIsLearnedOnce() throws {
        let workspace = Self.workspace()
        let naming = SubjectNaming(workspace: workspace)

        for _ in 0..<5 { _ = naming.subject(Self.safari) }
        _ = naming.subject(of: try Self.query(Self.safari))

        #expect(workspace.lookups == [Self.safari])
    }

    /// The panel outlives the application it accuses. It goes on saying the true thing.
    @Test("a name survives the application quitting, because the accusation is still on screen")
    func theNameOutlivesTheApplication() throws {
        let workspace = Self.workspace()
        let naming = SubjectNaming(workspace: workspace)
        #expect(try #require(naming.subject(Self.safari)).displayName == "Safari")

        workspace.runningNames.removeValue(forKey: Self.safari)
        #expect(try #require(naming.subject(Self.safari)).displayName == "Safari")
    }

    /// The fallback is **not** learned: an application asked about while it was still launching
    /// must not be called by its bundle identifier for the rest of the session.
    @Test("a missing name is not remembered, so the next ask can find the real one")
    func theFallbackIsNotLearned() throws {
        let workspace = Self.workspace()
        let naming = SubjectNaming(workspace: workspace)
        #expect(try #require(naming.subject(Self.figma)).displayName == Self.figma)

        workspace.runningNames[Self.figma] = "Figma"
        #expect(try #require(naming.subject(Self.figma)).displayName == "Figma")
    }

    // MARK: - An origin is never looked up

    /// No application owns an origin, so a lookup could only return a browser's name for a site.
    @Test("an origin is derived rather than asked about, and the workspace is never consulted")
    func originsAreNeverLookedUp() throws {
        let workspace = Self.workspace()
        let naming = SubjectNaming(workspace: workspace)
        let subject = try #require(naming.subject("https://docs.google.com"))
        #expect(subject.displayName == "docs.google.com")
        #expect(subject.identifier == "https://docs.google.com")
        #expect(workspace.lookups.isEmpty)
        // **Both** lookups, now that there are two. A guard that only covered the first would
        // leave the disk being asked what application owns a website.
        #expect(workspace.bundleLookups.isEmpty)
    }
}
