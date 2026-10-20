# ContextSpike — does reading the window help the model judge?

A throwaway spike, outside `Packages/` and outside the gate. It asks whether the lane 2 model judge
("is this window part of the person's task?") gets better when it sees more of the window than the
app name: the title, the open file or web address, and the window's own text read through
Accessibility.

**R-116 and the zero-capture rules are set aside for this test only** (owner's ruling,
16 October 2026). This spike reads window titles, file paths, URLs and window text, and sends them
to Azure Foundry. Nothing here is shipped, and the app's rules are unchanged.

## Running it

```bash
cd Tools/ContextSpike && swift build
./stage.sh                                     # opens staged docs in Word, Excel, TextEdit, Xcode and Safari
.build/debug/ContextSpike capture              # Accessibility read of each window → $TMPDIR/focus-context-spike/captures.json
.build/debug/ContextSpike show w-bbc full      # what a judge is sent for one window at one level
CTX_BACKEND=local CTX_LEVEL=full CTX_VARIANT=production .build/debug/ContextSpike judge
CTX_BACKEND=chat DECISION_ENDPOINT=https://<resource>.services.ai.azure.com CTX_DEPLOYMENT=gpt56luna \
  CTX_LEVEL=meta .build/debug/ContextSpike judge
CTX_BACKEND=systemone DECISION_ENDPOINT=https://<resource>.services.ai.azure.com CTX_LEVEL=full \
  .build/debug/ContextSpike judge              # Microsoft-Decision-1, deployment "decision-1"
python3 summarise.py                           # one table across every report
./unstage.sh                                   # closes only what stage.sh opened, without saving
```

The capturing process must be trusted for Accessibility. Each level includes the levels before it:

