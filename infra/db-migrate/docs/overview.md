# db-migrate

Applies Payload's schema and the site's generated secrets (packages/db's migrations) to the stage and prod Cloudflare D1 databases

Applies this repository's ordered database migrations per environment: plan on pull requests, apply on merge to `main`.

|              |                                                                                            |
| ------------ | ------------------------------------------------------------------------------------------ |
| Type         | `db-migrate`                                                                               |
| Source       | `infra/db-migrate`                                                                         |
| Environments | `stage`: `plan`, `apply` on a push to `main` · `prod`: `plan`, `apply` on a push to `main` |

## Depends on

- **db** — Payload's schema and the site's generated secrets as migrations, and the runner that applies them to D1 (built by the db-migrate component before it plans or applies)
- **cloudflare-d1** — Provisions the Cloudflare D1 database Payload stores the site in, for stage and prod

## Depended on by

- **web** — The Payload website and its admin (Next.js and Payload CMS on Cloudflare Workers + Static Assets via @opennextjs/cloudflare, per environment)
