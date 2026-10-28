import { afterEach, describe, expect, it } from "vitest";
import { SITE_NAME } from "@/site";
import { mergeOpenGraph } from "@/utilities/mergeOpenGraph";
import { getServerSideURL } from "@/utilities/getURL";

afterEach(() => {
  delete process.env.NEXT_PUBLIC_SERVER_URL;
});

describe("site identity (apps/web/src/site.ts)", () => {
  it("names the site", () => {
    expect(SITE_NAME.trim()).not.toBe("");
  });

  it("is the Open Graph site name and default title", () => {
    const og = mergeOpenGraph();
    expect(og?.siteName).toBe(SITE_NAME);
    expect(og?.title).toBe(SITE_NAME);
    expect(mergeOpenGraph({ title: "A post" })?.title).toBe("A post");
  });
});

describe("the site's origin (apps/web/src/utilities/getURL.ts)", () => {
  it("is the one the deploy names, else localhost", () => {
    process.env.NEXT_PUBLIC_SERVER_URL = "https://acme-web-stage.acme.workers.dev";
    expect(getServerSideURL()).toBe("https://acme-web-stage.acme.workers.dev");
    delete process.env.NEXT_PUBLIC_SERVER_URL;
    expect(getServerSideURL()).toBe("http://localhost:3000");
  });
});
