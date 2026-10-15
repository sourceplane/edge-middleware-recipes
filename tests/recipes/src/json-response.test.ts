import { describe, expect, it } from "vitest";
import { app, env } from "./helpers";

describe("json-response", () => {
  it("answers / with the JSON body from the middleware", async () => {
    const res = await (await app()).request("/json-response", undefined, env());
    expect(res.status).toBe(200);
    expect(res.headers.get("content-type")).toMatch(/^application\/json/);
    expect(await res.json()).toEqual({ message: "hello world!" });
  });
});
