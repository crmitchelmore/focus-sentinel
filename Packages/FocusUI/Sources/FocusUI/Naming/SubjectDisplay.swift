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

    /// The name for one rule's subject, decided by the rule's own scope.
    static func name(
        of rule: PriorityRuleValue,
        installedName: InstalledNameLookup = InstalledApplication.name(bundleID:)
    ) -> String {
        switch rule.scope {
        case .app, .session:
            // `.app` is a bundle identifier by definition. `.session` says only how long the rule
            // lives, so its subject can be any of the three — and the shape check inside decides.
            name(of: rule.subject, resolvingApplication: true, installedName: installedName)
        case .domain, .titleToken:
            // An origin loses its scheme; a title token is already the word a person typed.
            // Neither is a question for LaunchServices.
            name(of: rule.subject, resolvingApplication: false, installedName: installedName)
        }
    }
}
