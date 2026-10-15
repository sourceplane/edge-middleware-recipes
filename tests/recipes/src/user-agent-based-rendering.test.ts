import { describe, expect, it } from "vitest";
import { app, env } from "./helpers";

const iphone = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1";
const mac = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36";

describe("user-agent-based-rendering", () => {
  it("rewrites a mobile User-Agent to the mobile page", async () => {
    const res = await (await app()).request("/user-agent-based-rendering", { headers: { "user-agent": iphone } }, env());
    expect(res.status).toBe(200);
    expect(await res.text()).toContain("loaded on a <b>mobile</b> device");
  });

  it("rewrites everything else to the desktop page", async () => {
    const res = await (await app()).request("/user-agent-based-rendering", { headers: { "user-agent": mac } }, env());
    expect(await res.text()).toContain("loaded on a <b>desktop</b> device");
  });
});
