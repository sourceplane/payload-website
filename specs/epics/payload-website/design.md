# payload-website — design

## The template

Payload's website template (`templates/with-vercel-website` in
[payloadcms/payload](https://github.com/payloadcms/payload), the "Payload
Website Starter" on Vercel) is Payload 3 and its Next.js frontend in one app:
collections for pages (layout blocks: content, media, call to action,
archive, forms), posts, media, categories and users; header and footer
globals; the form-builder, nested-docs, redirects, search and SEO plugins;
drafts and versions with live preview; scheduled publishing through
Payload's job queue; a seed endpoint that fills a demo site; and an admin
panel at `/admin`. On Vercel it uses Vercel Postgres and Vercel Blob, runs
`payload migrate` before `next build`, pre-renders pages and posts from the
database, and runs the job queue from a Vercel Cron.

## How it maps to Cloudflare

| Vercel | Here | Why |
|---|---|---|
| Vercel Postgres adapter | `@payloadcms/db-d1-sqlite`, the `D1` binding | Payload's own Cloudflare template; a binding needs no connection string |
| Vercel Blob storage | `@payloadcms/storage-r2`, the `R2` binding | The same; no storage key |
| `payload migrate` in the build | `packages/db` migrations — the DDL `payload migrate:create` generates for the D1 adapter, made idempotent — applied by `infra/db-migrate` before the Worker deploys; `push: false` | turso-starter's shape: the plan orders database, schema, Worker; one ledger per database |
| Pre-rendering from Postgres | Every page per request from D1 | The build has no database; D1 answers at the edge |
| `PAYLOAD_SECRET`, `PREVIEW_SECRET`, `CRON_SECRET` | Generated in D1 by `020_app_secrets`; Worker secrets override | A site comes up with nothing typed |
| Vercel Cron → `/api/payload-jobs/run` | A Cron Trigger; `worker.ts`'s `scheduled` requests the endpoint in process | cron-starter's custom-worker shape |
| sharp (resizing) | None: originals kept | No native sharp on Workers |
| `VERCEL_PROJECT_PRODUCTION_URL` | `NEXT_PUBLIC_SERVER_URL` per environment | Absolute links, CORS, preview links |

## The repository

turso-starter's shape plus blob-starter's R2 root: `infra/terraform/cloudflare-d1`
and `infra/terraform/cloudflare-r2` (one database and one bucket per deployed
environment, wiring documents lease-published), `packages/db` (the migrations
and their runner, over the D1 REST API), `infra/db-migrate`, `apps/web`
(type `cloudflare-workers-assets-turbo`, depending on all three, enforced on
main), `tests/web` and `tests/db`. The site's name is one seam, `SITE_NAME`
in `apps/web/src/site.ts`, read by every page's title, the SEO plugin and
the Open Graph defaults.

## The build

`next build --webpack` (Turbopack hashes `drizzle-kit/api`'s external name,
which OpenNext's esbuild cannot resolve), `next-sitemap` (the robots file
and sitemap index into `public/`), then `opennextjs-cloudflare build`. During
`next build` Payload starts no platform proxy (`NEXT_PHASE`): no page reads
data at build, and seven page-data workers opening one local D1 lock it. The
Worker is about 4 MiB gzipped — Workers Paid.

`repo-blueprint.yaml` is turso-starter's with the R2 root and a fourth
brokered key (`r2-data`): one landing (`01-product`), one convergence that
applies the database and the bucket, migrates, and deploys stage and prod
side by side, and `02-docs`, the record. The smoke checks the home page, the
REST API answering from D1, and the admin.

## Out of scope

- Image resizing and focal-point crops: they need sharp. Cloudflare Images
  is the upgrade path.
- Email: Payload logs emails it would send (no adapter configured), as
  upstream.

## The alternative rejected

**Payload migrating itself** — `prodMigrations` in the adapter, or
`payload migrate` in the deploy lane, as Payload's Cloudflare template does.
The first runs DDL from the Worker on a cold start, inside a request; the
second needs wrangler's remote platform proxy in CI. Both put the schema
outside db-migrate's ledger and the plan's order, which every database
baseline here shares.
