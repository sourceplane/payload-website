import { afterEach, describe, expect, it, vi } from "vitest";

afterEach(() => {
  delete process.env.CRON_SECRET;
  vi.resetModules();
});

const ctx = { waitUntil() {}, passThroughOnException() {} } as unknown as ExecutionContext;
const controller = { cron: "0 0 * * *", scheduledTime: Date.UTC(2026, 9, 28), noRetry() {} } as ScheduledController;

describe("the Cron Trigger (apps/web/src/utilities/scheduled.ts)", () => {
  it("runs Payload's job queue the way Vercel Cron did: GET /api/payload-jobs/run with the cron bearer", async () => {
    process.env.CRON_SECRET = "the-cron-secret";
    const { makeScheduled, JOBS_PATH } = await import("@/utilities/scheduled");
    const seen: Request[] = [];
    const scheduled = makeScheduled(async (request) => {
      seen.push(request);
      return new Response('{"message":"Success"}', { status: 200 });
    });
    await scheduled(controller, {} as CloudflareEnv, ctx);
    expect(seen).toHaveLength(1);
    const [request] = seen as [Request];
    expect(new URL(request.url).pathname).toBe(JOBS_PATH);
    expect(request.method).toBe("GET");
    expect(request.headers.get("authorization")).toBe("Bearer the-cron-secret");
  });

  it("fails the invocation when the job run is refused", async () => {
    process.env.CRON_SECRET = "the-cron-secret";
    const { makeScheduled } = await import("@/utilities/scheduled");
    const scheduled = makeScheduled(async () => new Response("Forbidden", { status: 403 }));
    await expect(scheduled(controller, {} as CloudflareEnv, ctx)).rejects.toThrow(/answered 403/);
  });
});
