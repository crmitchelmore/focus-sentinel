# Launch copy

Written for launch day. **Do not post anything until all of these are true:**

* a notarised build is downloadable (issue #12);
* the repository is public, with a LICENSE file, if the post mentions source or MIT;
* the price is decided.

Placeholders are in `[BRACKETS]`. Every claim matches `claims-audit.md`. Character counts for
the limited fields were measured and are shown in brackets after each one.

---

## Show HN

**Title** (77 chars):

> Show HN: Focus Sentinel – a local-only Mac app that asks before it nudges you

**Body:**

> I kept losing afternoons to "just checking something" in a browser. Blockers didn't help,
> because my work lives in the same apps as my distractions. So I built a Mac app that keeps one
> priority in view and asks, rather than accuses, when the app in front drifts from it.
>
> How it works:
>
> - You write today's priority as one sentence, with an optional "Done when" line.
> - Focus compares the app in front with that priority and the context you attached (keywords,
>   sites, files), plus any rules you have written.
> - If it is unsure, it asks: "Is Numbers part of Draft the grant budget?" Your answer becomes a
>   rule, and it never asks about that app again for that priority.
> - If you drift, the menu-bar mark changes first. A small panel appears only if the drift lasts,
>   and it offers a way back. It never blocks or closes anything.
>
> Some engineering choices HN might care about:
>
> - The judgement is deterministic. A missing match can never, on its own, produce "unrelated":
>   Focus only calls something off task when you have told it what on task looks like. Otherwise
>   it asks or stays quiet.
> - It reads the active app's identity and nothing else. No window titles, URLs, screenshots or
>   keystrokes. This version does not read which site a browser is showing.
> - It never connects to the internet: no account, no telemetry, no updater, no network
>   entitlement, zero third-party dependencies. A 27-stage build gate checks the shipped binary
>   for networking symbols on every run.
> - It asks macOS for no permissions unless you switch the ask on. It stays quiet on calls (a live
>   microphone), in full screen, when you are away, in quiet hours, and after a daily limit.
> - There are no scores or streaks. History is a ledger of what the app did and why, and you can
>   tell it "you should have spoken" after the fact.
>
> macOS 26 or later. [PRICE]. Source: [REPO LINK] (MIT). Download: [LINK]
>
> I would especially like to hear where it stays quiet when you wanted it to speak.

---

## Product Hunt

**Tagline** (53 chars):

> One priority, kept in view. Asks instead of accusing.

**Description** (206 chars):

> A local-only Mac companion. Write today's priority in one sentence. Focus notices which app is
> in front, asks when unsure, and remembers your answer. It blocks nothing, keeps no score and
> never goes online.

**Maker's first comment:**

> Hi Product Hunt, I'm Chris.
>
> Focus Sentinel started because blockers didn't fit my work. The browser I research in is the
> browser I wander off in. So instead of a wall, I wanted a quiet colleague that knows the one
> thing I said I'd do today and asks a plain question when it can't tell.
>
> A few things it deliberately does not do:
> • It never connects to the internet, needs no account, and asks for no permissions unless you
>   switch that on.
> • It reads which app is active, never window titles, web addresses or what you type.
> • It keeps no score, no streaks and no "productive hours".
> • It never blocks, hides or closes anything.
>
> What it does do: it keeps your priority and timer in the menu bar, asks once about apps it
> can't place, nudges only after a sustained drift, and stays quiet on calls, in full screen,
> when you're away and in your quiet hours.
>
> It's for macOS 26 and later. [PRICE]. I'd love to know which of its silences you'd want
> louder, and which nudges you'd want quieter.

---

## X / Bluesky thread (7 posts)

1. Focus Sentinel is out for the Mac. It keeps one priority in view and asks, rather than
   accuses, when the app in front drifts from it. [LINK]
2. You write today's priority as one sentence. "Draft the grant budget. Done when every line has
   a number." It sits in the menu bar with your timer.
3. When Focus can't tell whether an app is part of the work, it asks: "Is Numbers part of Draft
   the grant budget?" Your answer becomes a rule. It won't ask again.
4. Drift for a while and the menu-bar mark changes. Drift longer and a small panel names the app
   and offers a way back. Nothing is blocked or closed.
5. It stays quiet on calls (a live microphone), in full screen, when you're away, in quiet hours,
   and after a daily limit. "Interrupt me less" keeps everything in the menu bar.
6. It never connects to the internet. No account, no telemetry, no updater. It reads which app is
   active, never window titles, URLs or keystrokes. Export or delete everything.
7. No score, no streaks. Just a plain record of what it did and why. macOS 26+. [PRICE] [LINK]

---

## LinkedIn

> I've released Focus Sentinel, a small Mac app for people whose work and distractions live in
> the same apps.
>
> Blockers assume you can list what to avoid. Most knowledge work isn't like that: the browser,
> the chat app and the editor are all both. So Focus does something gentler. You write the one
> priority for today. It notices which app is in front, and when it can't tell whether that app
> is part of the work, it asks you, once. Your answer becomes a rule you can read.
>
> It nudges only after a sustained drift, stays quiet on calls and during presentations, and
> keeps no score: no streaks, no productivity percentage.
>
> It is also local-only. It never connects to the internet, needs no account, asks for no
> permissions by default, and lets you export or delete everything.
>
> macOS 26 or later. [PRICE]. [LINK]

---

## r/macapps

**Title:** [Release] Focus Sentinel: a local-only menu-bar companion that keeps one priority in
view and asks before it nudges (macOS 26)

> Hi r/macapps. I'm the developer.
>
> **What it is:** a menu-bar app plus a small window. You set one priority as a sentence, with an
> optional "Done when" and an optional timebox. Focus watches which app is in front and compares
> it with the priority, your context (keywords, sites, files) and your rules.
>
> **What happens when you drift:** first the menu-bar mark changes. If the drift continues, a
> small non-activating panel (it doesn't steal focus) names the app and offers "Back to …",
> "Part of this task", snooze or dismiss. If it isn't sure, it asks a yes/no question instead,
> and remembers the answer.
>
> **What it won't do:** block, hide or close anything; connect to the internet; read window
> titles, URLs or keystrokes; ask for permissions unless you switch the ask on; score you.
>
> **Details people here ask about:**
> - Global quick-capture shortcut (default ⌃⌥⌘Space, changeable)
> - Shortcuts actions: Set Focus priority, Start Focus session, Finish Focus session
> - Quiet hours, silence on a live mic or in full screen, a daily interruption limit (8 by
>   default), and "Interrupt me less" to keep it all in the menu bar
> - Leaves password managers, banking, health and private-messaging apps alone
> - Retention of 7, 30 or 90 days, or forever; export activity and settings separately; delete
>   everything
> - Light and dark, Increase Contrast, Reduce Motion, larger text, VoiceOver labels
>
> **Price:** [PRICE]. **Requires:** macOS 26 or later. **Link:** [LINK]
>
> Happy to answer anything. Criticism of the nudge timing is especially welcome.

Before posting, check the Shortcuts actions run on the notarised build (`claims-audit.md`, O2).

---

## Newsletter / email announcement

**Subject:** Focus Sentinel is ready

> Hello,
>
> Focus Sentinel, my calm companion for the Mac, is ready to download.
>
> Write the one thing you mean to do today. Focus keeps it in the menu bar, notices which app is
> in front, and asks a small question when it can't tell whether that app is part of the work.
> If you drift for a while, it offers a way back. It never blocks anything and never keeps score.
>
> Everything stays on your Mac. Focus never connects to the internet, needs no account, and asks
> for no permissions unless you switch the ask on.
>
> It needs macOS 26 or later. [PRICE]. Download: [LINK]
>
> If it stays quiet when you wanted a nudge, or nudges when you wanted quiet, reply and tell me.
>
> Chris

---

## Mac App Store-style listing

**The current build cannot go to the Mac App Store as it is.** App Sandbox is off in
`App/FocusSentinel.entitlements`, and the store requires it. Use this text for directories and
download pages until that changes.

**Name:** Focus Sentinel

**Subtitle** (27 chars):

> One priority, kept in view.

**Keywords** (97 chars):

> focus,priority,distraction,timebox,menu bar,nudge,privacy,local,timer,session,attention,deep work

**Description:**

> Focus Sentinel keeps one priority in view and asks, rather than accuses, when the app in front
> drifts from it.
>
> WRITE ONE PRIORITY
> Write today's priority as one sentence and add "Done when" so you know what finished means. If
> the sentence has no verb or no outcome, Focus suggests a rewrite. Your wording always wins.
>
> A QUESTION, NOT A VERDICT
> Focus compares the app in front with your priority, the context you attach and the rules you
> write. When it cannot tell, it asks: "Is Numbers part of Draft the grant budget?" Your answer
> becomes a rule, and it does not ask again.
>
> A WAY BACK, NOT A WALL
> Drift for a while and the menu-bar mark changes. Drift longer and a small panel names the app
> and offers a way back. Focus never blocks, hides or closes anything, and a timebox never stops
> you working.
>
> QUIET WHEN IT SHOULD BE
> • A daily limit on interruptions
> • Silence while a microphone is in use, while an app is full screen, while you are away, and in
>   quiet hours you set
> • "Interrupt me less" keeps nudges and questions in the menu bar
> • Leaves password managers, banking, health and private-messaging apps alone
>
> SESSIONS AND TIMEBOXES
> Start a session that is open-ended, a fixed length, or finished by a time of day. Pause, take a
> break, or log a detour. The timer lives in the menu bar.
>
> YOUR DATA STAYS ON THIS MAC
> No account, no sync, no usage reports. Focus never connects to the internet. It reads which app
> is active, never window titles, web addresses, file names or what you type. It asks macOS for
> no permissions unless you switch the ask on. Choose how long records are kept, export your
> activity and settings, or delete everything.
>
> ALSO
> • Global quick-capture shortcut
> • Shortcuts actions to set a priority and start or finish a session
> • History: what Focus did today and why, with a way to say "you should have spoken"
> • Light and dark, Increase Contrast, Reduce Transparency, Reduce Motion, larger text
>
> Requires macOS 26 or later.

---

## Alternative taglines

1. Asks instead of accusing.
2. The one thing, in view. Nothing else.
3. A quiet colleague for your priority.
