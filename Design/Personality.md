# Focus: a little signal, a steady bearing

Focus is an observant desk companion. Curious when it cannot tell, matter-of-fact when it can, quiet once the work is back on track. Its personality comes from a recognisable little lens, warm surfaces and a clear visual rhythm. It does not praise, scold or invent conversation.

Chris selected the Little Signal concept with elements of the Lookout on 9 September 2026 (focus-gl3x). The combination keeps the small white companion, deep Spruce, warm ivory, restrained ochre and a lighthouse detail. The approved new query heading is “A small question.” The underlying question, explanation, scope and three answers keep their existing approved wording.

## Visual language

- The companion and beacon introduce primary surfaces, including the General tab in Settings. Other Settings tabs retain their bounded scrolling content and share the palette. They are decoration, not an indicator of surveillance, certainty or urgency.
- Spruce identifies uncertainty. Kiln still identifies drift. Destructive actions retain the system meaning of red.
- Warm ivory grounds and quiet inset surfaces carry the light appearance. Dark and increased-contrast pairs remain explicit.
- System sans-serif carries every text role. The priority is the largest type; headings and controls remain subordinate.
- The illustration never contains live text. Headings are localised SwiftUI text; increased contrast and large text use a plain legible header.
- Embedded nudge rows share the containing popover’s identity rather than repeating the artwork. Their decisions retain the available space.
- No looping character animation, invented progress ring, reward ceremony or extra interruption. Reduced Motion changes no meaning.

## Sources and reproduction

`CompanionIcon.png` is the icon master. `scripts/make-appicon.sh` packages its macOS sizes. `Packages/FocusUI/Sources/FocusUI/Resources/Palette.xcassets/CompanionHeader.imageset/CompanionHeader.png` is the compact header illustration; `CompanionHeaderWide.imageset/CompanionHeaderWide.png` supplies the composition for wide windows; `CompanionHeader.swift` supplies the live title and accessibility treatment. Palette values and asset catalogues remain paired and checked. Generated artwork is committed locally and requires no network service at runtime.

The selected reference is the combined concept `exec-c41104ce-a40e-4a43-8871-d9f065917ca0.png` in Codex task Assess project status, 01a08142-1e4c-7b10-a7e6-1526bd668ab3. This direction updates the earlier instrument-only visual ruling, while preserving the rule that a question never accuses the person.

## Integrated native controls

The owner asked for the identity to reach beyond the header on 9 September (focus-ev07). The current priority now sits on a distinct Bench surface with a Spruce outline. Wide cockpit windows place timing/session controls alongside context/rules; narrow windows and larger text retain the sequential layout. The session duration has a larger, monospaced reading. Recent priorities use separated rows and familiar status symbols.

`CompanionControls.swift` centralises rounded native button styling, selected states, section markers and grouped surfaces. Controls retain SwiftUI Button semantics and existing actions. Spruce now also identifies chosen settings and primary controls on summoned surfaces, as part of the owner's broader identity direction; destructive actions retain system red. No animation or new personality copy is introduced.

General Settings uses grouped controls with explicit selection indicators instead of a columns Form, and its complete content is bounded like the other tabs. All settings tab introductions live inside their own scroll boundaries. First-run and completion surfaces use the same headings, controls and icon language. These are layout changes in the isolated design branch; no peer-owned working-tree edits were imported.

Visual validation of this refinement is pending explicit permission for the new UI batch. Build success is not visual approval.
