// vercel/examples/edge-middleware/cookies — middleware.ts and the
// pages/{beta,non-beta} pages.
//
// The middleware is as written: parse the `beta` cookie and rewrite `/` to
// `/beta` or `/non-beta`. Upstream's pages flip the cookie with js-cookie and
// reload; here the Opt in / Opt out buttons are links that set it and
// redirect back.
import { Hono } from "hono";
import { getCookie, setCookie } from "hono/cookie";
import { html } from "hono/html";
import type { AppEnv } from "../env";
import { rewrite } from "../lib/middleware";
import { page, type RecipeMeta } from "../lib/page";

const BASE = "/cookies";

const app = new Hono<AppEnv>({ strict: false }).basePath(BASE);

// matcher: '/'
app.use("/", async (c) => {
  // Parse the cookie
  const isInBeta = JSON.parse(getCookie(c, "beta") || "false");

  // Update url pathname
  const url = new URL(c.req.url);
  url.pathname = `${BASE}/${isInBeta ? "beta" : "non-beta"}`;

  // Rewrite to url
  return rewrite(app, c, url);
});

// pages/beta.tsx
app.get("/beta", (c) =>
  c.html(
    page(
      "Cookies example",
      html`<h1>Cookies example</h1>
        <p>You are currently in beta!</p>
        <p><a class="button" href="${BASE}/opt-out">Opt out</a></p>`,
      "cookies",
    ),
  ),
);

// pages/non-beta.tsx
app.get("/non-beta", (c) =>
  c.html(
    page(
      "Cookies example",
      html`<h1>Cookies example</h1>
        <p>You are not in beta.</p>
        <p><a class="button primary" href="${BASE}/opt-in">Opt in</a></p>`,
      "cookies",
    ),
  ),
);

// Cookies.set('beta', 'true' | 'false') + router.reload()
app.get("/opt-in", (c) => {
  setCookie(c, "beta", "true", { path: "/" });
  return c.redirect(BASE);
});
app.get("/opt-out", (c) => {
  setCookie(c, "beta", "false", { path: "/" });
  return c.redirect(BASE);
});

export const meta: RecipeMeta = {
  slug: "cookies",
  title: "Cookies",
  summary: "Reads the beta cookie and rewrites / to the beta or the non-beta page without changing the URL.",
  primitive: "req.cookies.get → getCookie (hono/cookie); NextResponse.rewrite → in-process dispatch",
  try: [
    "curl -s http://localhost:8787/cookies | grep beta",
    "curl -s -b beta=true http://localhost:8787/cookies | grep beta",
  ],
};

export default app;
