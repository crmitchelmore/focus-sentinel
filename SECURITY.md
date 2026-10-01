# Security

Focus Sentinel is a local-only macOS app. It keeps its data in
`~/Library/Application Support/com.chrismitchelmore.FocusSentinel` and connects to the
internet only to check for an update, only after the person has switched that on in
Settings, General. The build gate proves both claims on the shipped binary; see the README
sections "What it says it does not do" and "Release trains".

## Reporting a vulnerability

Open a private security advisory on GitHub
(https://github.com/crmitchelmore/focus-sentinel/security/advisories/new) or email
chrismitchelmore@gmail.com. Say which build you saw it in: the version, build number and
commit are on the About panel and in Settings, General.

## What is and is not in this repository

- No signing material. The Sparkle EdDSA private key and the Developer ID identity live in
  the login keychain of the Mac that cuts releases. Only the public key is committed.
- No accounts, no analytics, no telemetry. The workflows use the repository's own
  `GITHUB_TOKEN` and nothing else.
- The self-hosted runner accepts jobs only from the repository owner's actors
  (`.github/runner/runner-policy.py`), and no workflow runs on pull requests from forks.
