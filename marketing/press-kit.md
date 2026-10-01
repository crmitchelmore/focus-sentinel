# Press kit

Every claim matches `claims-audit.md`. Any line marked **TBD** or **[PLACEHOLDER]** must be
filled in before this goes out.

## Fact sheet

| | |
|---|---|
| **Name** | Focus Sentinel. Shorten to "Focus" only after the first mention, and never write "Focus Mode". |
| **What it is** | A local-only Mac companion that keeps one priority in view and asks, rather than accuses, when the app in front drifts from it |
| **Developer** | Chris Mitchelmore (independent) |
| **Platform** | macOS (menu-bar app with a small window) |
| **Requirements** | macOS 26 or later. Tested on Apple silicon. |
| **Version** | 0.1.0 (pre-release) |
| **Price** | **TBD** |
| **Licence** | MIT, planned. **The LICENSE file is not in the repository yet, and the repository is private.** Do not say "open source" until both are fixed. |
| **Status** | Not yet released. Release tracker: GitHub issue #12. A Developer ID signed, notarised build is still to come. |
| **Category** | Productivity |
| **Language** | English (British spelling) |
| **Network** | None. No account, sync, telemetry or updater, and no network entitlement. |
| **Permissions** | None by default. Accessibility and Screen Recording can be switched on in Privacy settings, but nothing in this version uses them. |
| **Data** | One local file in `~/Library/Application Support/com.chrismitchelmore.FocusSentinel/`. You choose how long it is kept (7, 30 or 90 days, or forever), and you can export or delete all of it. |
| **Third-party code** | None. Zero package dependencies. |
| **Website** | https://focus-sentinel.win/ |
| **Source** | https://github.com/crmitchelmore/focus-sentinel (**private until launch**) |
| **Contact** | [PLACEHOLDER: press email] |
| **Elsewhere** | https://github.com/crmitchelmore · https://mitchelmore.uk/ |

### Key facts, in one breath each

* **One priority**, written as a sentence, with an optional "Done when" line and timebox.
* **Asks instead of accusing.** When it cannot tell whether an app belongs to the work, it asks
  once, and the answer becomes a rule you can read.
* **Nudges only after a sustained drift.** The menu-bar mark changes first, and a small panel
  follows. It never blocks, hides or closes anything.
* **Quiet when it should be.** A daily limit (8 interruptions by default), silence on a live
  microphone, in full screen, when you are away and in quiet hours, and "Interrupt me less".
* **Leaves private apps alone.** Password managers, banking, health and private-messaging apps
  are never judged.
* **No score, no streaks.** History records what the app did and why.
* **Shortcuts actions** to set a priority and start or finish a session. Check these on the
  notarised build.

## Boilerplate

**Short (about 50 words)**

> Focus Sentinel is a local-only companion for the Mac. Write today's priority as one sentence,
> and Focus keeps it in view, notices which app is in front, and asks a plain question when it
> cannot tell. It blocks nothing, keeps no score, asks for no permissions by default and never
> connects to the internet.

**Long (about 110 words)**

> Focus Sentinel is a calm companion for the Mac, made by independent developer Chris
> Mitchelmore. You write the one priority for today. Focus keeps it in the menu bar with your
> timer and compares the app in front with it. When it cannot tell whether an app is part of the
> work, it asks, and remembers your answer as a rule you can read. A nudge comes only after a
> sustained drift. It offers a way back and never blocks anything. Focus stays quiet on calls, in
> full screen, when you are away and in quiet hours. It keeps no score, reads no window titles,
> web addresses or keystrokes, and never connects to the internet. It requires macOS 26.

## Founder quote

> **[PLACEHOLDER: QUOTE FROM CHRIS. NOT APPROVED. DO NOT PUBLISH.]**
>
> Suggested direction, for Chris to rewrite in his own words: why blockers did not fit work that
> lives in the same apps as its distractions, and why the app asks instead of accusing.

## Assets

| file | status | notes |
|---|---|---|
| `site/companion.png` | exists | The companion: a small white lens with a yellow lamp on a stalk. Used for the site icon and og:image. |
| `site/og.png` | **to be added** | 1200 × 630 social card: the name, the line "One priority, kept in view.", and the companion |
| App icon | exists in `App/Assets.xcassets` | Export at 1024 px for press |
| Screenshots | **to be captured** | See the shot list below |
| Short screen recording (≤ 30 s) | **to be captured** | Set a priority with quick capture, drift to another app, get a question, answer it |

## Screenshot shot list

Capture from the real app on the notarised candidate. Use a clean demo store and a neutral
wallpaper, in light mode, with dark-mode versions of shots 1 and 4. Use realistic, harmless
priorities, such as "Draft the grant budget" (done when "Every line has a number"), and no
personal data.

**Before capturing:** the repository's `CLAUDE.md` requires Chris's explicit confirmation before
any automated UI drive. That includes `scripts/live-*-drive.sh` and snapshot lanes. Ask first,
or capture by hand.

| # | shot | what must be visible | notes |
|---|---|---|---|
| 1 | **Cockpit, Now tab** | Priority sentence, Done when, timebox counting down, session controls | The hero shot |
| 2 | **Quick capture panel** over another app | The "Suggested wording" strip with Use this and Keep my words | Shows the rewrite suggestion |
| 3 | **Question panel** | "Is Numbers part of Draft the grant budget?" with Yes, add it / No, it isn't / Ask later | Standard voice |
| 4 | **Menu-bar popover** | Priority, timer, a pending question, session buttons | Crop to the top right of the screen |
| 5 | **Nudge panel** | "[app] has been active for [time]" and "Back to [app]" | Describes, never scolds |
| 6 | **Cockpit, Details tab** | Context section with keyword, site and file chips; "Rules for this priority" with an app rule | Avoid showing a dragged app chip until the drag bug is fixed (`claims-audit.md`, W8) |
| 7 | **History window** | Rows for a question, a nudge and a "No nudge" interval, with "This was a distraction" | No totals anywhere, which is the point |
| 8 | **Privacy settings, top** | "Your data stays on this Mac…", "Focus never connects to the internet.", data file path and Show in Finder, retention choices | The trust shot |
| 9 | **Privacy settings, permissions** | Capability table "Available on this Mac", and both permission switches **off** with their notes | — |
| 10 | **Nudges settings** | Today's limits, quiet hours, Interrupt me less, where nudges appear | — |
| 11 | **Timings and thresholds** | A few dials with "Shipped:" values | For power users |
| 12 | **First-run sheet** | "What Focus Sentinel watches" | Replaces the tour the site wrongly mentions |
| 13 | **Shortcuts app** | The three Focus Sentinel actions | Only if they run on the notarised build |
| 14 | **Notch hairline** | A thin line under the notch | **Hold** until it is verified on MacBook hardware (issue #7) |
