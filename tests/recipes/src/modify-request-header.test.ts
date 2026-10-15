import { describe, expect, it } from "vitest";
import { app, env } from "./helpers";

describe("modify-request-header", () => {
  it("adds, overrides and deletes request headers before the route sees them", async () => {
    const res = await (await app()).request(
      "/modify-request-header",
      { headers: { "user-agent": "curl/8", "x-from-client": "secret" } },
      env(),
    );
    expect(res.status).toBe(200);
    const body = await res.text();
    expect(body).toContain("x-hello-from-middleware1: </strong>hello");
    expect(body).toContain("x-hello-from-middleware2: </strong>world!");
    expect(body).toContain("user-agent: </strong>New User Agent overriden by middleware!");
    expect(body).toContain("x-from-client: </strong>(deleted)");
  });
});
