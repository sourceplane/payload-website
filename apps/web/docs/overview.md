# web

The Payload website and its admin (Next.js and Payload CMS on Cloudflare Workers + Static Assets via @opennextjs/cloudflare, per environment)

A Cloudflare Worker with Static Assets (server rendering plus static files), deployed per environment by its CI lane.

|              |                                                                                                                    |
| ------------ | ------------------------------------------------------------------------------------------------------------------ |
| Type         | `cloudflare-workers-assets-turbo`                                                                                  |
| Source       | `apps/web`                                                                                                         |
| Package      | `@app/web`                                                                                                         |
| Environments | `dev`: `verify` · `stage`: `verify`, `deploy` on a push to `main` · `prod`: `verify`, `deploy` on a push to `main` |

## Depends on

- **cloudflare-d1** — Provisions the Cloudflare D1 database Payload stores the site in, for stage and prod
- **cloudflare-r2** — Provisions the Cloudflare R2 bucket Payload stores media uploads in (stage and prod)
- **db-migrate** — Applies Payload's schema and the site's generated secrets (packages/db's migrations) to the stage and prod Cloudflare D1 databases

## Depended on by

- (none)
