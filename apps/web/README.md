# apps/web — Payload and its website

Payload's website template ([payloadcms/payload](https://github.com/payloadcms/payload)
`templates/with-vercel-website`, MIT — `LICENSE.md`): Payload 3 and its
Next.js frontend in one app, built by
[`@opennextjs/cloudflare`](https://opennext.js.org/cloudflare) into one
Cloudflare Worker with Static Assets.

- `/admin` — Payload's admin panel; `/api` — its REST and GraphQL APIs
- `/`, `/<slug>` — pages built from layout blocks; `/posts`, `/posts/<slug>`,
  `/search`; `/pages-sitemap.xml`, `/posts-sitemap.xml`
- `/next/preview` — drafts and live preview; `/next/seed` — the demo content

The database is the `D1` binding (`@payloadcms/db-d1-sqlite`), the media the
`R2` binding (`@payloadcms/storage-r2`); both are rendered into
`wrangler.jsonc` from `wrangler.template.jsonc`. `worker.ts` is the Worker's
entry: OpenNext's fetch handler and the Cron Trigger that runs Payload's job
queue. The site's name is `src/site.ts`; its secrets are read from D1
(`src/utilities/appSecrets.ts`).

```bash
pnpm db:migrate:local   # the schema and the generated secrets in wrangler's local D1
pnpm dev                # next dev on http://localhost:3000
pnpm build              # next build (webpack) → next-sitemap → opennextjs-cloudflare build → .open-next/
pnpm preview            # wrangler dev over the built Worker
pnpm payload <cmd>      # Payload's CLI (migrate:create, generate:types, generate:importmap)
```

How it is deployed — per environment, on merge to `main` — is the
repository's README and `component.yaml` beside this file.
