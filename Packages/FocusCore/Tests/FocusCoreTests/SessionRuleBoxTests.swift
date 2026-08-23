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

    /// A session holds rules for **one** priority at a time, and writing under a new one is
    /// itself the declaration that the old one is gone. Without that, the box would accumulate a
    /// rule per priority the session ever held and any one of them could resurface.
    @Test("a session holds rules for at most one priority at a time")
    func aSessionHoldsOnePriorityAtATime() {
        let box = SessionRuleBox()
        box.insert(Self.rule("com.apple.Music"), forSession: Self.session, priorityID: Self.priority)
        box.insert(Self.rule("com.apple.TV"), forSession: Self.session, priorityID: Self.otherPriority)

        #expect(box.count == 1)
        #expect(box.rules(forSession: Self.session, priorityID: Self.priority).isEmpty)
        #expect(box.rules(forSession: Self.session, priorityID: Self.otherPriority)
                    .map(\.subject) == ["com.apple.TV"])

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

    /// The first half of the lifetime contract: a rule written under one priority says nothing
    /// about another, so it is never *read* under one. A plain lookup is a lookup and nothing
    /// else — the destruction is `setActivePriority`'s job, which is what keeps this readable by
    /// an inspector that wants to ask a question without changing the answer.
    @Test("a rule written under one priority is invisible under another")
    func aPriorityChangeHidesTheRule() {
        let box = SessionRuleBox()
        box.insert(Self.rule("com.apple.Music"), forSession: Self.session, priorityID: Self.priority)

        #expect(box.rules(forSession: Self.session, priorityID: Self.otherPriority).isEmpty)
        #expect(box.rules(forSession: Self.session, priorityID: nil).isEmpty)
        #expect(box.rules(forSession: Self.session, priorityID: Self.priority).count == 1)
    }

    /// **Hiding is not dying, and A → B → A is the difference.**
    ///
    /// The regression this test exists for: an earlier shape keyed the storage on the priority
    /// and stopped there, so a rule written under *A* was merely *invisible* while *B* was
    /// active — and came back the moment the person switched to *A* again. A session rule is the
    /// one-click *"not now"*; it answers a question that was being asked at the time, and a
    /// question somebody left and came back to is a new question. The rule must be destroyed by
    /// the change, not shelved by it.
    ///
    /// The sequence below is exactly the one the host performs: `SessionHost.sessionRules`
    /// declares the priority before reading, on the only path the box is read from, and the
    /// snapshot is rebuilt on precisely the events that change it (R-65, R-72.2).
    @Test("a rule written under one priority cannot come back when that priority does")
    func aPriorityChangeDestroysTheRule() {
        let box = SessionRuleBox()

        box.setActivePriority(Self.priority, forSession: Self.session)
        box.insert(Self.rule("com.apple.Music"), forSession: Self.session, priorityID: Self.priority)
        #expect(box.rules(forSession: Self.session, priorityID: Self.priority).count == 1)

        // The person switches to another priority. The rule dies here.
        #expect(box.setActivePriority(Self.otherPriority, forSession: Self.session))
        #expect(box.rules(forSession: Self.session, priorityID: Self.otherPriority).isEmpty)
        #expect(box.isEmpty)
        #expect(box.count == 0)

        // …and switching back does not resurrect it.
        #expect(box.setActivePriority(Self.priority, forSession: Self.session))
        #expect(box.rules(forSession: Self.session, priorityID: Self.priority).isEmpty)
        #expect(box.count == 0)
    }

    /// Clearing to `nil` is *"there is no priority now"* rather than *"do not check"*. A person
    /// who completes their one thing has left the question the rule answered just as surely as
    /// one who replaced it.
    @Test("clearing the priority altogether also destroys the rule")
    func losingThePriorityDestroysTheRule() {
        let box = SessionRuleBox()
        box.insert(Self.rule("com.apple.Music"), forSession: Self.session, priorityID: Self.priority)

        #expect(box.setActivePriority(nil, forSession: Self.session))
        #expect(box.count == 0)
        #expect(box.rules(forSession: Self.session, priorityID: Self.priority).isEmpty)
    }

    /// The read path calls this on **every** lookup, so it has to be free when nothing moved.
    @Test("re-declaring the same priority changes nothing")
    func redeclaringThePriorityIsIdempotent() {
        let box = SessionRuleBox()
        box.insert(Self.rule("com.apple.Music"), forSession: Self.session, priorityID: Self.priority)

        for _ in 0..<3 {
            #expect(!box.setActivePriority(Self.priority, forSession: Self.session))
        }
        #expect(box.rules(forSession: Self.session, priorityID: Self.priority).count == 1)
    }

    /// One session's priority change is not another's. Two sessions cannot exist at once in this
    /// app, but a box that conflated them would be one restoration away from proving it.
    @Test("a priority change in one session leaves another session alone")
    func priorityChangesAreScopedToTheirSession() {
        let box = SessionRuleBox()
        box.insert(Self.rule("com.apple.Music"), forSession: Self.session, priorityID: Self.priority)
        box.insert(Self.rule("com.apple.TV"), forSession: Self.otherSession, priorityID: Self.priority)

        box.setActivePriority(Self.otherPriority, forSession: Self.session)
        #expect(box.rules(forSession: Self.otherSession, priorityID: Self.priority).count == 1)
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
