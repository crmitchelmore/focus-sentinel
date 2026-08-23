import Foundation
import Testing

@testable import FocusCore

/// The session authority's only owner, and its lifetime (R-72.2).
///
/// The assertions here are all about *reachability*: what a session rule can be seen from, and
/// what it cannot. A rule that outlived its session would be a rule the person never agreed to,
/// applied to work they have since moved on from, and the only way to make that impossible
/// rather than unlikely is to give the value nowhere to survive.
@Suite("Session rule box")
@MainActor
struct SessionRuleBoxTests {
    static let reference = Date(timeIntervalSince1970: 1_767_225_600)
    static let session = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    static let otherSession = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
    static let priority = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
    static let otherPriority = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!

    static func rule(
        _ subject: String,
        _ verdict: PriorityRuleVerdict = .uncertain,
        kind: RuleSubjectKind = .app,
        authority: RuleAuthority = .session
    ) -> ScopedRuleValue {
        ScopedRuleValue(
            authority: authority,
            subjectKind: kind,
            subject: subject,
            verdict: verdict,
            createdAt: reference
        )
    }

    @Test("a fresh box is empty")
    func freshBoxIsEmpty() {
        let box = SessionRuleBox()
        #expect(box.isEmpty)
        #expect(box.count == 0)
        #expect(box.rules(forSession: Self.session, priorityID: Self.priority).isEmpty)
    }

    @Test("a rule inserted is a rule returned, at session authority")
    func insertThenRead() {
        let box = SessionRuleBox()
        box.insert(Self.rule("com.apple.Music"), forSession: Self.session, priorityID: Self.priority)

        let rules = box.rules(forSession: Self.session, priorityID: Self.priority)
        #expect(rules.map(\.subject) == ["com.apple.Music"])
        #expect(rules.first?.authority == .session)
        #expect(box.count == 1)
        #expect(!box.isEmpty)
    }

    /// The box **is** the definition of the session authority, so a value arriving with another
    /// one is a rule claiming a lifetime this box cannot give it. It is corrected, not stored
    /// as it came.
    @Test("a rule arriving at the wrong authority is stored at session authority anyway")
    func authorityIsForced() {
        let box = SessionRuleBox()
        box.insert(
            Self.rule("com.apple.Music", authority: .global),
            forSession: Self.session,
            priorityID: Self.priority
        )
        #expect(box.rules(forSession: Self.session, priorityID: Self.priority)
                    .allSatisfy { $0.authority == .session })
    }

    @Test("insert then clear leaves it empty")
    func insertThenClear() {
        let box = SessionRuleBox()
        box.insert(Self.rule("com.apple.Music"), forSession: Self.session, priorityID: Self.priority)
        box.clear(sessionID: Self.session)

        #expect(box.isEmpty)
        #expect(box.count == 0)
        #expect(box.rules(forSession: Self.session, priorityID: Self.priority).isEmpty)
    }

    /// Clearing one session takes every priority it held with it — the session is the lifetime,
    /// and a rule left behind under an old priority id would be a rule with no way to die.
    @Test("clearing a session takes every priority it held")
    func clearingASessionTakesEveryPriority() {
        let box = SessionRuleBox()
        box.insert(Self.rule("com.apple.Music"), forSession: Self.session, priorityID: Self.priority)
        box.insert(Self.rule("com.apple.TV"), forSession: Self.session, priorityID: Self.otherPriority)
        box.insert(Self.rule("com.apple.News"), forSession: Self.session, priorityID: nil)
        #expect(box.count == 3)

        box.clear(sessionID: Self.session)
        #expect(box.isEmpty)
    }

    @Test("a rule under one session is invisible to another")
    func sessionsAreIsolated() {
        let box = SessionRuleBox()
        box.insert(Self.rule("com.apple.Music"), forSession: Self.session, priorityID: Self.priority)

        #expect(box.rules(forSession: Self.otherSession, priorityID: Self.priority).isEmpty)
        box.clear(sessionID: Self.otherSession)
        #expect(box.rules(forSession: Self.session, priorityID: Self.priority).count == 1)
    }

    /// **The structural half of the lifetime contract.** "Until the priority changes" is a
    /// property of *lookup* rather than of housekeeping, so it cannot be forgotten by a hook
    /// somebody removes.
    @Test("a rule written under one priority is invisible under another")
    func aPriorityChangeHidesTheRuleWithNoHookAtAll()
    {
        let box = SessionRuleBox()
        box.insert(Self.rule("com.apple.Music"), forSession: Self.session, priorityID: Self.priority)

        #expect(box.rules(forSession: Self.session, priorityID: Self.otherPriority).isEmpty)
        #expect(box.rules(forSession: Self.session, priorityID: nil).isEmpty)
        #expect(box.rules(forSession: Self.session, priorityID: Self.priority).count == 1)
    }

    /// Two rules about the same subject are one rule. The person changed their mind; they did
    /// not author a contradiction, and the cascade's same-cell conflict rule exists for genuine
    /// disagreements rather than for a double click.
    @Test("re-stating a subject replaces rather than duplicates")
    func reStatingASubjectReplaces() {
        let box = SessionRuleBox()
        box.insert(Self.rule("com.apple.Music", .uncertain), forSession: Self.session, priorityID: Self.priority)
        box.insert(Self.rule("com.apple.Music", .unrelated), forSession: Self.session, priorityID: Self.priority)

        let rules = box.rules(forSession: Self.session, priorityID: Self.priority)
        #expect(rules.count == 1)
        #expect(rules.first?.verdict == .unrelated)
    }

    /// The same subject at a different *narrowness* is a different rule — `docs.google.com` as
    /// a domain and as a title token are two statements, and the specificity axis is what tells
    /// them apart.
    @Test("the same subject at a different narrowness is a different rule")
    func narrownessDistinguishesSubjects() {
        let box = SessionRuleBox()
        box.insert(Self.rule("proposal", kind: .titleToken), forSession: Self.session, priorityID: Self.priority)
        box.insert(Self.rule("proposal", kind: .domain), forSession: Self.session, priorityID: Self.priority)
        #expect(box.rules(forSession: Self.session, priorityID: Self.priority).count == 2)
    }

    /// The array a snapshot holds is `==` between two reads of the same box, which is what
    /// makes a replayed sequence exact.
    @Test("the returned order is the snapshot's total order")
    func theOrderIsTotal() {
        let box = SessionRuleBox()
        box.insert(Self.rule("com.apple.Music", kind: .app), forSession: Self.session, priorityID: Self.priority)
        box.insert(Self.rule("proposal", kind: .titleToken), forSession: Self.session, priorityID: Self.priority)
        box.insert(Self.rule("news.example", kind: .domain), forSession: Self.session, priorityID: Self.priority)

        let first = box.rules(forSession: Self.session, priorityID: Self.priority)
        let second = box.rules(forSession: Self.session, priorityID: Self.priority)
        #expect(first == second)
        #expect(first.map(\.subjectKind) == [.titleToken, .domain, .app])
    }

    @Test("clearAll forgets every session")
    func clearAllForgetsEverything() {
        let box = SessionRuleBox()
        box.insert(Self.rule("com.apple.Music"), forSession: Self.session, priorityID: Self.priority)
        box.insert(Self.rule("com.apple.TV"), forSession: Self.otherSession, priorityID: nil)
        box.clearAll()
        #expect(box.isEmpty)
    }
}
