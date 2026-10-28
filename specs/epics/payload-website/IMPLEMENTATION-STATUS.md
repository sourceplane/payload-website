# payload-website — implementation status

| Milestone | State | Landed |
|---|---|---|
| PW0 — the spec | ✅ | the repository's first commit |
| PW1 — Payload on Workers, D1 and R2 | ✅ | PW-2 |
| PW2 — a baseline | ✅ | PW-3, tagged `baseline-v1` |

## Departures from the upstream template

Everything not listed here is the template as it is at Payload's tag `v3.89.0`.

| # | What | Why |
|---|---|---|
| 1 | The app lives in `apps/web` of a pnpm workspace; `Dockerfile`, `docker-compose.yml`, `vercel.json`, the Playwright and Vitest integration tests and their configs are not carried | Other hosts' files; the template's tests need a running database, and `tests/web` / `tests/db` take their place |
| 2 | `@payloadcms/db-vercel-postgres` → `@payloadcms/db-d1-sqlite` (`push: false`), `@payloadcms/storage-vercel-blob` → `@payloadcms/storage-r2`; every `@payloadcms/*` at 3.89.0 | Payload's own Cloudflare template's adapters |
| 3 | `payload.config.ts` reads the bindings from the Cloudflare context (the platform proxy under the CLI and `next dev`, none during `next build`), the secret from `appSecrets.ts`, and the cron bearer for `jobs.access.run` | D1 and R2 are bindings; the secrets are generated |
| 4 | `sharp` removed from the config and the dependencies | No native sharp on Workers |
| 5 | Frontend pages `force-dynamic`, `generateStaticParams` and `revalidate` removed | The build has no database |
| 6 | `next.config.ts`: `output: 'standalone'`, the trace and Turbopack roots at the workspace root, `serverExternalPackages: ['jose', 'pg-cloudflare']`, `images.unoptimized`, the origin from `NEXT_PUBLIC_SERVER_URL` | OpenNext's build |
| 7 | `build` is `next build --webpack && next-sitemap && opennextjs-cloudflare build` | Turbopack's hashed externals; the sitemap step was `postbuild` |
| 8 | `generatePreviewPath` is async and reads the preview secret from `appSecrets.ts`; the preview route checks the same | The secret is generated |
| 9 | `getURL.ts`, the sitemaps, `environment.d.ts`: `VERCEL_PROJECT_PRODUCTION_URL` removed | Vercel's variable |
| 10 | `src/site.ts` (`SITE_NAME`) for the titles, `generateMeta`'s title suffix, the SEO plugin's generated title and the Open Graph defaults | One rename seam |
| 11 | `worker.ts`, `src/utilities/scheduled.ts`, `src/utilities/appSecrets.ts`, `cloudflare-env.d.ts`, `open-next.config.ts`, `wrangler.template.jsonc` | The Workers runtime |
| 12 | The admin's import map regenerated | The Vercel Blob client handler is gone |
| 13 | `eslint.config.mjs` in eslint-config-next 16's flat form; `react-hooks/set-state-in-effect` and `react-hooks/refs` off | FlatCompat fails on 16; two new rules the template was not written against |
| 14 | The template's migrations (Postgres) dropped; the schema is `packages/db`'s `010_payload` (D1) | One schema, one ledger |
