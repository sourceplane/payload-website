import fs from 'fs'
import { sqliteD1Adapter } from '@payloadcms/db-d1-sqlite'
import { r2Storage } from '@payloadcms/storage-r2'
import { type CloudflareContext, getCloudflareContext } from '@opennextjs/cloudflare'
import type { GetPlatformProxyOptions } from 'wrangler'
import path from 'path'
import { buildConfig, PayloadRequest } from 'payload'
import { fileURLToPath } from 'url'

import { Categories } from './collections/Categories'
import { Media } from './collections/Media'
import { Pages } from './collections/Pages'
import { Posts } from './collections/Posts'
import { Users } from './collections/Users'
import { Footer } from './Footer/config'
import { Header } from './Header/config'
import { plugins } from './plugins'
import { defaultLexical } from '@/fields/defaultLexical'
import { getServerSideURL } from './utilities/getURL'
import { appSecret } from './utilities/appSecrets'

const filename = fileURLToPath(import.meta.url)
const dirname = path.dirname(filename)
const realpath = (value: string) => (fs.existsSync(value) ? fs.realpathSync(value) : undefined)
const isCLI = process.argv.some((value) => realpath(value)?.endsWith(path.join('payload', 'bin.js')))
const isProduction = process.env.NODE_ENV === 'production'

// The D1 database and the R2 bucket are bindings, not connection strings. In
// the Worker they come from its own context; under the Payload CLI and
// `next dev` from wrangler's local platform proxy (wrangler.jsonc's bindings,
// the local D1 and R2 under .wrangler/).
// `next build` reads no data — every page renders per request — so it starts
// no platform proxy: its page-data workers would each open the same local D1
// and lock it.
const isBuild = process.env.NEXT_PHASE === 'phase-production-build'
const cloudflare: Pick<CloudflareContext, 'env'> = isBuild
  ? { env: {} as CloudflareEnv }
  : isCLI || !isProduction
    ? await getCloudflareContextFromWrangler()
    : await getCloudflareContext({ async: true })

function getCloudflareContextFromWrangler(): Promise<CloudflareContext> {
  return import(/* webpackIgnore: true */ `${'__wrangler'.replaceAll('_', '')}`).then(
    ({ getPlatformProxy }) =>
      getPlatformProxy({
        environment: process.env.CLOUDFLARE_ENV,
        remoteBindings: false,
      } satisfies GetPlatformProxyOptions),
  )
}

// Payload's signing key: the Worker secret PAYLOAD_SECRET if one is set, else
// the key packages/db's 020_app_secrets migration generated in this site's D1
// database (utilities/appSecrets.ts). `next build` and the Payload CLI's
// generators (types, the import map) sign nothing, so before a local database
// is migrated they get a placeholder that no running site ever uses.
const secret =
  (isBuild ? undefined : await appSecret('payload', cloudflare.env.D1).catch(() => undefined)) ||
  (isBuild || isCLI ? 'build-and-cli-sign-nothing' : undefined)
if (!secret) {
  throw new Error(
    'No PAYLOAD_SECRET: the D1 database has no generated app_secrets row (run the migrations — pnpm --filter @app/web db:migrate:local, or the db-migrate lane) and no Worker secret is set',
  )
}

export default buildConfig({
  admin: {
    components: {
      // The `BeforeLogin` component renders a message that you see while logging into your admin panel.
      // Feel free to delete this at any time. Simply remove the line below.
      beforeLogin: ['@/components/BeforeLogin'],
      // The `BeforeDashboard` component renders the 'welcome' block that you see after logging into your admin panel.
      // Feel free to delete this at any time. Simply remove the line below.
      beforeDashboard: ['@/components/BeforeDashboard'],
    },
    importMap: {
      baseDir: path.resolve(dirname),
    },
    user: Users.slug,
    livePreview: {
      breakpoints: [
        {
          label: 'Mobile',
          name: 'mobile',
          width: 375,
          height: 667,
        },
        {
          label: 'Tablet',
          name: 'tablet',
          width: 768,
          height: 1024,
        },
        {
          label: 'Desktop',
          name: 'desktop',
          width: 1440,
          height: 900,
        },
      ],
    },
  },
  // This config helps us configure global or default features that the other editors can inherit
  editor: defaultLexical,
  // The schema is packages/db's migrations, applied before the Worker deploys;
  // Payload never pushes schema changes itself.
  db: sqliteD1Adapter({ binding: cloudflare.env.D1, push: false }),
  collections: [Pages, Posts, Media, Categories, Users],
  cors: [getServerSideURL()].filter(Boolean),
  plugins: [
    ...plugins,
    r2Storage({
      bucket: cloudflare.env.R2,
      collections: { media: true },
    }),
  ],
  globals: [Header, Footer],
  secret,
  typescript: {
    outputFile: path.resolve(dirname, 'payload-types.ts'),
  },
  jobs: {
    access: {
      run: async ({ req }: { req: PayloadRequest }): Promise<boolean> => {
        // Allow logged in users to execute this endpoint (default)
        if (req.user) return true

        // Otherwise the Cron Trigger's own request (worker.ts), which carries
        // the cron secret as its bearer — CRON_SECRET, else the generated one.
        const cron = await appSecret('cron').catch(() => undefined)
        if (!cron) return false

        const authHeader = req.headers.get('authorization')
        return authHeader === `Bearer ${cron}`
      },
    },
    tasks: [],
  },
})
