# payload-website — operating contract (for humans and agents)

This is the standing guide to how this site is deployed and operated.
Instance facts (live URLs, workspace, the secrets it uses) live in
[deployment.md](deployment.md), rendered from probed reality by the
bootstrap's `02-docs` phase; this file is the contract that stays true
between deployments. It is written to give an agent with repository read
access enough context to reason about and operate the site without any
other source.

## What this system is

Payload CMS and the website it publishes, on Cloudflare alone, expressed as
an Orun component-native desired-state repo.

- **`infra/terraform/cloudflare-d1`** — one Cloudflare D1 database per
  deployed environment (`stage`, `prod`), applied by Terraform. After each
  apply it publishes a wiring document — `{d1_database_id, d1_database_name}`
  — as the Orun secret `WIRING_CLOUDFLARE_D1` on that environment.
- **`infra/terraform/cloudflare-r2`** — one R2 bucket per deployed
  environment, where Payload stores media uploads. After each apply it
  publishes `{r2_bucket_name}` as `WIRING_CLOUDFLARE_R2`.
- **`packages/db`** — the schema as migrations (`src/migrations/*/up.sql`,
  listed with their checksums in `src/manifest.ts`) and the runner that
  applies them to D1 over the REST API, recording each in a
  `_migrations_applied` table. `010_payload` is Payload's schema (every
  collection, global, version table and plugin table, as `payload
  migrate:create` generated it for the D1 adapter); `020_app_secrets`
  generates the site's three secrets once, in the database.
- **`infra/db-migrate`** — runs that runner per environment: it plans offline
  on a pull request and applies on a merge, finding the database through
  `WIRING_CLOUDFLARE_D1`.
- **`apps/web`** — the site: Payload 3 and its Next.js frontend, built by
  `@opennextjs/cloudflare` into one Worker plus Static Assets. `/admin` is
  Payload's admin panel, `/api` its REST and GraphQL APIs, and every other
  page renders per request from D1 through the `D1` binding (the D1
  adapter); media is in R2 through the `R2` binding (the R2 storage
  adapter). `worker.ts` adds the Cron Trigger that runs Payload's job queue
  (scheduled publishing) once a day. Payload never pushes schema changes
  itself (`push: false`): the migrations are the schema.
- **`tests/web`**, **`tests/db`** — the site's name, origin, generated
  secrets and Cron Trigger, and the migrations applied through the runner
  into real SQLite (vitest), verified on the `dev` rung.
- **`tooling/*`** — shared TypeScript and ESLint configuration, the wrangler
  renderer that turns `wrangler.template.jsonc` plus the wiring documents
  into `wrangler.jsonc`, and the migration helpers (the manifest's checksum
  check, the local-D1 apply, and `payload-sql.mjs`, which turns a Payload
  migration into a packages/db one).

Environments: **`stage`** and **`prod`** are deployed; **`dev` is
verify-only by design** — lanes build and test, nothing deploys, and no
database or bucket exists for it (its build renders the committed fixture).

The account must be on **Workers Paid**: the Worker is about 4 MiB gzipped,
over Workers Free's 3 MiB.

## Identity and tenancy

Every remote operation runs against ONE Orun workspace, declared in
`intent.yaml` under `execution.state.workspace` — committed, enforced, and
what CI uses. Do not remove it; headless credentials depend on it. If it
reads `ws_SET_ME`, the bootstrap had no workspace to write: set the real one
before anything else.

## How deployment works

