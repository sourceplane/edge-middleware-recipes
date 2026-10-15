import { describe, expect, it } from "vitest";
import { app, env } from "./helpers";

describe("cookies", () => {
  it("rewrites / to the beta page when the beta cookie is true", async () => {
    const res = await (await app()).request("/cookies", { headers: { cookie: "beta=true" } }, env());
    expect(res.status).toBe(200);
    expect(await res.text()).toContain("You are currently in beta!");
  });

  it("rewrites / to the non-beta page otherwise", async () => {
    const res = await (await app()).request("/cookies", undefined, env());
    expect(await res.text()).toContain("You are not in beta.");
  });
});
