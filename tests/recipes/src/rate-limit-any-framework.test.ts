import { describe, expect, it } from "vitest";
import { app, env, fakeRateLimiter } from "./helpers";

describe("rate-limit-any-framework", () => {
  it("allows 5 requests per IP and redirects the sixth to /blocked.html", async () => {
    const bindings = env({ RATE_LIMITER: fakeRateLimiter(5) });
    const a = await app();
    const headers = { "cf-connecting-ip": "203.0.113.7" };
    for (let i = 0; i < 5; i++) {
      const res = await a.request("/rate-limit-any-framework", { headers }, bindings);
      expect(res.status).toBe(200);
    }
    const sixth = await a.request("/rate-limit-any-framework", { headers }, bindings);
    expect(sixth.status).toBe(302);
    expect(sixth.headers.get("location")).toBe("http://localhost/rate-limit-any-framework/blocked.html");

    // another IP is another key
    const other = await a.request("/rate-limit-any-framework", { headers: { "cf-connecting-ip": "203.0.113.8" } }, bindings);
    expect(other.status).toBe(200);
  });
});
