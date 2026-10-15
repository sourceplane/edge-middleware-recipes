// vercel/examples/edge-middleware/rate-limit-any-framework — middleware.js,
// index.html and blocked.html.
//
// Upstash's `Ratelimit.slidingWindow(5, '10 s')` over Vercel KV becomes the
// Workers Rate Limiting binding (`ratelimits` in wrangler.jsonc: 5 per 10 s,
// per key, per Cloudflare location). It is GA (September 2025), runs under
// `wrangler dev`, adds no network round trip, and returns only `success` —
// the `limit`, `reset` and `remaining` the upstream also destructures are not
// available; its decision only ever used `success`. `ipAddress(request)` is
// CF-Connecting-IP.
import { Hono } from "hono";
import { html } from "hono/html";
import type { AppEnv } from "../env";
import { ipAddress } from "../lib/middleware";
import { page, type RecipeMeta } from "../lib/page";

const BASE = "/rate-limit-any-framework";

const app = new Hono<AppEnv>({ strict: false }).basePath(BASE);

// Define which routes you want to rate limit
app.use("/", async (c, next) => {
  // You could alternatively limit based on user ID or similar
  const ip = ipAddress(c.req.raw) || "127.0.0.1";
  const { success } = await c.env.RATE_LIMITER.limit({ key: ip });

  return success ? next() : Response.redirect(new URL(`${BASE}/blocked.html`, c.req.url));
});

// index.html
app.get("/", (c) =>
  c.html(
    page(
      "Workers Rate Limit",
      html`<h1>Workers Rate Limit</h1>
        <p>
          This recipe shows how to add rate limiting to any application with the
          <a href="https://developers.cloudflare.com/workers/runtime-apis/bindings/rate-limit/">Workers Rate Limiting binding</a>
          in a Cloudflare Worker.
        </p>
        <p>
          It rate limits based on the visitor IP address. You are successfully viewing the
          <code>/</code> route. Try refreshing a few times (5) and you will be rate limited and
          redirected to <code>/blocked.html</code>.
        </p>`,
      "rate-limit-any-framework",
    ),
  ),
);

// blocked.html
app.get("/blocked.html", (c) =>
  c.html(
    page(
      "Workers Rate Limiting",
      html`<h1>Workers Rate Limiting</h1>
        <p>
          You are now rate limited after exceeding 5 requests in 10 seconds based on your IP
          address. Please wait 10 seconds and you can return to the
          <a href="${BASE}"><code>/</code> route</a>.
        </p>`,
      "rate-limit-any-framework",
    ),
  ),
);

export const meta: RecipeMeta = {
  slug: "rate-limit-any-framework",
  title: "Rate limit (any framework)",
  summary: "Allows 5 requests per 10 seconds per IP and redirects the sixth to /blocked.html.",
  primitive: "@upstash/ratelimit over Vercel KV → the Workers Rate Limiting binding (ratelimits)",
  try: ["for i in 1 2 3 4 5 6; do curl -s -o /dev/null -w '%{http_code} ' http://localhost:8787/rate-limit-any-framework; done; echo"],
};

export default app;
