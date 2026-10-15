import { describe, expect, it } from "vitest";
import { app, env } from "./helpers";

describe("add-header", () => {
  it("adds x-modified-edge: true to the response", async () => {
    const res = await (await app()).request("/add-header", undefined, env());
    expect(res.status).toBe(200);
    expect(res.headers.get("x-modified-edge")).toBe("true");
  });
});
