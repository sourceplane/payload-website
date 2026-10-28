# payload-website

Vercel's [Payload Website Starter](https://github.com/payloadcms/payload/tree/main/templates/with-vercel-website)
— Payload CMS and the website it publishes, in one Next.js app: pages built
from layout blocks, posts with categories, search, redirects, forms, SEO,
drafts with live preview, scheduled publishing and Payload's admin panel —
running on **Cloudflare Workers + Static Assets** through
[`@opennextjs/cloudflare`](https://opennext.js.org/cloudflare), with the
content in a **Cloudflare D1** database and the media in an **R2** bucket,
both provisioned by Terraform through [Orun](https://github.com/sourceplane/orun)
and the schema applied by migrations, deployed by
[Orun](https://github.com/sourceplane/orun) to stage and prod on every merge.
Packaging it as an Orun baseline is the next milestone (PW2). The Cloudflare account
must be on **Workers Paid**: the Worker is about 4 MiB gzipped.

The port is the one Payload's own Cloudflare template makes — the D1 adapter
for Vercel Postgres, the R2 storage adapter for Vercel Blob — applied to the
website template, at Payload's release tag `v3.89.0`. Payload's generated
schema is migrations here, applied before the Worker deploys; the pages
render per request from D1 instead of being pre-rendered from a database
the build has not got; Vercel Cron is a Cron Trigger; the three secrets
Vercel asked for are generated in the database. See
[`specs/epics/payload-website`](specs/epics/payload-website/README.md) for the
design, the milestones and the as-built status.

## What is here (the product)

| Surface | Where |
|---|---|
| Payload's config: collections, globals, plugins, the D1 database, the R2 storage, the jobs | `apps/web/src/payload.config.ts`, `apps/web/src/collections`, `apps/web/src/Header`, `apps/web/src/Footer`, `apps/web/src/plugins` |
| The frontend and the admin | `apps/web/src/app/(frontend)`, `apps/web/src/app/(payload)` |
| The site's name, its generated secrets, the Cron Trigger | `apps/web/src/site.ts`, `apps/web/src/utilities/appSecrets.ts`, `apps/web/worker.ts` + `src/utilities/scheduled.ts` |
| Workers build, bindings and deploy contract | `apps/web/next.config.ts`, `open-next.config.ts`, `wrangler.template.jsonc` + `wiring.fixture.json` (→ the committed `wrangler.jsonc`), `component.yaml` |
| The D1 database and the R2 bucket (stage, prod) | `infra/terraform/cloudflare-d1`, `infra/terraform/cloudflare-r2` |
| The schema (migrations), their runner, the Payload-to-SQL converter | `packages/db`, run by `infra/db-migrate`; `tooling/migrations/payload-sql.mjs` |
| The wrangler renderer, the migration helpers | `tooling/wire`, `tooling/migrations` |
| Tests | `tests/web` (name, origin, secrets, Cron Trigger), `tests/db` (the migrations through the runner, into real SQLite) |

## Getting started

```bash
pnpm install
pnpm run wire:fixture   # render apps/web/wrangler.jsonc from the offline fixture
pnpm typecheck
pnpm lint
pnpm test
pnpm build              # next build (webpack) + next-sitemap + opennextjs-cloudflare build → apps/web/.open-next
```

```bash
pnpm --filter @app/web db:migrate:local   # the schema and the generated secrets in wrangler's local D1
pnpm --filter @app/web dev                # http://localhost:3000 — the local D1 and R2 through wrangler's platform proxy
pnpm --filter @app/web preview            # wrangler dev over the built Worker, same local D1 and R2
```

## How it maps to Vercel

| Vercel-side | Here |
|---|---|
| Next.js hosting (Payload's admin, its API and the site) | One Cloudflare Worker (`.open-next/worker.js`, wrapped by `worker.ts`) + Static Assets, built with webpack |
| Vercel Postgres (`@payloadcms/db-vercel-postgres`, `POSTGRES_URL`) | Cloudflare D1 (`@payloadcms/db-d1-sqlite`), the `D1` binding; its id is rendered into `wrangler.jsonc` per environment from the D1 root's wiring document |
| Vercel Blob (`@payloadcms/storage-vercel-blob`, `BLOB_READ_WRITE_TOKEN`) | Cloudflare R2 (`@payloadcms/storage-r2`), the `R2` binding; the bucket from the R2 root |
| `payload migrate` before `next build` (the `ci` script) | Payload's schema as `packages/db` migrations (`010_payload`), applied by `infra/db-migrate` before the Worker deploys; Payload runs with `push: false` |
| Pages pre-rendered at build (`generateStaticParams`, ISR every 600 s) | Rendered per request from D1 (`force-dynamic`): the build has no database |
| `PAYLOAD_SECRET`, `PREVIEW_SECRET`, `CRON_SECRET` set in the project | Generated once per database by `020_app_secrets`; a Worker secret of the same name wins |
| Vercel Cron (`vercel.json`: `/api/payload-jobs/run`, daily) | A Cron Trigger (`0 0 * * *`); `worker.ts`'s `scheduled` requests the same endpoint in process with the cron bearer |
| Image resizing with sharp, Vercel Image Optimization | Neither: Payload keeps the originals, `images.unoptimized` |
| `VERCEL_PROJECT_PRODUCTION_URL` | `NEXT_PUBLIC_SERVER_URL`, set per environment by the deploy (its `SITE_URL`, else its workers.dev URL) |
| A database and a blob store created in the dashboard | `infra/terraform/cloudflare-d1` and `cloudflare-r2`, applied by Orun before the migrations and the Worker |
| Deploy on push | Orun applies the database and the bucket, migrates, and deploys `<repo>-web-{stage,prod}` on merge to `main` |
| "Deploy with Vercel" (clone the template) | `orun new --blueprint repo-blueprint.yaml` — a new repository, branded, deployed |

## How the database and the bucket reach the Worker

```
infra/terraform/cloudflare-d1 ──apply──► orun secret WIRING_CLOUDFLARE_D1 (stage, prod)
infra/terraform/cloudflare-r2 ──apply──► orun secret WIRING_CLOUDFLARE_R2 (stage, prod)
                                               │
                                               ▼
infra/db-migrate  dependsOn cloudflare-d1 (enforced on main) · secretEnv WIRING_CLOUDFLARE_D1
  apply:  packages/db's runner → POST …/d1/database/<id>/query, each pending migration once
                                               ▼
apps/web  dependsOn cloudflare-d1 + cloudflare-r2 + db-migrate (enforced on main)
          · secretEnv WIRING_CLOUDFLARE_D1_<ENV>, WIRING_CLOUDFLARE_R2_<ENV>
  build:  tooling/wire/live.mjs → wrangler.jsonc with the environment's database id and bucket
          (dev, verify-only, renders the fixture) → next build → opennextjs-cloudflare
```

`wrangler.jsonc` is committed as the fixture render of
`wrangler.template.jsonc`, because the deploy lane's `verify-app-structure`
step checks the config exists before it builds; `testing/e2e.test.sh` fails
if the two disagree.

## CI

| Workflow | What it runs | Ships to a product |
|---|---|---|
| `ci.yml` | the Orun pipeline, and the only workflow a product carries: `orun plan --changed`, then one job per lane. A pull request runs the verify lanes (packages type-checked, linted, tested and built, both test suites, the site built and dry-deployed per environment), except the bootstrap's own landings (`orun/BASE-*`), where `plan` alone is the check; a merge applies the D1 database and the R2 bucket, migrates the database, then deploys stage → prod. It plans nothing while `intent.yaml` names the placeholder workspace `ws_CHANGE_ME`, as this repository does. A manual run (Orunbase's Deploy button, or Run workflow on `main`) plans the environment and components it names under the push-to-main trigger, so they deploy as a merge deploys them | yes |
