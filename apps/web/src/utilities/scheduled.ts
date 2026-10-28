import { appSecret } from './appSecrets'

type FetchHandler = (
  request: Request,
  env: CloudflareEnv,
  ctx: ExecutionContext,
) => Response | Promise<Response>

// Vercel ran Payload's job queue (scheduled publishing) by requesting
// /api/payload-jobs/run once a day (vercel.json `crons`), with CRON_SECRET as
// its bearer. Here the Cron Trigger in wrangler.jsonc fires on the same
// schedule, and this handler makes the same request through the OpenNext fetch
// handler, in process — the template's own endpoint, unchanged, is what runs.
// The bearer is CRON_SECRET if the Worker has one, else the cron secret the
// database generated. The origin is a placeholder; the route never reads it.
export const CRON_ORIGIN = 'https://cron.internal'
export const JOBS_PATH = '/api/payload-jobs/run'

export function makeScheduled(fetch: FetchHandler) {
  return async function scheduled(
    _controller: ScheduledController,
    env: CloudflareEnv,
    ctx: ExecutionContext,
  ): Promise<void> {
    const cron = await appSecret('cron', env.D1 as never)
    if (!cron) throw new Error('scheduled: no cron secret (CRON_SECRET, or app_secrets in D1)')
    const response = await fetch(
      new Request(`${CRON_ORIGIN}${JOBS_PATH}`, { headers: { authorization: `Bearer ${cron}` } }),
      env,
      ctx,
    )
    const body = await response.text()
    if (!response.ok) {
      // A thrown error marks the invocation failed in the Worker's logs.
      throw new Error(`${JOBS_PATH} answered ${response.status}: ${body.slice(0, 200)}`)
    }
    console.log(`${JOBS_PATH} ${response.status} ${body.slice(0, 200)}`)
  }
}
