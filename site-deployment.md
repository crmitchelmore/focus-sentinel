# Marketing site deployment

The static marketing site lives in `site/`. No build step is required. It is served by
the Cloudflare Pages project `focus-sentinel` (account `761de6a0aa83a8ad709981bd30d9b03f`),
production branch `main`, custom domain `focus-sentinel.win`.

## How a change reaches production

Merging to `main` deploys. `.github/workflows/deploy-site.yml` runs on every push to
`main` that changes `site/**`, `wrangler.toml` or the workflow itself, and can also be
dispatched by hand from `main`. Changes on any other branch are not deployed until
they are merged.

The job runs serially on the existing `bravo-mini-local` macOS ARM64 runner, checks out
current `main` when it starts (so a queued run cannot roll the site back), requires both
repository secrets, uploads only `site/` with Wrangler, and then fetches the public HTML
and `companion.png` over HTTPS and compares them byte for byte with the source. No macOS
builds or UI tests run. GitHub-hosted runners were blocked by account billing limits on
13 September 2026, which is why the local runner is used.

To deploy from this Mac without waiting for CI, from the repository root:

```sh
npx --yes wrangler@4.129.1 pages deploy site --project-name=focus-sentinel --branch=main --env-file .env.cloudflare
```

## Credential locations for agents

Verified 13 September 2026:

- Local file: `/Users/bravostation/work/focus/.env.cloudflare`, ignored by Git,
  permissions `0600`. Both `CLOUDFLARE_ACCOUNT_ID` and `CLOUDFLARE_API_TOKEN` are
  populated. The file is machine-local and is not part of any checkout.
- CI: GitHub repository `crmitchelmore/focus-sentinel` → Settings → Secrets and
  variables → Actions → repository secrets `CLOUDFLARE_API_TOKEN` and
  `CLOUDFLARE_ACCOUNT_ID`, the same names Pasta and Just Speak to It use.
- Token name: **Focus Sentinel Pages deployment**, created with Chris's explicit
  confirmation on 13 September 2026. Scope: Cloudflare Pages:Edit on the account above;
  no DNS permission and no expiry. That scope can edit every Pages project in the account.

Keep the local file outside `site/`. Never print its contents, use shell tracing
(`set -x`), put the token on a command line, or copy values into Git, Notion, PR
descriptions or chat. Preserve permissions `0600`. Do not use browser-session
authentication or extracted cookies for deployment; use the saved token.

To rotate: create a new scoped token in Cloudflare, update `.env.cloudflare`, then
`gh secret set CLOUDFLARE_API_TOKEN --repo crmitchelmore/focus-sentinel` with the value
on standard input. GitHub cannot return a saved secret value, and Wrangler's local
OAuth login is not a CI credential.

## One-time setup, already done

Recorded for reference; none of this needs repeating.

- Pages project created: `npx --yes wrangler@4.129.1 pages project create focus-sentinel --production-branch=main`.
- `focus-sentinel.win` associated under Custom domains in Cloudflare Pages, with the
  apex CNAME to `focus-sentinel.pages.dev` created afterwards. Adding DNS alone does not
  associate a hostname with Pages.

## History

- 12 September 2026: first deployment uploaded as a ZIP through the Cloudflare dashboard.
  The site itself came from commit `c4b6517` on `feat/release-trains` (PR #13).
- 13 September 2026: API token created, secrets provisioned, a local token deployment
  verified (`https://faa85c64.focus-sentinel.pages.dev`), and the automatic workflow
  landed on `main`.

The site's GitHub source, release and security links require repository access while
the repository remains private.
