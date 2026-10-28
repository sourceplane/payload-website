// The bindings wrangler.jsonc declares, as the Worker (and the Payload CLI and
// `next dev`, through the platform proxy) see them — D1Database and R2Bucket
// come with the Payload adapters' types — plus the slice of the Workers
// runtime the custom worker entry (worker.ts) uses. Hand-typed rather than
// `@cloudflare/workers-types` as a global, which would merge its own Request
// and Response over lib.dom's. Keep in step with wrangler.template.jsonc.
interface CloudflareEnv {
  D1: D1Database
  R2: R2Bucket
  ASSETS: Fetcher
}

interface ExecutionContext {
  waitUntil(promise: Promise<unknown>): void
  passThroughOnException(): void
}

interface ScheduledController {
  readonly cron: string
  readonly scheduledTime: number
  noRetry(): void
}

interface ExportedHandler<Env = unknown> {
  fetch?(request: Request, env: Env, ctx: ExecutionContext): Response | Promise<Response>
  scheduled?(controller: ScheduledController, env: Env, ctx: ExecutionContext): void | Promise<void>
}
