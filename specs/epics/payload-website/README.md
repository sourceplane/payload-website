# payload-website — Vercel's Payload Website Starter on Cloudflare

**Payload's own Cloudflare port — the D1 adapter for Vercel Postgres, the R2
storage adapter for Vercel Blob — applied to the website template, with the
schema as migrations applied before the Worker deploys and the secrets
generated in the database; and the baseline that makes a copy of it
somebody else's site in one landing.**

| | |
|---|---|
| Status | In progress — PW1 on main: the site runs on Workers |
| Upstream | [payloadcms/payload](https://github.com/payloadcms/payload) `templates/with-vercel-website` (MIT), at tag `v3.89.0` |
| Reference | [turso-starter](https://github.com/sourceplane/turso-starter) — D1, migrations, db-migrate; [blob-starter](https://github.com/sourceplane/blob-starter) — R2; [cron-starter](https://github.com/sourceplane/cron-starter) — the Cron Trigger |
| Key | `PW` |

## Read in this order

1. [design.md](design.md) — the template, how each Vercel piece maps to
   Cloudflare, the repository and the build, and the alternative rejected.
2. [implementation-plan.md](implementation-plan.md) — the milestones.
3. [risks-and-open-questions.md](risks-and-open-questions.md) — what is not
   proven, and what was accepted.
4. [IMPLEMENTATION-STATUS.md](IMPLEMENTATION-STATUS.md) — what shipped, and
   every departure from the upstream template.

## Milestones

| Milestone | What it lands | Task |
|---|---|---|
| PW0 — the spec | the repository, its intent, CI, tooling and spec index; this doc set | PW-1 |
| PW1 — Payload on Workers, D1 and R2 | the template in `apps/web`, its schema as migrations, the D1 and R2 roots, the tests | PW-2 |
| PW2 — a baseline | the console card, the build document, the context pack and the baseline's tests | PW-3 |
