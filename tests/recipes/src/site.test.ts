import { describe, expect, it } from "vitest";
import { app, env } from "./helpers";

// hono/html's escaping: a product name may carry `&` or `'`.
const escaped = (s: string) =>
  s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;").replace(/'/g, "&#39;");

describe("site identity (apps/recipes/src/site.ts)", () => {
  it("names the product and links its source repository", async () => {
    const { SITE_NAME, SOURCE_URL } = await import("@/site");
    expect(SITE_NAME.trim()).not.toBe("");
    expect(SOURCE_URL).toMatch(/^https:\/\/github\.com\/[A-Za-z0-9-]+\/[a-z0-9-]+$/);
  });

  it("is the index page's heading and title, and every footer's source link", async () => {
    const { SITE_NAME, SOURCE_URL } = await import("@/site");
    const index = await (await (await app()).request("/", undefined, env())).text();
    expect(index).toContain(`<title>${escaped(SITE_NAME)}</title>`);
    expect(index).toContain(`<h1>${escaped(SITE_NAME)}</h1>`);
    const recipe = await (await (await app()).request("/cookies", undefined, env())).text();
    expect(recipe).toContain(`<a href="${SOURCE_URL}">source</a>`);
  });
});
