# Liquid Glass in Focus Sentinel

The owner's verdict on the first two glass passes (16 October 2026): the glass made the
writing illegible. The worst case was the cockpit's selected tab, where teal text sat on a
teal-tinted glass pill. That verdict replaces the earlier approach. This document is the rule
for every screen. The code that enforces it is `Design/LiquidGlass.swift`.

## Sources

- Apple HIG, *Materials*: Liquid Glass is "a distinct functional layer for controls and
  navigation… Don't use Liquid Glass in the content layer… Use Liquid Glass effects
  sparingly." Use the regular variant "when components have a significant amount of text."
- Apple, *Adopting Liquid Glass*: prefer system components, which adopt glass automatically.
  Reduce custom backgrounds in bars and controls. Don't layer glass on glass. "Be judicious
  with your use of color in controls and navigation so they stay legible."
- Dimillian's `swiftui-liquid-glass` skill and conorluddy's *LiquidGlassReference*: glass is
  for the floating navigation layer and never for content. Tint carries meaning, not
  decoration. Keep text at 4.5:1 contrast or better. Group glass shapes in one
  `GlassEffectContainer`.

## The strategy: three layers, with glass only at the top

| Layer | What lives there | Material |
|---|---|---|
| **Ground** | the window behind everything | solid: Inlay in Light, Bench in Dark |
| **Content** | cards, rows, lists, fields, chips, badges, every sentence | **opaque**: an elevated pane (Bench in Light, Inlay in Dark) and a neutral inset wash for fields and chips |
| **Function** | navigation and floating chrome: the window, popover and sheet chrome, the cockpit's tab switcher, and a summoned floating panel | **Liquid Glass**, `.regular` and untinted |

1. **Text never sits on tinted glass.** A label on glass is primary or secondary ink on
   untinted regular glass. A selected state is an opaque thumb with primary ink. It is never
   a hue on a wash of the same hue.
2. **Content is opaque.** There are no translucent cards, no ambient blooms behind words, and
   no glass chips inside cards. Cards separate from the ground by elevation: in Light a
   lighter pane with a soft lift, in Dark a lighter pane with no shadow.
3. **Buttons inside content are solid, not glass.**
   - A primary action is a solid Spruce capsule with Bench ink (contrast above 5:1 in both
     schemes).
   - A secondary action is a neutral ink wash with primary ink.
   - A selected option is the primary fill.
   - Hover deepens the fill and never relies on shimmer alone.
4. **Glass is used once per surface, where it means navigation.** The cockpit has exactly one
   custom glass element, the tab switcher's track. The system draws the rest: the window
   chrome, the Settings toolbar, the menu-bar popover and sheets.
5. **A floating panel is regular glass, never clear.** A panel the person summoned over other
   apps draws regular (frosted) glass, which Apple specifies for surfaces carrying significant
   text. It is untinted, and its words are primary ink.
6. **Uninvited surfaces stay opaque.** Nudge panels never draw glass. The new button style is
   glass-free, so it is safe to use there.
7. **Accessibility collapses glass to solid.** Under Reduce Transparency and Increase Contrast,
   `drawsGlass` is false. The tab track becomes an opaque pane with a hairline, and Increase
   Contrast puts firm two-point edges on controls.

## Screen by screen

| Screen | Ground | Content | Glass |
|---|---|---|---|
| Cockpit: Now and History | solid ground | opaque cards; solid buttons and timebox options; neutral chips and badges | the tab switcher track only |
| Settings: General, Nudges, Privacy | solid ground | opaque cards; solid option buttons | system toolbar tabs |
| Menu-bar popover | system popover glass | opaque status pane; solid buttons | system |
| Sheets: Context, Completion, Handoff, Walkthrough intro | system sheet | opaque fields and buttons | system |
| Quick capture and walkthrough panels | opaque Bench | solid buttons | none (the panels are small text surfaces) |
| Nudge panels | opaque | solid buttons | regular glass only when summoned |