1. Merge (or push) to `main`.
2. CI (`.github/workflows/ci.yml`) runs `orun plan --changed` — only
   components whose files changed are planned — then runs each planned lane
   with `orun run --remote-state`, authenticated by GitHub OIDC (the
   exchange resolves this repository's linked workspace server-side).
3. **The database and the bucket, then the schema, then the Worker**, per
   environment. `cloudflare-d1` and `cloudflare-r2` apply and publish their
   wiring documents. `db-migrate` declares an enforced `dependsOn` on
   `cloudflare-d1` for pushes to `main`, so it starts after that apply — a
   job resolves its secrets when it starts, so the document is there — and
   applies every pending migration. `apps/web` waits on all three the same
   way.
4. `apps/web` renders `wrangler.jsonc` from those documents (the real
   database id and bucket name), builds once per environment with
   `NEXT_PUBLIC_SERVER_URL` set to that environment's `SITE_URL`
   (intent.yaml) or its workers.dev URL, `wrangler deploy` ships
   `payload-website-web-<env>`, and a smoke test fetches `/`,
   `/api/users/me` (Payload answering from its migrated database) and
   `/admin`.
5. `prod` deploys after `stage` has converged on the same commit
   (`environments.prod.promotion` in intent.yaml).
6. **The convergence run is the deployment.** A green run means every
   planned lane applied. Failed lanes are retried with
   `gh run rerun --failed`, which resumes the same execution.

On a pull request nothing applies or deploys: the D1 and R2 roots plan, the
migrations plan offline (their checksums verified), the site builds and
dry-deploys, and the edges in step 3 are advisory.

Caveats that matter:

- A push that touches no component files plans zero lanes — that run is
  green and deployed nothing. Never treat "latest run green" as "site
  converged"; probe the URLs instead.
- A change to `intent.yaml`'s `environments` maps to no component and
  redeploys nothing on its own. Land it with a change under `apps/web`.
- `wrangler.jsonc` is generated. Edit `wrangler.template.jsonc`, run
  `pnpm run wire:fixture` and commit both; the deploy renders its own
  config from the template, so a stale committed render misleads local work.
- An applied migration is immutable: its checksum is recorded, and the
  runner refuses to run while a file no longer matches it. Change the
  schema with a NEW migration.
- Every page renders per request: nothing is cached at the edge, so a
  publish shows on the next request. Payload's publish hooks call
  `revalidatePath`, which has no cached page to refresh here.

## Secrets model

- **Brokered provider secrets**, minted per run from the workspace's
  Cloudflare connection — no long-lived values at rest, nothing to rotate by
  hand:
  - `CLOUDFLARE_API_TOKEN` (`workers-deploy`: Workers Scripts) — the site's
    deploy;
  - `CLOUDFLARE_D1_TOKEN` (`d1-edit`: D1) — the D1 root's apply and the
    migration runner, which bind it as their `CLOUDFLARE_API_TOKEN`; the
    deploy token cannot touch D1;
  - `CLOUDFLARE_R2_TOKEN` (`r2-data`: R2) — the R2 root's apply;
  - `CLOUDFLARE_ACCOUNT_ID` — a connection fact all of them bind.
- **Wiring**: `WIRING_CLOUDFLARE_D1` and `WIRING_CLOUDFLARE_R2` on `stage`
  and `prod`, written by the roots' applies (lease-published), read by the
  migration runner and by the Worker's build as `WIRING_CLOUDFLARE_*_<ENV>`.
  They hold ids and names, not credentials.
- **The site's own secrets** — Payload's signing key, the draft-preview
  token, the cron bearer — are generated once per database by the
  `020_app_secrets` migration (table `app_secrets`) and read by the Worker
  from D1. A Worker secret of the upper-case name (`PAYLOAD_SECRET`,
  `PREVIEW_SECRET`, `CRON_SECRET`, `wrangler secret put`) wins over the
  generated value. Rotating `payload` signs everyone out.
- Inspect by NAME only: `orun secrets list --org <ws> --project` and
  `--env stage|prod`. No tooling in this repository prints a secret value,
  and no document in `ai/context/` may contain one.

## Verifying the system

```bash
# the site on each environment (also recorded, probed, in deployment.md);
# Payload answers its REST API from D1
curl -s https://payload-website-web-stage.your-workers-subdomain.workers.dev/api/users/me
curl -s -o /dev/null -w '%{http_code}\n' https://payload-website-web-prod.your-workers-subdomain.workers.dev/admin

# the wiring the migrations and deploys read, and workspace readiness
orun secrets list --org <ws> --env stage && orun secrets list --org <ws> --env prod
orun integrations list --org <ws> --json && orun cloud check --org <ws>
```

## Common operations

| task | how |
|---|---|
| the first admin | open `/admin` on the environment and create the first user; then the dashboard's "Seed your database" fills the template's demo pages, posts and media |
| edit content | the admin, `/admin` — pages, posts, media, categories, the header and footer, forms, redirects |
| change the site's code | `apps/web/src/` (collections, blocks, heroes, the frontend), its name `apps/web/src/site.ts`; merge |
| change the schema (a collection or field) | `pnpm --filter @app/web payload migrate:create <name>` (against the local D1), `node tooling/migrations/payload-sql.mjs <the new file> packages/db/src/migrations/<NNN>_<name>/up.sql`, list it in `packages/db/src/manifest.ts`, `pnpm --filter @saas/db run manifest:fix`, `pnpm --filter @app/web generate:types`, merge — db-migrate applies it before the site redeploys |
| try the schema locally | `pnpm --filter @app/web db:migrate:local` applies every migration to wrangler's local D1 |
| run the job queue now | sign in to the admin and request `/api/payload-jobs/run`; the Cron Trigger runs it daily at 00:00 UTC |
| deploy a change | merge to `main`; watch the run; failed lanes → `gh run rerun --failed` |
| deploy by hand | Orunbase's Deploy button, or `gh workflow run ci.yml --ref main -f environment=<env> [-f component=<a,b>]` — the named components (blank: every one) run in that environment as a merge runs them; started off `main` it is refused |
| redeploy without a change | edit the last line of `apps/web/component.yaml` (`# orun: redeploy <reason> <stamp>`) and merge — it is a deploy trigger, nothing reads it |
| query a live database | `wrangler d1 execute <name> --remote --command "SELECT count(*) FROM pages"` (the name is in the environment's `WIRING_CLOUDFLARE_D1`) |
| set a secret yourself | `pnpm exec wrangler secret put PAYLOAD_SECRET --name payload-website-web-<env>` from `apps/web` (or `PREVIEW_SECRET`, `CRON_SECRET`) |
| add a binding (KV, another D1) | a Terraform root under `infra/terraform/` that publishes `WIRING_<ROOT>`, a token in `wrangler.template.jsonc`, its fixture entry, the root in the build's `--components`, the `WIRING_<ROOT>_<ENV>` secretEnv on each deployed environment's own `subscribe` entry (not the component's — a job resolves every secret it declares before it starts, and waits only on its own environment's applies) and an enforced `dependsOn` on it in `apps/web/component.yaml` |
| serve a custom domain | attach it to the Worker in Cloudflare and set `SITE_URL` for the environment in `intent.yaml` — the next deploy builds the site's links for it (README, "Custom domain") — then replace the placeholder `payload-website.example.com` in `intent.yaml`'s `BASE_DOMAIN` with it |
| headless credentials | `ORUN_TOKEN` (workspace-scoped) + `GITHUB_TOKEN` |

The deployment record is the bootstrap's `02-docs` phase. Re-running it (the
Orun console's Retry on that phase, or `orun new … --phase 02-docs`)
re-probes the URLs and re-renders [deployment.md](deployment.md); it is
idempotent.

## Evolution

D1 has no interactive transactions and caps a database's size (10 GB on
Workers Paid); Payload's D1 adapter is built for both. Structural changes
follow the same contract that deployed the site: add a component under
`apps/`, `infra/` or `packages/` with a `component.yaml`, land it as a pull
request, and the convergence run applies it.
