import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

// A D1 that answers the one statement appSecrets.ts sends.
function fakeD1(rows: Record<string, string>) {
  const asked: { sql: string; name: unknown }[] = [];
  return {
    asked,
    db: {
      prepare(sql: string) {
        return {
          bind(name: unknown) {
            return {
              async first<T>(): Promise<T | null> {
                asked.push({ sql, name });
                const value = rows[String(name)];
                return (value ? { value } : null) as T | null;
              },
            };
          },
        };
      },
    },
  };
}

beforeEach(() => {
  vi.resetModules();
});
afterEach(() => {
  delete process.env.PAYLOAD_SECRET;
  delete process.env.PREVIEW_SECRET;
  delete process.env.CRON_SECRET;
});

describe("the site's generated secrets (apps/web/src/utilities/appSecrets.ts)", () => {
  it("reads a secret the migration generated, by name, from the D1 binding", async () => {
    const { appSecret } = await import("@/utilities/appSecrets");
    const { db, asked } = fakeD1({ payload: "a".repeat(64) });
    expect(await appSecret("payload", db)).toBe("a".repeat(64));
    expect(asked).toEqual([{ sql: "SELECT value FROM app_secrets WHERE name = ?", name: "payload" }]);
  });

  it("lets a Worker secret of the upper-case name win, without reading D1", async () => {
    const { appSecret } = await import("@/utilities/appSecrets");
    const { db, asked } = fakeD1({ preview: "generated" });
    process.env.PREVIEW_SECRET = "set-by-the-owner";
    expect(await appSecret("preview", db)).toBe("set-by-the-owner");
    expect(asked).toEqual([]);
  });

  it("reads each once per isolate", async () => {
    const { appSecret } = await import("@/utilities/appSecrets");
    const { db, asked } = fakeD1({ cron: "c".repeat(64) });
    await appSecret("cron", db);
    await appSecret("cron", db);
    expect(asked).toHaveLength(1);
  });

  it("answers nothing when the database has no such row (the migrations have not run)", async () => {
    const { appSecret } = await import("@/utilities/appSecrets");
    expect(await appSecret("payload", fakeD1({}).db)).toBeUndefined();
  });
});
