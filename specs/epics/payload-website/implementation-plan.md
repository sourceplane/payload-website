# payload-website — implementation plan

Three milestones, each one reviewed pull request (PW0 is the repository's
first commit), each green before it merges.

## PW0 — the spec (PW-1)

The repository is born: `intent.yaml` with the placeholder workspace
`ws_CHANGE_ME`, `ci.yml` (byte for byte turso-starter's), the shared
TypeScript and ESLint configuration, the wiring renderer and migration
helpers, the spec index, this doc set and the task contracts.

## PW1 — Payload on Workers, D1 and R2 (PW-2)

- The template at `v3.89.0` in `apps/web`: the D1 and R2 adapters in
  `payload.config.ts` (bindings from the Cloudflare context; no proxy during
  `next build`), `push: false`, no sharp, pages per request, the admin's
  import map regenerated, ESLint in eslint-config-next 16's flat form.
- `worker.ts` and `src/utilities/scheduled.ts`: the Cron Trigger.
- `src/site.ts` (the name seam), `src/utilities/appSecrets.ts` (the secrets
  from D1), `NEXT_PUBLIC_SERVER_URL` per environment.
- `wrangler.template.jsonc` + `wiring.fixture.json` (D1, R2, the cron),
  `component.yaml` (deploy contract, smoke).
- `packages/db`: `010_payload` (from `payload migrate:create` through
  `tooling/migrations/payload-sql.mjs`), `020_app_secrets`; the D1 and R2
  roots; `infra/db-migrate`.
- `tests/web` and `tests/db`.

## PW2 — a baseline (PW-3)

turso-starter's machinery with the R2 root added: `blueprint.yaml`,
`repo-blueprint.yaml` (four brokered keys), `.baseline/`, the rename engine,
the bootstrap helpers, the record renderer (probing `/`, `/api/users/me` and
`/admin`), `docs/phases/`, the context pack, and `testing/` — the leak,
placement and wiring gates over D1 and R2, and the e2e tier that migrates
the stage database through a stand-in D1 API, then serves the built Worker,
signs up an admin, seeds D1 and R2 and runs the Cron Trigger.
