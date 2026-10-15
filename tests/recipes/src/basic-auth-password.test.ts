import { describe, expect, it } from "vitest";
import { app, env } from "./helpers";

const secrets = env({ BASIC_AUTH_USER: "4dmin", BASIC_AUTH_PASSWORD: "testpwd123" });

describe("basic-auth-password", () => {
  it("challenges with 401 and WWW-Authenticate when the header is missing or wrong", async () => {
    const res = await (await app()).request("/basic-auth-password", undefined, secrets);
    expect(res.status).toBe(401);
    expect(res.headers.get("www-authenticate")).toBe('Basic realm="Secure Area"');
    expect(await res.text()).toBe("Auth Required.");

    const wrong = await (await app()).request(
      "/basic-auth-password",
      { headers: { authorization: `Basic ${btoa("4dmin:nope")}` } },
      secrets,
    );
    expect(wrong.status).toBe(401);
  });

  it("lets the right user:password through", async () => {
    const res = await (await app()).request(
      "/basic-auth-password",
      { headers: { authorization: `Basic ${btoa("4dmin:testpwd123")}` } },
      secrets,
    );
    expect(res.status).toBe(200);
    expect(await res.text()).toContain("Password-protected page demo");
  });
});
