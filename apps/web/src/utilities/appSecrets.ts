import { getCloudflareContext } from '@opennextjs/cloudflare'

// The site's three secrets — Payload's signing key, the preview token and the
// cron bearer — without anyone typing one. packages/db's 020_app_secrets
// migration generates each once in the site's own D1 database; a Worker
// secret of the upper-case name (PAYLOAD_SECRET, PREVIEW_SECRET, CRON_SECRET)
// wins over the generated value.
export type AppSecret = 'payload' | 'preview' | 'cron'

const ENV_NAME: Record<AppSecret, string> = {
  payload: 'PAYLOAD_SECRET',
  preview: 'PREVIEW_SECRET',
  cron: 'CRON_SECRET',
}

type SecretsDB = {
  prepare(sql: string): {
    bind(...values: unknown[]): { first<T>(): Promise<T | null> }
  }
}

const cache = new Map<AppSecret, string>()

/** The secret's value: the Worker secret if one is set, else the generated row. */
export async function appSecret(name: AppSecret, db?: SecretsDB): Promise<string | undefined> {
  const fromEnv = process.env[ENV_NAME[name]]
  if (fromEnv) return fromEnv
  const cached = cache.get(name)
  if (cached) return cached
  const d1 = db ?? ((await getCloudflareContext({ async: true })).env.D1 as unknown as SecretsDB)
  const row = await d1
    .prepare('SELECT value FROM app_secrets WHERE name = ?')
    .bind(name)
    .first<{ value: string }>()
  if (row?.value) cache.set(name, row.value)
  return row?.value
}
