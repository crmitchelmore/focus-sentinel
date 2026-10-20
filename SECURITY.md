# Security

Focus Sentinel is a local-first macOS app. It keeps its data in
`~/Library/Application Support/com.chrismitchelmore.FocusSentinel`, and by default nothing
leaves the Mac. It connects to the internet only for what the person switches on:

- **software updates**, after the person enables automatic checks in Settings, General or
  explicitly checks from Settings or the File menu. A manual check does not enable automatic
  checks;
- **the remote judge** (*Ask Decision-1* in Settings, Privacy), which sends context to
  Microsoft's Decision-1 model on Azure, authenticated with the person's own signed-in Azure
  CLI token. Under the owner's opt-in posture (2026-10-20) a person who switches it on gives the
  judge access to everything the app knows: priorities and their context, the frontmost
  window's title, selected item, address, file and visible text, busy times and tasks. Nothing
  is sent from password managers or private windows, and the app stores nothing it sends.

The build gate proves the default-off updater boundary and confines all networking to the
updater and one remote-judge file; see the README sections "What it says it does not do",
"Privacy posture" and "Release trains".

## Reporting a vulnerability

Open a private security advisory on GitHub
(https://github.com/crmitchelmore/focus-sentinel/security/advisories/new) or email
chrismitchelmore@gmail.com. Say which build you saw it in: the version, build number and
commit are on the About panel and in Settings, General.

## What is and is not in this repository

- No signing material. The Sparkle EdDSA private key and the Developer ID identity live in
  the login keychain of the Mac that cuts releases. Only the public key is committed.
- No app accounts, no analytics, no telemetry. Release workflows use the repository's
  `GITHUB_TOKEN` and the runner's signing keychain, or optional encrypted Apple signing
  secrets imported temporarily for the job. The marketing-site workflow uses encrypted
  Cloudflare deployment secrets. None of these credentials are bundled in the app.
- The self-hosted runner accepts jobs only from the repository owner's actors
  (`.github/runner/runner-policy.py`), and no workflow runs on pull requests from forks.
