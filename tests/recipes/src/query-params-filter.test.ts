import { describe, expect, it } from "vitest";
import { app, env } from "./helpers";

describe("query-params-filter", () => {
  it("redirects (307) to the URL with only the allowed params", async () => {
    const res = await (await app()).request("/query-params-filter?a=b&allowed=test", undefined, env());
    expect(res.status).toBe(307);
    expect(res.headers.get("location")).toBe("http://localhost/query-params-filter?allowed=test");
  });

  it("serves the page when nothing had to be removed", async () => {
    const res = await (await app()).request("/query-params-filter?allowed=test", undefined, env());
    expect(res.status).toBe(200);
    expect(await res.text()).toContain("query: ?allowed=test");
  });
});
