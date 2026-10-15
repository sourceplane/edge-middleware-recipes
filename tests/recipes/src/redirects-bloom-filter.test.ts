import { describe, expect, it } from "vitest";
import { app, env } from "./helpers";

describe("redirects-bloom-filter", () => {
  it("redirects a path in the table (307 for a temporary entry)", async () => {
    const res = await (await app()).request("/redirects-bloom-filter/blog/should-redirect-to-google", undefined, env());
    expect(res.status).toBe(307);
    expect(res.headers.get("location")).toBe("https://www.google.com");
  });

  it("falls through to the page for a path the filter rules out", async () => {
    const res = await (await app()).request("/redirects-bloom-filter/blog/should-render-basic-blog-post", undefined, env());
    expect(res.status).toBe(200);
    expect(await res.text()).toContain("Blog Post");
  });

  it("serves the lookup as the Route Handler too", async () => {
    const res = await (await app()).request("/redirects-bloom-filter/api/redirects?pathname=/blog/should-redirect-to-1", undefined, env());
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({ target: "https://www.google.com/?redirect=1", permanent: false });
  });
});
