# Security

Focus Sentinel is a local-only macOS app. It keeps its data in
`~/Library/Application Support/com.chrismitchelmore.FocusSentinel` and connects to the
internet only for software updates, after the person enables automatic checks in
Settings, General or explicitly checks from Settings or the File menu. A manual check does
not enable automatic checks. The build gate proves the default-off updater boundary; see the README
sections "What it says it does not do" and "Release trains".

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
