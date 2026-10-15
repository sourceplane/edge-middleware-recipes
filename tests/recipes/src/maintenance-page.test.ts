import { describe, expect, it } from "vitest";
import { app, env } from "./helpers";

describe("maintenance-page", () => {
  it("serves the maintenance page for /big-promo while the flag is on", async () => {
    const res = await (await app()).request("/maintenance-page/big-promo", undefined, env({ MAINTENANCE_MODE: "true" }));
    expect(res.status).toBe(200);
    expect(await res.text()).toContain("Under Maintenance");
  });

  it("serves the real page when the flag is off, and the setup dialog when it is missing", async () => {
    const off = await (await app()).request("/maintenance-page/big-promo", undefined, env({ MAINTENANCE_MODE: "false" }));
    expect(await off.text()).toContain("Something big is coming");

    const missing = await (await app()).request("/maintenance-page/big-promo", undefined, env({ MAINTENANCE_MODE: undefined }));
    expect(await missing.text()).toContain("Incomplete Environment Variables Setup");
  });
});
