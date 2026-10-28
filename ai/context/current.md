# payload-website — where this repository stands

The entry page for anyone (or any agent) picking this repository up. It is
this repository's own state and does not ship to a site built from it; the
two pages that do are [operations.md](operations.md) and
[deployment.md](deployment.md).

## What it is

Vercel's Payload Website Starter (payloadcms/payload's
`templates/with-vercel-website`) — Payload CMS and the website it publishes,
one Next.js app — built by OpenNext into one Cloudflare Worker with Static
Assets, the content in a Cloudflare D1 database and the media in an R2
bucket that Terraform provisions per environment, the schema applied by
db-migrate, packaged as an Orun baseline: `orun new --blueprint
repo-blueprint.yaml` builds a new site in its own repository and takes it to
live on stage and prod in one landing (`01-product`), then records what went
live (`02-docs`). It needs a Workers Paid account.

## Release

| | |
|---|---|
| Latest tag | `baseline-v1` — PW0 to PW2: the repository, Payload on Workers with D1 and R2, and the baseline (blueprint, phases, tests) |
| Proven live | Not yet: proven offline in Baseline CI only (risk PW-A); needs a Workers Paid account (PW-B) |

## Where to read

| Question | Page |
|---|---|
| What shipped, and every departure from upstream | `specs/epics/payload-website/IMPLEMENTATION-STATUS.md` |
| Why it is built this way | [decisions.md](decisions.md), then `specs/epics/payload-website/design.md` |
| What could still go wrong | [open-risks.md](open-risks.md), then `specs/epics/payload-website/risks-and-open-questions.md` |
| How to instantiate it | `BOOTSTRAP.md`, `docs/phases/` |
| What the components are | each component's `docs/` (generated; `python3 tooling/catalog/gen-component-docs.py`) |

## Next

1. Bootstrap one site from `baseline-v1` into a workspace whose Cloudflare
   account is on Workers Paid, sign up the first admin, seed, and record the
   timings against the 9-minute estimate (closes PW-A); then the registry row
   goes public with the measured minutes.
