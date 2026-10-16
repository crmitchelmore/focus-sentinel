# Decision-1 spike (evaluation only)

Runs Microsoft-Decision-1 (MAI "System 1", Azure AI Foundry) as a lane 2 judge through
`ModelEvaluationHarness`, against the same 45-cell model corpus and quality bar as the
on-device tier. It lives outside `Packages/`, is never linked into the app, and sends only
what a `ModelRequest` carries (normalised priority tokens and a bundle ID or domain) unless
`DECISION_STATE=intent` is set.

## Run

```bash
az login
swift build --package-path Tools/DecisionSpike
DECISION_ENDPOINT=https://<account>.services.ai.azure.com \
  Tools/DecisionSpike/.build/debug/DecisionSpike
```

| Variable | Meaning |
|---|---|
| `DECISION_ENDPOINT` | Foundry account endpoint (required) |
| `DECISION_DEPLOYMENT` | deployment name, default `decision-1` |
| `DECISION_VARIANT` | `method` (mirrors the on-device prompt) or `neutral` |
| `DECISION_STATE` | `tokens` (production shape) or `intent` (diagnostic) |
| `DECISION_RPM` | client pacing, default 55 |
| `AZURE_ENTRA_TOKEN` | optional; otherwise `az account get-access-token` |
| `DECISION_BACKEND` | `systemone` (Decision-1, default) or `chat` (any Foundry chat deployment) |

The `chat` backend asks one question with four lettered answers (A direct, B supporting,
C unrelated, D too vague) through `openai/v1/chat/completions`. It scores the answer with
P(A)+P(B) from the first token's logprobs. Models without usable logprobs (Phi-4,
Mistral-Large-3, grok-4.3) are scored on the sampled letter alone. Deployments whose names
start with `gpt5` are sent `reasoning_effort: none`.

The decision-1 report is written to `$TMPDIR/focus-decision-spike/report-<variant>-<state>.json`.
Chat reports are written to `report-<deployment>-<variant>-<state>.json` in the same folder.

## Azure notes

- Deployment names may not contain "microsoft" (`ContainsReservedWord`).
- DataZoneStandard capacity is requests per minute; capacity 1 is one call a minute.
- Local auth is disabled by policy: grant the caller **Foundry User** on the account and
  allow up to ten minutes for the role to propagate.
- Decision-1 is not deterministic: identical requests can return very different
  probabilities, so the harness's three passes matter.
- **Serverless capacity.** Capacity 1 means 1 request per minute. Raising capacity after
  deployment took more than ten minutes to reach the gateway, so deploy at the final capacity.
- **Long throttled runs.** A run throttled for an hour outlives its Entra token and fails
  with 401.
- **gpt-5.x.** These deployments return logprobs only with `reasoning_effort: none`, and they
  sample at temperature 1.
- **grok-4.3** spends about 500 hidden reasoning tokens per one-letter answer.

## Results (12 September 2026)

The bar is seduced 0, recall ≥ 0.75 and no unstable cells. No configuration earned it. The
best clean point, with seduced 0 and unstable 0, was recall 0.27 (`method`, tokens) or
0.33 (`neutral`, tokens or intent). By comparison, the on-device model had seduced 15 and
recall 0.733. Decision-1 does not get seduced, but it rejects most of the "supporting tool"
rescues, such as a spreadsheet or Figma for a proposal. Latency was p50 about 170 ms and
p95 about 210 ms.

## Chat models (13 October 2026, `neutral` wording)

Rows are ordered by cost. Each cell gives the best point of the threshold sweep as rescued/15
with the number seduced, and **u** marks a point with unstable cells. "tokens" is the shape
production can send. "intent" sends the person's sentence, which `ModelRequest` cannot carry
today. Cost is the estimated monthly cost per 1,000 users, assuming about 184 input tokens
per call and 40 lane 2 calls per user per working day.

| Model | tokens | intent | p50 | Cost |
|---|---|---|---|---|
| Phi-4 | 11, seduced 6 | — | 352 ms | $21 |
| DeepSeek-V4-Flash | 10, seduced 2 **u** | 12, seduced 1 **u** | 462 ms | $32 |
| gpt-5.6-luna | 6, seduced 1 | 11, seduced 1 | 649 ms | $37 |
| gpt-5.4-nano | 4, seduced 0 **u** | — | 625 ms | $37 |
| gpt-4.1-mini | 10, seduced 4 | **13, seduced 2** | 539 ms | $68 |
| Llama-3.3-70B | **11, seduced 1** | 12, seduced 1 | **188 ms** | $116 |
| gpt-5.4-mini | 9, seduced 3 **u** | — | 587 ms | $137 |
| gpt-4.1 | 9, seduced 1 | 9, seduced 1 | 1216 ms | $338 |
| gpt-5.6-terra | 9, seduced 1 | 12, seduced 1 | 787 ms | $366 |
| gpt-5.4 | 10, seduced 1 **u** | 9, seduced 1 | 945 ms | $458 |
| gpt-5.6-sol | 10, seduced 1 | 10, seduced 1 | 737 ms | $718 |
| gpt-5.5 | 11, seduced 1 | 10, seduced 1 | 735 ms | $915 |
| grok-4.3 | 9, seduced 3 **u** | 10, seduced 3 **u** | 4195 ms | ~$1,080 |
| Phi-4-mini | ignores the format, times out | — | — | — |
| Mistral-Large-3 | 14, seduced 13 **u** | 14, seduced 9 **u** | 333 ms | — |
| DeepSeek-V4-Pro | 2, seduced 0 | 2, seduced 0 | 1030 ms | — |

