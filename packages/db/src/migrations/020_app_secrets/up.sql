-- The site's own secrets, generated once in the database the first time this
-- migration runs on it, so a site built from the template needs no secret
-- typed anywhere to come up:
--   payload  — PAYLOAD_SECRET, the key Payload signs its session tokens with
--   preview  — PREVIEW_SECRET, the token the admin's draft previews carry
--   cron     — CRON_SECRET, the bearer the Cron Trigger's job run carries
-- A Worker secret of the same upper-case name (wrangler secret put
-- PAYLOAD_SECRET) wins over the generated value. Rotating one is updating its
-- row (or setting the Worker secret); rotating `payload` signs everyone out.
-- INSERT OR IGNORE: a value, once generated, is never replaced by a re-run.
CREATE TABLE IF NOT EXISTS app_secrets (
  name        TEXT PRIMARY KEY,
  value       TEXT NOT NULL,
  created_at  TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now'))
);

INSERT OR IGNORE INTO app_secrets (name, value) VALUES ('payload', lower(hex(randomblob(32))));

INSERT OR IGNORE INTO app_secrets (name, value) VALUES ('preview', lower(hex(randomblob(32))));

INSERT OR IGNORE INTO app_secrets (name, value) VALUES ('cron', lower(hex(randomblob(32))));
