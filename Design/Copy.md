# Focus copy

The owner requested an app-wide plain-language edit on 9 September 2026 (focus-rlsf), using [Unslop from cursor/plugins](https://github.com/cursor/plugins/blob/main/pstack/skills/unslop/SKILL.md). Its current source was read in full for this pass. Use it as editorial guidance alongside Focus's behaviour and copy contracts.

## Voice

Focus is an observant companion: calm, direct and specific. Describe the known state, then the available action. Use familiar words, active sentences, sentence-case labels and straight quotes. Remove filler, vague reassurance and technical detail that does not help the person decide. Keep macOS names and established product terms intact. Never rewrite user-authored task names or notes.

Nudges describe the activity or ask a real question. They do not praise or blame the person, infer attention from a displayed panel, or claim knowledge the app lacks. The existing 56-line voice matrix forbids second-person tokens; accusation lines remain statements and app-membership queries remain questions. The approved heading "A small question." stays.

## This pass

Reviewed all 527 English strings across the App, Core and UI catalogues; revised 274. Labels, settings, first-run guidance, storage and privacy explanations, permission text, destructive confirmations, undo labels and all four nudge voices were included. Already-clear text was retained. Catalogue keys and ordered format arguments are unchanged.

Examples of the resulting wording:

- Empty priority: "What are you working on?"
- Optional completion notes: "You can leave both fields blank."
- Storage readiness: "Data file is open." This does not claim every change has been saved.
- Session allowance: "Allow for this session", matching the actual lifetime of the rule.
- Display history: "Displayed", without claiming the person saw the panel.
- Custom duration: "Minutes, 1 to 1,440".

Privacy wording follows the owner's posture of 20 October 2026: local first, nothing leaves the Mac unless the person switches it on, and opting in to Ask Decision-1 gives the remote judge everything the app knows. Each opt-in note says what it lets Focus see or send; none promises less than the switch allows. Destructive confirmations retain their scope, restart requirements and inability to undo. Revised catalogue comments distinguish this owner-requested edit from approval of the earlier wording.

The copy assertions and accessibility-driving scripts use the revised labels. Source checks preserve localisation coverage and format arguments. Native layout and accessibility validation remain subject to the owner's standing requirement to confirm each UI test batch.

## Tooltips (12 September 2026, focus-8ski)

Every control carries a tooltip from the catalog, drawn only through `View.shellHelp`. One sentence, six to fourteen words: for a session verb the verb first, then what it changes ("Pause session. The clock stops and nudges stay quiet until you resume."); for any other control what pressing changes; for a disabled control why it is off and what would enable it ("Type a priority first.", "This tuning is already at its highest allowed value."). Facts in tooltips were checked against the code they describe (daily update checks, one-minute away steps, half-hour quiet-hours steps, the once-a-day retention sweep). Nudge-panel tooltips follow the nudge rules: no praise, no blame, no claim about attention.
