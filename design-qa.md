# Focus personality: design verification

Source visual truth: `Design/Reference.png` (1487 × 1058 concept board). Owner selection: Little Signal with Lookout elements, 9 September 2026, focus-gl3x. This is a native macOS implementation, not a web prototype.

Implementation evidence: `Packages/FocusUI/Tests/FocusUITests/__Snapshots__/queryPanel.neutral.light.standard.png`, `menuBarPopover.question.light.standard.png`, `cockpitWithPriority.light.standard.png`, and `companionHeader.width{248,336,448,720,1200}.light.standard.png` in that directory. All are Xcode-rendered SwiftUI at 2× density. The popup is 380 points wide; popover is 300 points. Header-width tests name the complete proposed render width, including the harness padding. Native cockpit and Settings were also inspected through Computer Use with a separate fixture store; screenshots and accessibility trees are in source task Assess project status (01a08142-1e4c-7b10-a7e6-1526bd668ab3; share URL unavailable).

## Comparison and findings

The source board and rendered popup, populated cockpit, and wide header crops were opened together in the same comparison input. The board includes window chrome, different task wording and a simplified session; those are not pixel-equivalent states. Comparison therefore evaluates the illustrated header, question/action hierarchy and material palette, rather than asserting a whole-screen pixel match. Native controls and the existing complete cockpit workflow remain functional.

- Typography: system sans-serif throughout; the priority remains the largest semantic role. Localised live headings have clear separation from the companion. The question and supporting copy grow, wrap and stack their actions at large text. No text is baked into the artwork.
- Spacing: room around the popup question and three equal actions; embedded questions keep compact actions. Header layout reserves the character area. Five native widths cover the narrow popover through a wide window.
- Colour: warm ivory Bench and Inlay, deep teal artwork, Spruce question action, existing Kiln drift semantics. Increased Contrast replaces artwork with the explicit Slate/Bench pair; dark variants retain their own grounds.
- Imagery: generated bitmap companion, lighthouse and matching packaged app icon. Compact and wide compositions preserve the whole companion; no drawn substitute, live network dependency or animation.
- Copy: the sole new nudge sentence, “A small question.”, was explicitly approved. Existing task question, explanation, scope and actions are unchanged. Main-window app name stays Focus Sentinel rather than adopting the mock’s abbreviated label.

## Repair history

1. Missing catalogue image: the initial raw resource did not resolve under native asset lookup. Moved the illustration into an asset catalogue and added a runtime lookup regression. Subsequent captures show the artwork.
2. Repeated embedded headers crowded decisions: keep the companion on the enclosing popover, with compact embedded nudge actions. Layout and decision-reachability checks passed.
3. Narrow and wide image crop: fixed-width header assumptions clipped the companion. Added a wide composition and proportional header height; post-fix captures at 248, 336, 448, 720 and 1200 points preserve it. A real wide cockpit window was inspected again and confirms the repair.
4. Settings toolbar overlap: a header outside TabView exceeded the existing long-pane ceiling. Moved the Settings introduction into General. Native General-to-Privacy navigation was inspected again; Privacy starts below its toolbar and retains scrolling.

## Scope and residual limits

The release base’s General form still clips some existing labels. Another agent owns that Settings work (focus-exdi), and the owner explicitly asked to leave it alone. Its uncommitted changes were not copied. This report passes the new identity changes, not that separate pre-existing Settings defect. Existing ImageRenderer placeholders for AppKit-backed controls are not screenshots of their native appearance; the live cockpit verified those controls separately. No deployment or installed-app replacement is claimed.

No actionable P0/P1/P2 finding remains in this change’s identity scope. The full UI comparison and source checks are recorded in the PR validation evidence; recording passes alone do not count as comparison proof.

final result: passed
