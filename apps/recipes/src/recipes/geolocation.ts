// vercel/examples/edge-middleware/geolocation — middleware.ts + pages/index.tsx.
//
// `geolocation(req)` from `@vercel/functions` becomes `request.cf` (country,
// city, regionCode, latitude, longitude, timezone, colo); the middleware's
// body and comments are the upstream's. Next reaches `pages/index.tsx` at
// `/index` as well as `/`, so the rewrite that upstream aims back at `/` (with
// the query the page reads) aims at `/index` here — the same page, and the
// rewritten request does not run the middleware again.
import { Hono } from "hono";
import { html } from "hono/html";
import type { AppEnv } from "../env";
import { geolocation, rewrite } from "../lib/middleware";
import { page, type RecipeMeta } from "../lib/page";
import countriesJson from "./geolocation/countries.json";

interface Country {
  cca2: string;
  currencies: Record<string, { name: string; symbol: string }>;
  languages: Record<string, string>;
}

const countries = countriesJson as unknown as Country[];
const BASE = "/geolocation";

const app = new Hono<AppEnv>({ strict: false }).basePath(BASE);

// run only on homepage
app.use("/", async (c) => {
  const url = new URL(c.req.url);
  const geo = geolocation(c.req.raw);
  const country = geo.country || "US";
  const city = geo.city || "San Francisco";
  const region = geo.countryRegion || "CA";

  // the upstream assumes every country code is in the table; a code it does
  // not know (Cloudflare's "T1" for Tor, "XX") falls back to the default
  const countryInfo =
    countries.find((x) => x.cca2 === country) ?? (countries.find((x) => x.cca2 === "US") as Country);

  const currencyCode = Object.keys(countryInfo.currencies)[0] ?? "";
  const currency = countryInfo.currencies[currencyCode] ?? { name: "", symbol: "" };
  const languages = Object.values(countryInfo.languages).join(", ");

  url.searchParams.set("country", country);
  url.searchParams.set("city", city);
  url.searchParams.set("region", region);
  url.searchParams.set("currencyCode", currencyCode);
  url.searchParams.set("currencySymbol", currency.symbol);
  url.searchParams.set("name", currency.name);
  url.searchParams.set("languages", languages);
  // the fields Cloudflare adds beyond Vercel's x-vercel-ip-* headers
  url.searchParams.set("latitude", geo.latitude ?? "");
  url.searchParams.set("longitude", geo.longitude ?? "");
  url.searchParams.set("timezone", geo.timezone ?? "");
  url.searchParams.set("colo", geo.region ?? "");

  url.pathname = `${BASE}/index`;
  return rewrite(app, c, url);
});

// pages/index.tsx — forward properties from the middleware (the query)
app.get("/index", (c) => {
  const q = c.req.query();
  const country = q.country ?? "";
  return c.html(
    page(
      "Geolocation",
      html`<h1>Geolocation</h1>
        <p>Show localized content based on <code>request.cf</code></p>
        <p>
          <a href="https://developers.cloudflare.com/workers/runtime-apis/request/#incomingrequestcfproperties">View Documentation →</a>
        </p>
        <div class="card">
          <div class="row">
            <span><img alt="${country} flag" src="https://flagcdn.com/96x72/${country.toLowerCase()}.png" width="32" height="24" /></span>
            <span style="margin-right:auto"><strong>${q.name}</strong><br /><span style="color:#555">${q.city}</span></span>
            <span>${country}</span>
          </div>
          <div class="row"><strong>Languages</strong><span>${q.languages}</span></div>
          <div class="row"><strong>Currency</strong><span>${q.currencyCode} ${q.currencySymbol}</span></div>
          <h2>Geolocation (request.cf)</h2>
          <pre>cf.city:       ${q.city}
cf.regionCode: ${q.region}
cf.country:    ${country}
cf.latitude:   ${q.latitude}
cf.longitude:  ${q.longitude}
cf.timezone:   ${q.timezone}
cf.colo:       ${q.colo}</pre>
        </div>`,
      "geolocation",
    ),
  );
});

export const meta: RecipeMeta = {
  slug: "geolocation",
  title: "Geolocation",
  summary: "Looks up the visitor's country, city and region, adds the currency and languages from a country table, and rewrites to a page that renders them.",
  primitive: "geolocation(req) from @vercel/functions → request.cf",
  try: ["curl -s http://localhost:8787/geolocation | grep cf."],
};

export default app;
