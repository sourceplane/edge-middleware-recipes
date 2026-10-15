import { describe, expect, it } from "vitest";
import { app, env } from "./helpers";

describe("the index (/)", () => {
  it("lists the thirteen recipes with links", async () => {
    const res = await (await app()).request("/", undefined, env());
    expect(res.status).toBe(200);
    const body = await res.text();
    for (const slug of [
      "geolocation", "i18n", "basic-auth-password", "rate-limit-any-framework", "ab-testing-simple",
      "maintenance-page", "cookies", "add-header", "modify-request-header", "query-params-filter",
      "json-response", "user-agent-based-rendering", "redirects-bloom-filter",
    ]) {
      expect(body).toContain(`href="/${slug}"`);
    }
  });

  it("answers an unknown path with 404", async () => {
    const res = await (await app()).request("/nope", undefined, env());
    expect(res.status).toBe(404);
  });
});
