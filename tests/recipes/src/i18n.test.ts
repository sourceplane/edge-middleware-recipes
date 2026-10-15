import { describe, expect, it } from "vitest";
import { app, env, withCf } from "./helpers";

describe("i18n", () => {
  it("rewrites / to /<locale>/<country> from Accept-Language and the visitor's country", async () => {
    const req = withCf("http://localhost/i18n", { country: "FR" }, { headers: { "accept-language": "fr" } });
    const res = await (await app()).request(req, undefined, env());
    expect(res.status).toBe(200);
    const body = await res.text();
    expect(body).toContain("Bonjour!");
    expect(body).toContain("locale:  fr");
    expect(body).toContain("country: fr");
  });

  it("falls back to the default dictionary and to 'us' without a known locale or a country", async () => {
    const res = await (await app()).request("/i18n", { headers: { "accept-language": "en-US,en;q=0.9" } }, env());
    const body = await res.text();
    expect(body).toContain("we could not detect your locale");
    expect(body).toContain("country: us");
  });
});
