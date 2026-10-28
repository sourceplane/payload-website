# payload-website — open risks

What is not yet proven or not yet decided. The full write-up of every risk,
including the accepted and resolved ones, is
`specs/epics/payload-website/risks-and-open-questions.md`; this page lists
only what is still live, so it should be short.

| ID | Risk | State | What closes it |
|---|---|---|---|
| PW-A | `baseline-v1` is not yet proven live; it is proven offline in Baseline CI (the offline bootstrap, the lanes' own steps, the site served by `wrangler dev`: migrated, signed up, seeded into D1 and R2, its Cron Trigger run) | OPEN | One console bootstrap from `baseline-v1` |
| PW-B | The Worker is about 4 MiB gzipped: it deploys only on Workers Paid (10 MiB); Workers Free (3 MiB) refuses it | OPEN | A build on a Paid account; the registry row says so and stays unlisted until then |
| PW-G | A Worker's startup and request CPU limits under Payload's admin | WATCH | Holds under `wrangler dev`; the live build measures it |

Accepted, and worth knowing before you change them: PW-C (no image
resizing), PW-D (the schema is the migrations), PW-E (the secrets live in
D1), PW-F (a webpack build), PW-H (stack-tectonic 0.19.0).
