// vercel/examples/edge-middleware/query-params-filter — middleware.ts.
//
// As written: every query parameter that is not allowed is removed and the
// visitor is redirected to the clean URL (only when something changed, so the
// redirect cannot loop). `NextResponse.redirect(url)` is a 307 — Next's
// default — which `c.redirect(url, 307)` reproduces.
import { Hono } from "hono";
import { html } from "hono/html";
import type { AppEnv } from "../env";
import { page, type RecipeMeta } from "../lib/page";

const BASE = "/query-params-filter";

const allowedParams = ["allowed"];

const app = new Hono<AppEnv>({ strict: false }).basePath(BASE);

// matcher: '/'
app.use("/", async (c, next) => {
  const url = new URL(c.req.url);
  let changed = false;

  url.searchParams.forEach((_, key) => {
    if (!allowedParams.includes(key)) {
      url.searchParams.delete(key);
      changed = true;
    }
  });

  // Avoid infinite loop by only redirecting if the query
  // params were changed
  if (changed) {
    return c.redirect(url.toString(), 307);
    // It's also useful to do a rewrite instead of a redirect
    // return rewrite(app, c, url)
  }

  return next();
});

// pages/index.tsx
app.get("/", (c) =>
  c.html(
    page(
      "Query params filter",
      html`<h1>Query params filter</h1>
        <p>Any query param that's not <code>allowed</code> will be removed from the URL.</p>
        <p>Try <a href="${BASE}?a=b&amp;allowed=test">${BASE}?a=b&amp;allowed=test</a>.</p>
        <pre>query: ${new URL(c.req.url).search || "(none)"}</pre>`,
      "query-params-filter",
    ),
  ),
);

export const meta: RecipeMeta = {
  slug: "query-params-filter",
  title: "Query params filter",
  summary: "Strips every query parameter except allowed and redirects (307) to the clean URL.",
  primitive: "req.nextUrl + NextResponse.redirect → new URL(c.req.url) + c.redirect(url, 307)",
  try: ["curl -si 'http://localhost:8787/query-params-filter?a=b&allowed=test' | grep -iE '^(HTTP|location)'"],
};

export default app;
