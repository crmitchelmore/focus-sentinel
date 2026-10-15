# Marketing

The launch kit for Focus Sentinel. Everything here is checked against the source, and
`claims-audit.md` is the reference. If a claim is not there, do not make it.

| file | what it is for |
|---|---|
| [`claims-audit.md`](claims-audit.md) | Each product claim on `site/index.html`, checked against the code, with a verdict, the evidence file and line, and a correction. It also lists true features the site leaves out, and the launch risks. **Read this first.** |
| [`positioning.md`](positioning.md) | The pitch at one line, 25 words and 50 words; audiences and their pains; how Focus differs from each category; objections; messaging pillars; words to use and avoid |
| [`launch-copy.md`](launch-copy.md) | Show HN, Product Hunt, an X/Bluesky thread, LinkedIn, r/macapps, a newsletter, a Mac App Store-style listing, and alternative taglines |
| [`press-kit.md`](press-kit.md) | Fact sheet, boilerplate, founder-quote placeholder, asset list and screenshot shot list |

## Before anything is published

1. Fix the wrong claims on the site (`claims-audit.md`, section 1). The most important: there are
   no update checks and no guided tour, and the away threshold defaults to three minutes.
2. Add a LICENSE file and make the repository public, or drop every "open source", "MIT" and
   "read the source" line.
3. Ship the notarised build (issue #12), then check the Shortcuts actions on it.
4. Set the price, and replace every `[PLACEHOLDER]` and `[LINK]`.

Last checked: 1 October 2026, against `main` at `9319f3b`.
