# Marketing site deployment

The static marketing site lives in `site/`. No build step is required. The intended
Cloudflare Pages project is `focus-sentinel`, with production branch `main` and
custom domain `focus-sentinel.win`.

Cloudflare account: `761de6a0aa83a8ad709981bd30d9b03f`. The first deployment was
uploaded from a local ZIP through the Cloudflare dashboard on 12 September 2026.
Chris prefers API credentials for future deployments; use an API token for local
CLI and CI deployment. CI credentials have not yet been provisioned.

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
