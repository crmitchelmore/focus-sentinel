import FocusCore
import Foundation

/// **What a stored subject is called on screen** (focus-7zr).
///
/// ## The walk this closes
///
/// The panel asks *"Is Figma part of Write the Q3 proposal?"*. The person clicks *"Yes, add it"*.
/// `QueryLedger` writes a rule keyed on `com.figma.Desktop`, because a rule keyed on a display
/// name is not a rule. And then the rules list in the same window drew a row reading
/// `com.figma.Desktop`. The panel said the name; the click it invited wrote a row the window
/// rendered as the key — with the context chips beside it, in the same window, saying *"Safari"*
/// and *"docs.example.com"* about exactly the same kinds of thing.
///
/// ## The policy is `NudgeSubject`'s, not a second one
///
/// `NudgeSubject.named(_:runningName:)` already decides all of it: an origin's display half is
/// derived through `ContextItemValue.displayName(forOrigin:)`, an application's is the name
/// something looked up, whitespace is not a name, and the identifier is the last resort. What it
/// cannot do is *look anything up* — it lives in `FocusCore`, which holds no AppKit
/// (`check-boundaries.sh`, R-96k). So this supplies the half that needs the world and delegates
/// the half that does not. There is deliberately no rule here that `NudgeSubject` does not
/// already state.
///
/// ## Which subjects are asked about, and which are not
///
/// A lookup is not free of consequence, so it is not made speculatively. A keyword is a word the
/// person typed and no bundle could improve it; an origin belongs to no application at all, so a
/// lookup could only ever return a browser's name for a site. Both are refused by shape — the
/// same discriminator `NudgeSubject.isOrigin(_:)` uses — and by scope where the scope knows
/// better. That is what makes the `PriorityRuleScope` switch below exhaustive rather than
/// defaulted: a fifth scope has to say which of the two it is.
@MainActor
enum SubjectDisplay {
    /// How an application identifier becomes a name. Injectable so the unit lane can prove which
    /// subjects reach the workspace — and, more to the point, which never do.
    typealias InstalledNameLookup = (String) -> String?

    /// The name for a subject the caller knows the kind of.
    ///
    /// - Parameters:
    ///   - subject: the stored key, exactly as it is filed. Never modified here; this returns a
    ///     second string and the caller keeps the first.
    ///   - resolvingApplication: whether an application name is worth asking for. `false` is not
    ///     a performance hint — it is the statement that this subject is not an application, and
    ///     the lookup is then not made at all.
    static func name(
        of subject: String,
        resolvingApplication: Bool,
        installedName: InstalledNameLookup = InstalledApplication.name(bundleID:)
    ) -> String {
        // An origin is refused by shape even when the caller said `true`, because a `.session`
        // rule is scoped by how long it lasts and says nothing about what it is about.
        let resolved = resolvingApplication && !NudgeSubject.isOrigin(subject)
            ? installedName(subject)
            : nil
        // Total: `named` answers `nil` only for an unnameable key, and a row exists to draw
        // something, so the key itself is the last thing left to draw.
        return NudgeSubject.named(subject, runningName: resolved)?.displayName ?? subject
    }

    /// **Whether a rule of this scope has a subject a bundle could name.**
    ///
    /// A function rather than a `switch` inside the call below, and the reason is R-70n. The
    /// `.session` scope is the shipped-but-ambiguous shape — a persisted row with
    /// `scopeRaw == "session"` says nothing about whether its subject is a bundle identifier, an
    /// origin or a title token, which is why e04 skips such rows and `check-forbidden.sh` bans
    /// reviving them. The cockpit's own `PriorityRuleValue` can still carry one and the rules
    /// list still draws it, so this has to answer for it — but nothing should have to *plant*
    /// one to prove the answer is total. Split out, the policy is checkable over
    /// `PriorityRuleScope.allCases` with no rule constructed at all.
    ///
    /// Exhaustive on purpose: a fifth scope has to say which of the two it is.
    static func resolvesApplication(_ scope: PriorityRuleScope) -> Bool {
        switch scope {
        // A bundle identifier by definition.
        case .app: true
        // Any of the three. `name(of:resolvingApplication:)` refuses origins by shape, which is
        // the most a scope naming no kind can honestly ask for.
        case .session: true
        // An origin loses its scheme; a title token is already the word the person typed.
        // Neither is a question for LaunchServices.
        case .domain, .titleToken: false
        }
    }

    /// The name for one rule's subject, decided by the rule's own scope.
    static func name(
        of rule: PriorityRuleValue,
        installedName: InstalledNameLookup = InstalledApplication.name(bundleID:)
    ) -> String {
        name(
            of: rule.subject,
            resolvingApplication: resolvesApplication(rule.scope),
            installedName: installedName
        )
    }
}
