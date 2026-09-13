# Marketing site deployment

The static marketing site lives in `site/`. No build step is required. The intended
Cloudflare Pages project is `focus-sentinel`, with production branch `main` and
custom domain `focus-sentinel.win`.

Cloudflare account: `761de6a0aa83a8ad709981bd30d9b03f`. The first deployment was
uploaded from a local ZIP through the Cloudflare dashboard on 12 September 2026.
Chris prefers API credentials for future deployments; use an API token for local
CLI and CI deployment. CI credentials have not yet been provisioned.

## Credential locations for agents

Verified 13 September 2026:

- Local file: `/Users/bravostation/work/focus/.env.cloudflare`, ignored by Git,
  permissions `0600`. It contains `CLOUDFLARE_ACCOUNT_ID`; the
  `CLOUDFLARE_API_TOKEN` field is **empty**, not a usable credential.
- CI destination: GitHub repository `crmitchelmore/focus-sentinel` → Settings →
  Secrets and variables → Actions → repository secrets. Required names are
  `CLOUDFLARE_API_TOKEN` and `CLOUDFLARE_ACCOUNT_ID`. Neither repository secret
  was present at verification. Do not assume Pasta/JSTI secrets are shared.
  Subsequent attempts to save the account-ID secret returned GitHub HTTP 502
  and 500, and the follow-up listing returned 500. Its final presence is
  unverified; recheck before provisioning. No API token was submitted.
- Deployments so far use the signed-in Codex in-app browser session. It is not
  an API token, cannot authenticate CI, and must not be extracted into a file.

Keep the local file outside `site/` and out of upload ZIPs. Never print its
contents, use shell tracing (`set -x`), put tokens on command lines, or copy
values into Git, Notion, PR descriptions or chat. Preserve permissions `0600`.
Use a scoped API token for this account with Cloudflare Pages edit permission;
routine site deploys do not need DNS edit or a global API key.

After a token is supplied locally, Wrangler can read the file without sourcing
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
The workflow cannot deploy until its API token is provisioned. Track that
remaining setup in `focus-g7ju`.
The workflow is currently on `codex/marketing-cloudflare`; it must be merged
to main after credentials are provisioned for automatic pushes to take effect.

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

Future CI can use the same deploy command with GitHub Actions secrets named
`CLOUDFLARE_API_TOKEN` and `CLOUDFLARE_ACCOUNT_ID`, matching Pasta and Just Speak To
It. GitHub cannot return existing secret values; provisioning requires the
original token or a new scoped token. Local Wrangler OAuth is not a CI token.

The original site came from commit `c4b6517` on `feat/release-trains` (PR #13).
Its GitHub source, release and security links require repository access while
the repository remains private.
