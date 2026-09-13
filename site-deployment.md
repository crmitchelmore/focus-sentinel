# Marketing site deployment

The static marketing site lives in `site/`. No build step is required. The intended
Cloudflare Pages project is `focus-sentinel`, with production branch `main` and
custom domain `focus-sentinel.win`.

Cloudflare account: `761de6a0aa83a8ad709981bd30d9b03f`. The first deployment was
uploaded from a local ZIP through the Cloudflare dashboard on 12 September 2026.
Chris prefers API credentials for future deployments; use an API token for local
CLI and CI deployment. Both GitHub Actions repository secrets are provisioned.

## Credential locations for agents

Verified 13 September 2026:

- Local file: `/Users/bravostation/work/focus/.env.cloudflare`, ignored by Git,
  permissions `0600`. Both `CLOUDFLARE_ACCOUNT_ID` and `CLOUDFLARE_API_TOKEN`
  are populated. This file is machine-local and is not included in checkouts.
- CI: GitHub repository `crmitchelmore/focus-sentinel` → Settings →
  Secrets and variables → Actions → repository secrets. Both names above were
  securely provisioned via standard input and verified in the secret listing.
- Token name: **Focus Sentinel Pages deployment**, created with Chris's explicit
  confirmation on 13 September 2026. Scope: Cloudflare Pages:Edit on account
  `761de6a0aa83a8ad709981bd30d9b03f`; no DNS permissions or expiry was configured.
  This account-level scope can edit Pages projects across that account.
  An authenticated read of the `focus-sentinel` Pages project succeeded.
- Previous deployments used a browser session. Do not extract browser cookies
  or use browser-session authentication for CI; use the saved API token.

Keep the local file outside `site/` and out of upload ZIPs. Never print its
contents, use shell tracing (`set -x`), put tokens on command lines, or copy
values into Git, Notion, PR descriptions or chat. Preserve permissions `0600`.
Use a scoped API token for this account with Cloudflare Pages edit permission;
routine site deploys do not need DNS edit or a global API key.

Wrangler can read the local credential file without sourcing
it as shell code:

```sh
npx --yes wrangler@4.129.1 pages deploy site --project-name=focus-sentinel --branch=main --env-file .env.cloudflare
```

Provision GitHub secrets using `gh secret set NAME` with each value passed via
standard input from a parser of this file, never `--body TOKEN`. Verify only
secret names with `gh secret list --repo crmitchelmore/focus-sentinel`, then
verify an actual deployment. GitHub does not return saved secret values.

## Automatic deployment

`.github/workflows/deploy-site.yml` deploys on pushes to `main` that change
`site/**`, `wrangler.toml` or that workflow. It also supports manual dispatch
from main. Jobs run serially on Ubuntu, check out current main when starting,
require both repository secrets, upload only `site/`, and compare the public
HTML and image with source over HTTPS. No macOS builds or UI tests run.

Authenticate locally with Wrangler or supply `CLOUDFLARE_API_TOKEN` and
`CLOUDFLARE_ACCOUNT_ID` through the environment. Never commit credentials.

Create the Pages project once, if it does not already exist:

```sh
npx --yes wrangler@4.129.1 pages project create focus-sentinel --production-branch=main
```

Deploy from the repository root:

```sh
npx --yes wrangler@4.129.1 pages deploy site --project-name=focus-sentinel --branch=main
```

Associate `focus-sentinel.win` with the project under Custom domains in Cloudflare
Pages, then create the DNS record Cloudflare requests. Adding DNS alone does not
associate the hostname with Pages. Verify HTTPS serves the page and
`/companion.png` after certificate activation.

CI uses the same deploy command with GitHub Actions secrets named
`CLOUDFLARE_API_TOKEN` and `CLOUDFLARE_ACCOUNT_ID`, matching Pasta and Just Speak To
It. GitHub cannot return existing secret values; provisioning requires the
original token or a new scoped token. Local Wrangler OAuth is not a CI token.

The original site came from commit `c4b6517` on `feat/release-trains` (PR #13).
Its GitHub source, release and security links require repository access while
the repository remains private.
