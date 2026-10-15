import { describe, expect, it } from "vitest";
import { app, env, withCf } from "./helpers";

describe("geolocation", () => {
  it("renders the visitor's country, city and region from request.cf with the currency and languages", async () => {
    const req = withCf("http://localhost/geolocation", { country: "DE", city: "Berlin", regionCode: "BE", timezone: "Europe/Berlin" });
    const res = await (await app()).request(req, undefined, env());
    expect(res.status).toBe(200);
    const body = await res.text();
    expect(body).toContain("Berlin");
    expect(body).toContain("cf.country:    DE");
    expect(body).toContain("Euro");
    expect(body).toContain("German");
    expect(body).toContain("Europe/Berlin");
  });

  it("defaults to San Francisco, US when the request carries no cf", async () => {
    const res = await (await app()).request("/geolocation", undefined, env());
    const body = await res.text();
    expect(body).toContain("San Francisco");
    expect(body).toContain("United States dollar");
  });
});
