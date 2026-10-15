import { describe, expect, it } from "vitest";
import { app, env } from "./helpers";

describe("ab-testing-simple", () => {
  it("assigns a bucket cookie on /home and rewrites to that bucket's page", async () => {
    const res = await (await app()).request("/ab-testing-simple/home", undefined, env());
    expect(res.status).toBe(200);
    const cookie = res.headers.get("set-cookie") ?? "";
    const m = /^bucket-home=([abc]);/.exec(cookie);
    expect(m).not.toBeNull();
    expect(await res.text()).toContain(`bucket ${m![1]!.toUpperCase()}`);
  });

  it("keeps a valid bucket from the cookie and sets none", async () => {
    const res = await (await app()).request("/ab-testing-simple/marketing", { headers: { cookie: "bucket-marketing=original" } }, env());
    expect(res.status).toBe(200);
    expect(res.headers.get("set-cookie")).toBeNull();
    expect(await res.text()).toContain("the original marketing page");
  });
});
