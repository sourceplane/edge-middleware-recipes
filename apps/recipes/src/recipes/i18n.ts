// vercel/examples/edge-middleware/i18n — middleware.ts + pages/[locale]/[country].tsx,
// lib/{api,constants,types}.ts kept beside it (./i18n/*).
//
// The locale is the first entry of Accept-Language, the country comes from
// geolocation (request.cf here), and `/` is rewritten to `/<locale>/<country>`,
// which renders the dictionary for that locale. The flag that upstream serves
// from public/flags/*.svg comes from flagcdn.com here (a plain Worker ships no
// static assets).
import { Hono } from "hono";
import { html } from "hono/html";
import type { AppEnv } from "../env";
import { geolocation, rewrite } from "../lib/middleware";
import { page, type RecipeMeta } from "../lib/page";
import api from "./i18n/api";

const BASE = "/i18n";

const app = new Hono<AppEnv>({ strict: false }).basePath(BASE);

// only run middleware on home page
app.use("/", async (c) => {
  const country = geolocation(c.req.raw).country?.toLowerCase() || "us";
  const locale = c.req.header("accept-language")?.split(",")?.[0] || "en-US";

  // Rewrite the path (`/`) to the localized page (pages/[locale]/[country])
  const url = new URL(c.req.url);
  url.pathname = `${BASE}/${locale}/${country}`;
  return rewrite(app, c, url);
});

// pages/[locale]/[country].tsx
app.get("/:locale/:country", async (c) => {
  const { locale, country } = c.req.param();
  // Get dictionary
  const dictionary = await api.dictionaries.fetch(locale);
  return c.html(
    page(
      dictionary.title,
      html`<h1>${dictionary.title}</h1>
        <p>${dictionary.subtitle}</p>
        <p><a href="https://developers.cloudflare.com/workers/runtime-apis/request/#incomingrequestcfproperties">${dictionary.link} →</a></p>
        <div class="card">
          <p><img alt="Country flag" src="https://flagcdn.com/96x72/${country.toLowerCase()}.png" width="64" height="48" /></p>
          <p><em>${dictionary.greet}</em></p>
          <pre>locale:  ${locale}
country: ${country}</pre>
        </div>`,
      "i18n",
    ),
  );
});

export const meta: RecipeMeta = {
  slug: "i18n",
  title: "i18n",
  summary: "Picks the locale from Accept-Language and the country from the visitor's location, then rewrites / to /<locale>/<country> and renders that locale's dictionary.",
  primitive: "geolocation(req) → request.cf; NextResponse.rewrite → in-process dispatch",
  try: [
    "curl -s -H 'Accept-Language: fr' http://localhost:8787/i18n | grep -E 'Bonjour|locale'",
    "curl -s -H 'Accept-Language: es' http://localhost:8787/i18n | grep -E 'Hola|locale'",
  ],
};

export default app;
