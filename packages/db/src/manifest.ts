import type { MigrationManifest } from "./types.js";

// Every migration the runner applies, in order, with the sha256 of its file.
// `pnpm --filter @saas/db run manifest:check` verifies the checksums;
// `manifest:fix` rewrites them after a migration file changes (only ever
// before that migration has been applied anywhere — an applied migration's
// checksum is immutable).
export const manifest: MigrationManifest = {
  version: 1,
  migrations: [
    {
      id: "000_control_baseline",
      context: "control",
      path: "000_control/up.sql",
      checksum:
        "c7f11499fa82d6fd2baa1af7fc75eeb73cd7be252af2e56841509c66001d638b",
      description:
        "Baseline control migration — creates the migration tracking schema",
    },
    {
      id: "010_payload",
      context: "app",
      path: "010_payload/up.sql",
      checksum:
        "c16bbbb53188ad21d95c891096eccdf863952d3ec22b25abe56958b376091d9c",
      description:
        "The Payload website's schema — pages, posts, media, categories, users, the header and footer globals, forms, redirects, search, folders, jobs and their versions — as payload migrate:create generated it for the D1 adapter, made idempotent",
    },
    {
      id: "020_app_secrets",
      context: "app",
      path: "020_app_secrets/up.sql",
      checksum:
        "f0575dcea3daf0e6ecb8750e8f1def3e712c46b45d9b1897d648800f2790280b",
      description:
        "The site's generated secrets (Payload's signing key, the preview token, the cron bearer), each created once in this database",
    },
  ],
};
