// The Worker's bindings as apps/web/cloudflare-env.d.ts declares them, over
// @cloudflare/workers-types' runtime globals (tsconfig `types`).
interface CloudflareEnv {
  D1: D1Database
  R2: R2Bucket
  ASSETS: Fetcher
}