| Level | The judge is sent |
|---|---|
| `app` | app name and bundle ID (today's production input) |
| `title` | + window title |
| `meta` | + web address or open file path |
| `full` | + focused element (only if it is in this window) and window text, content first, capped at `CTX_CHARS` (6,000) |

The corpus has 15 real windows and 11 tasks, giving 46 cases: 15 rescues and 31 holds. The holds
include decoys: an *Acme offsite* doc for the *Acme proposal* task, Crash Bandicoot on Wikipedia for
an iOS checkout crash, and Xcode open on this repo for the swift-format triage task. Each case is
asked three times. The bar, as in DecisionSpike, is **seduced = 0, no unstable cases, recall ≥ 0.75**.

## What Accessibility gives up, per app

| App | What comes back | Read time |
|---|---|---|
| Safari | the whole page: 8–62K characters from the `AXWebArea`, and the URL | 1.2–5.5 s (500–5,300 nodes) |
| Xcode | the whole source file as the editor's value (22K characters) | ~0.1 s |
| TextEdit | the whole document | <0.1 s |
| Excel | **only the formula bar** (the selected cell), name box and ribbon; cells are not exposed | ~0.1 s |
| Word | **no body text at all**; the page is an `AXLayoutArea` with no text children or text attributes, even with `AXEnhancedUserInterface` / `AXManualAccessibility` set | ~0.1 s |

Office documents therefore judge on title and file path, whatever the level. Safari exposes only
the selected tab's web area, so a window behind a different tab reads as that tab.

## Results (16 October 2026)

The best threshold per run is shown: the lowest seduced count, then the most rescued. Cost assumes
880K calls per month per 1,000 users at list price, with about 2 output tokens per call.

| Judge | app | title | meta | full | $/1k users/mo (meta → full) |
|---|---|---|---|---|---|
| on-device, production prompt | 7/15, 9 seduced | 11/15, 2 | 13/15, 4 | 13/15, 4 | $0 |
| on-device, neutral prompt | 11/15, 21 | 13/15, 5 | 15/15, 6 | 15/15, 7 | $0 |
| **Decision-1** (choice) | 1/15, 7 **u** | 8/15, 1 **u** | 15/15, 0 ✓ (t = 0.6 only) | **15/15, 0 ✓ (t = 0.5–0.8)** | **$16 → $46** |
| Decision-1 (yes/no) | 0/15, 2 **u** | 9/15, 0 **u** | 14/15, 0 **u** | 15/15, 0 ✓ | $16 → $46 |
| gpt-5.6-luna | 1/15, 0 | 14/15, 1 | **15/15, 0 ✓** | **15/15, 0 ✓** | $46 → $179 |
| gpt-4.1 | 8/15, 14 | 15/15, 2 | 15/15, 1 | **15/15, 0 ✓** | $455 → $1,788 |
| gpt-4.1-mini | 2/15, 4 | 14/15, 3 | 14/15, 1 | 15/15, 2 | $91 → $358 |
| Llama-3.3-70B | 15/15, 27 | 15/15, 4 | 15/15, 3 | 15/15, 1 | $172 → $651 |
| DeepSeek-V4-Flash | 8/15, 16 | 10/15, 2 | 15/15, 1 | 14/15, 2 | $42 → $173 |

**u** marks unstable cases at the best point. Decision-1 is asked a four-way `choice` and a
yes/no `noul` in the same request; both signals are swept from the same calls.

p50 latency: Decision-1 0.2 s at every level; on-device 0.55 s (app) to 1.0–1.3 s (full); Llama 0.25–0.3 s; DeepSeek 0.55 s;
gpt-5.6-luna 0.8–0.9 s; gpt-4.1 0.9–1.2 s. Full content costs about 1,000 input tokens per call,
against 170–250 for app to meta.

What it says:

- **Decision-1 is the best judge here.** With full window text it rescues all 15 and accepts
  no hold at any threshold, is stable from t = 0.5 to 0.8, answers in about 220 ms and costs
  about $46 per 1,000 users a month ($0.042 per million input tokens, output free). At `meta`
  it also meets the bar, but only at t = 0.6, so that point is fragile. On the earlier
  DecisionSpike corpus, which had only an app name or domain and normalised tokens, it reached
  recall 0.27–0.33. The difference is the context, not the model.

- **Context is what moves every model.** From the app name alone, nothing can tell the Acme proposal
  from the best man speech, because both are Word. Each model either declines everything
  (gpt-5.6-luna, gpt-4.1-mini) or accepts everything (Llama, DeepSeek).
- **The on-device model does not reach the bar at any level.** Window text gets the neutral prompt
  to 15/15 recall, but it still accepts six or seven holds: the Acme offsite doc for the Acme
  proposal (Word gives it only the title), the novel chapter for the best man speech, and the
  Foundation Models docs for the swift-format triage task. The production prompt is more
  conservative and holds at 13/15 recall with four seduced.
- **gpt-5.6-luna meets the bar at `meta`.** Title plus URL or file path is enough, at about a
  quarter of the full-content cost and without sending any window text. Window text adds nothing
  for it on this corpus.
- **gpt-4.1 needs the window text** to stop being seduced by the Xcode window for the iOS checkout
  task. It meets the bar at `full`, at about ten times luna's `meta` cost.
- The decoy most cloud models fall for is `t-resume/w-crashlog`, a TextEdit crash log open for a
  CV-rewriting task. gpt-4.1-mini and Llama accept it at every level.

## Caveats

- The documents and pages were staged by the spike, and the labels are the author's own judgement.
  Real windows are noisier: longer documents, several tabs, and half-read pages.
- 31 holds × 3 passes is a small sample, and zero seduced on it is weak evidence of zero seduced in
  use.
- Office content is missing (see above). A production design would have to use AppleScript or the
  screen for Word and Excel, each a separate grant.
- At `meta` and `full`, file paths, URLs and document text leave the Mac. That is a privacy change
  for the product, not a tuning choice; the owner made it opt-in on 2026-10-20 (README ▸ Privacy
  posture).
