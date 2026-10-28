#!/usr/bin/env node
// Turns a Payload migration (what `payload migrate:create` writes, a .ts file
// whose `up` runs `db.run(sql`…`)` statements) into the plain, idempotent SQL
// file packages/db applies — over the D1 REST API on stage and prod (the
// db-migrate component), and to wrangler's local D1 (tooling/migrations/local.mjs).
//
//   node tooling/migrations/payload-sql.mjs <migration.ts> <out/up.sql>
//
// The schema lives in packages/db, not in Payload's own migrations directory:
// the Worker never runs `payload migrate`, and one place for the schema means
// one ledger of what each database has. Only `up` is read. Every CREATE gains
// IF NOT EXISTS, so applying the file twice (a local re-run) is a no-op; an
// ALTER TABLE is left as it is and is the runner's ledger's to apply once.
import { readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { dirname } from "node:path";

const [src, out] = process.argv.slice(2);
if (!src || !out) {
  console.error("usage: payload-sql.mjs <migration.ts> <out/up.sql>");
  process.exit(2);
}
const text = readFileSync(src, "utf8");
const up = text.slice(text.indexOf("export async function up"), text.indexOf("export async function down"));
if (!up.trim()) {
  console.error(`payload-sql: no \`up\` function in ${src}`);
  process.exit(1);
}

// Each statement is a sql`…` template literal; the generator escapes the
// backticks of quoted identifiers as \` and has no ${} interpolation.
const statements = [];
const re = /sql`((?:\\[\s\S]|[^`\\])*)`/g;
for (const m of up.matchAll(re)) {
  let stmt = m[1].replace(/\\`/g, "`").replace(/\\\\/g, "\\").trim();
  if (stmt.includes("${")) {
    console.error(`payload-sql: an interpolated statement cannot be translated:\n${stmt}`);
    process.exit(1);
  }
  stmt = stmt
    .replace(/^CREATE TABLE (?!IF NOT EXISTS)/i, "CREATE TABLE IF NOT EXISTS ")
    .replace(/^CREATE UNIQUE INDEX (?!IF NOT EXISTS)/i, "CREATE UNIQUE INDEX IF NOT EXISTS ")
    .replace(/^CREATE INDEX (?!IF NOT EXISTS)/i, "CREATE INDEX IF NOT EXISTS ")
    .replace(/[ \t]+$/gm, "")
    .replace(/\t/g, "  ");
  if (!stmt.endsWith(";")) stmt += ";";
  statements.push(stmt);
}
if (statements.length === 0) {
  console.error(`payload-sql: no sql\`…\` statements in ${src}'s \`up\``);
  process.exit(1);
}
mkdirSync(dirname(out), { recursive: true });
writeFileSync(
  out,
  `-- Generated from ${src.split("/").pop()} (payload migrate:create) by\n` +
    `-- tooling/migrations/payload-sql.mjs. Edit the collections and regenerate a\n` +
    `-- NEW migration; never edit an applied one.\n\n` +
    statements.join("\n\n") +
    "\n",
);
console.log(`payload-sql: ${statements.length} statement(s) → ${out}`);
