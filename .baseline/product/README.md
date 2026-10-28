# payload-website

[Payload CMS](https://payloadcms.com/) and the website it publishes — pages
built from layout blocks, posts with categories, search, redirects, forms,
SEO, drafts with live preview and scheduled publishing, and Payload's admin
panel — as one Next.js app on **Cloudflare Workers + Static Assets** through
[`@opennextjs/cloudflare`](https://opennext.js.org/cloudflare). The content is
in a **Cloudflare D1** database and the media in an **R2** bucket, both
provisioned by Terraform per environment; the schema is applied by
migrations before every deploy. The account must be on **Workers Paid**: the
Worker is about 4 MiB gzipped, over Workers Free's 3 MiB.

## Live deployment

<!-- 02-docs:begin -->
Not recorded yet. The bootstrap's last phase writes the live URLs, the
workspace and the secrets the site uses into
[ai/context/deployment.md](ai/context/deployment.md); how the site deploys
and how to operate it is in
[ai/context/operations.md](ai/context/operations.md).
<!-- 02-docs:end -->

## First steps

1. Open `/admin` on the site and create the first user — the admin.
2. On the dashboard, **Seed your database** fills the template's demo: a home
   page, posts, categories, media (uploaded to R2), a contact form and the
   header and footer. Or start from nothing and add your own pages.

## What is here

| Surface | Where |
|---|---|
| Collections (pages, posts, media, categories, users), globals (header, footer), plugins | `apps/web/src/collections`, `apps/web/src/Header`, `apps/web/src/Footer`, `apps/web/src/plugins` |
| Layout blocks and heroes | `apps/web/src/blocks`, `apps/web/src/heros` |
| The frontend and the admin | `apps/web/src/app/(frontend)`, `apps/web/src/app/(payload)` |
| Payload's config: the D1 database, the R2 storage, the jobs | `apps/web/src/payload.config.ts` |
| The site's name | `apps/web/src/site.ts` |
| The site's generated secrets | `apps/web/src/utilities/appSecrets.ts` (read from D1) |
| The Worker's entry (OpenNext's handler, the Cron Trigger) | `apps/web/worker.ts`, `apps/web/src/utilities/scheduled.ts` |
| Workers build, bindings and deploy contract | `apps/web/next.config.ts`, `open-next.config.ts`, `wrangler.template.jsonc` + `wiring.fixture.json` (→ `wrangler.jsonc`), `component.yaml` |
| The D1 database and the R2 bucket (stage, prod) | `infra/terraform/cloudflare-d1`, `infra/terraform/cloudflare-r2` |
| The schema (migrations) and their runner | `packages/db`, applied by `infra/db-migrate` |
| Tests | `tests/web`, `tests/db` (vitest) |

## Getting started

```bash
pnpm install
pnpm run wire:fixture   # render apps/web/wrangler.jsonc from the offline fixture
pnpm typecheck
pnpm lint
pnpm test
pnpm build              # next build + next-sitemap + opennextjs-cloudflare build → apps/web/.open-next
```

```bash
pnpm --filter @app/web db:migrate:local   # Payload's schema and the generated secrets in wrangler's local D1
pnpm --filter @app/web dev                # http://localhost:3000 — the local D1 and R2 through wrangler's platform proxy
pnpm --filter @app/web preview            # wrangler dev over the built Worker, same local D1 and R2
```

## How the database and the bucket are wired

The Worker binds the database as `D1` and the bucket as `R2`. Neither is
hand-written: `apps/web/wrangler.template.jsonc` names them as wiring tokens,
and `wrangler.jsonc` is that template rendered — from `wiring.fixture.json`
(placeholders) for local work and verification, and on every deploy from the
documents the `cloudflare-d1` and `cloudflare-r2` Terraform roots publish
after their applies (`WIRING_CLOUDFLARE_D1`, `WIRING_CLOUDFLARE_R2`, per
environment). Edit the template, then `pnpm run wire:fixture` and commit the
render with the template.

The schema is `packages/db`'s migrations: each
`src/migrations/<NNN>_<name>/up.sql` is listed in `src/manifest.ts` with its
checksum, and the `db-migrate` component applies the pending ones to each
environment's database before the site deploys. Payload never changes the
schema itself. To change a collection: edit it, run
`pnpm --filter @app/web payload migrate:create <name>` (against the local D1),
turn the file it writes into a migration with
`node tooling/migrations/payload-sql.mjs <that file> packages/db/src/migrations/<NNN>_<name>/up.sql`,
list it in `src/manifest.ts` and run `pnpm --filter @saas/db run
manifest:fix`. Never edit an applied migration — its checksum is recorded.

## Secrets

Payload's signing key, the draft-preview token and the cron bearer are
generated once per database by the `020_app_secrets` migration and read by
the Worker from D1, so nothing is typed anywhere. To set one yourself, a
Worker secret of the upper-case name wins:
`pnpm exec wrangler secret put PAYLOAD_SECRET --name payload-website-web-<env>`
from `apps/web` (or `PREVIEW_SECRET`, `CRON_SECRET`).

## How it deploys

Merges to `main` converge through [Orun](https://github.com/sourceplane/orun):
`.github/workflows/ci.yml` plans the changed components and runs each lane
against the workspace in `intent.yaml`. Per environment, the D1 database and
the R2 bucket apply first, then the migrations, then the site builds with
that environment's database and bucket and deploys — to `stage`, then to
`prod` once stage has converged on the same commit; `dev` only verifies. The
Worker is `payload-website-web-<env>` on your account's workers.dev
subdomain, and every deploy is smoke-tested over HTTP: the home page, the
REST API answering from D1, and the admin. A pull request runs the same
pipeline's verify lanes: the packages type-checked, linted, tested and
built, both test suites, and the site built and dry-deployed for each
environment, with nothing deployed. (A push to `main` applies, migrates,
builds and deploys.) Payload's job queue (scheduled publishing) runs daily
from the Worker's Cron Trigger.

The pipeline holds one credential, GitHub's own `GITHUB_TOKEN`. The
Cloudflare tokens (one to deploy, one scoped to D1, one to R2) and the
account id are brokered per run from the workspace's Cloudflare connection,
and the database ids and bucket names travel as Orun secrets; nothing
provider-shaped is stored in the repository or in GitHub.

**Deploy by hand.** Orunbase's **Deploy** button on a component, or **Run
workflow** on the CI workflow in GitHub's Actions tab (on `main`), runs
`ci.yml` for the environment and components you pick, and each one deploys
exactly as a merge would deploy it. Leave the component blank to redeploy
every component in that environment, with nothing changed: after rotating a
secret, say. A component with nothing to run in that environment (a test
suite in `prod`) is left out with a notice.

## Custom domain

The site answers on workers.dev from its first deploy. To serve it on your
own domain:

1. Add the domain to the Cloudflare account the site deploys into, and attach
   it to the Worker (dashboard → Workers & Pages →
   `payload-website-web-prod` → Settings → Domains & Routes → Add →
   Custom domain).
2. Set the environment's public origin in `intent.yaml`, so the next deploy
   builds the site's links for it — CORS, the sitemaps, canonical and Open
   Graph links and the admin's preview links (until then they use the
   workers.dev URL):

   ```yaml
   environments:
     prod:
       env:
         SITE_URL: https://payload-website.example.com
   ```

   The site was born with the reserved placeholder
   `payload-website.example.com` where its domain goes: that example, and
   `BASE_DOMAIN` under each environment in `intent.yaml`. Replace it with
   your domain in the same change, and land it with a change under
   `apps/web` so the merge rebuilds the site.

## Credits

The site is Payload's website template
([payloadcms/payload](https://github.com/payloadcms/payload), `templates/with-vercel-website`,
MIT — `apps/web/LICENSE.md`).