No model earned the bar.

- **One cell seduces nearly every model.** It is `mg-p6s1`, Excel for "catalogue the family
  films". That cell is a deliberate trap: its note relies on a film-library app being open in
  the same grid, which the request never carries.
- **Some misses are corpus questions rather than model errors.**
  - `mg-p3s1` (Excel for a support crash, rescue) contradicts `ml-l2s1` (the same task in
    German, hold).
  - `mg-p6s6` (Blender for a film night, rescue) and `mg-p5s2` (Figma for a blog review) are
    generous "supporting" calls that most models decline.
- **Bigger is not better here.** gpt-5.5 and gpt-5.6-sol cost 8–13 times as much as
  gpt-4.1-mini or Llama-3.3 and score no higher.
- **The two serious candidates:**
  - Llama-3.3-70B on tokens: recall 0.73, one seduction, stable, 188 ms.
  - gpt-4.1-mini with the intent sentence: recall 0.87, two seductions, both on the film row.

## Window titles (16 October 2026)

This experiment asks what Accessibility-read context would be worth.
`DECISION_TITLES=aligned|generic|decoy` adds a `Window title:` line from `titles.json`, which
`titles.py` generates. `DECISION_TITLE_RULE=strict` adds a prompt rule that a shared word is
not evidence. The task is always sent as normalised tokens (the production shape).

- **aligned:** the title each cell's own note describes. A hold shows the unrelated thing the
  app is doing.
- **generic:** default titles ("Book1", "Steam") that say nothing.
- **decoy:** rescues keep their aligned title. Holds get titles that share words with the task
  but are other work, such as "Plex – Crash (2004)" for a checkout crash.

Each cell gives the best point as rescued/15 with the number seduced. **u** marks a point with
unstable cells, and **✓** marks a point that meets the bar.

| Model | no title | generic | aligned | decoy | aligned, strict | decoy, strict |
|---|---|---|---|---|---|---|
| Llama-3.3-70B | 11, 1 | 11, 2 | **15, 0 ✓** | 15, 11 | 13, 2 | 13, 15 |
| gpt-4.1-mini | 10, 4 | 10, 2 | 15, 4 | 15, 12 | **14, 0 ✓** | 14, 5 |
| gpt-4.1 | 9, 1 | 6, 1 | **14, 0 ✓** | 14, 6 **u** | **12, 0 ✓** | 12, 0 **u** |
| gpt-5.6-luna | 6, 1 | 6, 1 | **15, 0 ✓** | 13, 5 | **15, 0 ✓** | 13, 4 |
| DeepSeek-V4-Flash | 10, 2 **u** | 5, 0 | **12, 0 ✓** | 10, 1 **u** | — | — |

- **A title that shows the work is decisive.** Every model meets the bar on aligned titles,
  including the film-night trap and the contested labels.
- **A title that says nothing neither helps nor harms.** Generic titles leave results close
  to no title at all.
- **Word overlap is the new failure mode.** Every model is seduced by decoys. The strict
  rule fixes this for gpt-4.1 only: 12/15 with 0 seduced on both sets. Its one unstable cell
  is `ml-l3s3` ("IndieGameKit — Review.swift" in Xcode for writing a game review), the most
  debatable decoy. For Llama the rule made things worse.
- **Titles add tokens.** They add about 40 input tokens per call, and the strict rule about
  110. At about 295 input tokens per call, the cost per 1,000 users a month is about $533 for
  gpt-4.1, $107 for gpt-4.1-mini and $56 for gpt-5.6-luna.
- **Caveats:**
  - These titles are hand-written; the aligned set carries its label by construction.
  - Real titles are messier (browser tabs, "Untitled", notification text).
  - The next evidence needed is a corpus of real titles captured on a real machine.
  - A title is captured prose that `ModelRequest` cannot carry (R-116); sending one anywhere,
    let alone to a cloud model, needs a ruling.
