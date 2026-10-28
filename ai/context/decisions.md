# payload-website — decisions

The choices that shape this repository, one line each, with where the full
reasoning lives. Superseded decisions stay listed, marked, so the history
reads in order.

| # | Decision | Why | Source |
|---|---|---|---|
| 1 | The template at Payload's release tag `v3.89.0`, every `@payloadcms/*` package at 3.89.0, Next.js 16.3.3 | `main`'s template is mid-change (it imports an API no release exports); the tag's template is consistent, and Next 16.3 is what OpenNext 1.20 runs | `specs/epics/payload-website/design.md` |
| 2 | D1 (`@payloadcms/db-d1-sqlite`) for Vercel Postgres, R2 (`@payloadcms/storage-r2`) for Vercel Blob, as Payload's own Cloudflare template does | Both are bindings: no connection string, no storage key | design.md |
| 3 | The schema is `packages/db`'s migrations — Payload's generated DDL, made idempotent — applied by db-migrate over the D1 API; Payload runs with `push: false` and never migrates | One place for the schema and one ledger of what each database has, applied before the Worker that reads it (turso-starter's shape) | risk PW-D |
| 4 | The site's secrets (Payload's signing key, the preview token, the cron bearer) are generated in D1 by a migration; a Worker secret of the same name wins | A site comes up with nothing typed; the brokered secrets are provider credentials, and these are not | risk PW-E |
| 5 | Every page renders per request (`force-dynamic`, no `generateStaticParams`); `next build` reads no data and starts no platform proxy | Vercel's build ran `payload migrate` first and pre-rendered from Postgres; this build has no database, and seven page-data workers would lock a local one | IMPLEMENTATION-STATUS (departures) |
| 6 | `next build --webpack`, `output: 'standalone'` | Turbopack hashes the name of an external package (`drizzle-kit/api`), which OpenNext's bundler cannot resolve | risk PW-F |
| 7 | No sharp: Payload keeps originals (no resized variants, no focal-point crops); `images.unoptimized` | Workers have no native sharp and no image optimiser | risk PW-C |
| 8 | Vercel Cron → a Cron Trigger: `worker.ts` adds `scheduled`, which requests `/api/payload-jobs/run` in process with the cron bearer | cron-starter's custom-worker shape; the template's own endpoint runs on schedule, unchanged | `apps/web/src/utilities/scheduled.ts` |
| 9 | `NEXT_PUBLIC_SERVER_URL` per environment: its `SITE_URL`, else its workers.dev URL | CORS, the sitemaps and the admin's preview links are absolute; each environment builds anyway | `apps/web/component.yaml` |
| 10 | Four brokered keys in one reconcile: `workers-deploy`, `d1-edit`, `r2-data`, the account id | The deploy token can touch neither D1 nor R2 | `repo-blueprint.yaml` |
| 11 | The registry row stays unlisted until a live build on Workers Paid | The Worker is about 4 MiB gzipped; Workers Free refuses it | risk PW-B |
| 12 | One landing (`01-product`) then the record (`02-docs`), each checked in the build box | turso-starter's shape: the plan carries the order (database and bucket, then schema, then Worker) | `docs/phases/README.md` |
| 13 | `ci.yml` plans nothing while `intent.yaml` names `ws_CHANGE_ME`; no Checks workflow; stack-tectonic 0.19.0 | As every sibling: a bootstrap cannot set a repository variable; 0.20.0's lane-shared install breaks Next | `.github/workflows/ci.yml`, `intent.yaml` |
| 14 | Component docs are generated from the manifests and checked in CI; orun is pinned only where it runs | A hand-written copy drifts silently | `tooling/catalog/gen-component-docs.py` |
| 15 | `subdomain` is read from the Cloudflare connection, never asked; the console asks for no domain | Both belong to the account or the owner, not to the build | `blueprint.yaml` |
