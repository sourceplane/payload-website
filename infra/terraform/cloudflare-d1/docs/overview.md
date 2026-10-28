# cloudflare-d1

Provisions the Cloudflare D1 database Payload stores the site in, for stage and prod

Terraform-managed infrastructure, planned and applied per environment by its CI lane.

|              |                                                                                                      |
| ------------ | ---------------------------------------------------------------------------------------------------- |
| Type         | `terraform`                                                                                          |
| Source       | `infra/terraform/cloudflare-d1`                                                                      |
| Environments | `stage`: `plan-only`, `apply` on a push to `main` · `prod`: `plan-only`, `apply` on a push to `main` |

## Depends on

- (none)

## Depended on by

- **db-migrate** — Applies Payload's schema and the site's generated secrets (packages/db's migrations) to the stage and prod Cloudflare D1 databases
- **web** — The Payload website and its admin (Next.js and Payload CMS on Cloudflare Workers + Static Assets via @opennextjs/cloudflare, per environment)
