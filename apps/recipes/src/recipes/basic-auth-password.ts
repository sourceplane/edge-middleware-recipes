// vercel/examples/edge-middleware/basic-auth-password — middleware.ts + pages/api/auth.ts.
//
// The upstream compares against a user and password written into the
// middleware ('4dmin' / 'testpwd123'); here the pair is the Worker secrets
// BASIC_AUTH_USER / BASIC_AUTH_PASSWORD (.dev.vars locally, `wrangler secret
// put` per environment). Everything else is as written: a missing or wrong
// Authorization header rewrites to /api/auth, which answers 401 with the
// WWW-Authenticate challenge.
import { Hono } from "hono";
import { html } from "hono/html";
import type { AppEnv } from "../env";
import { rewrite } from "../lib/middleware";
import { page, type RecipeMeta } from "../lib/page";

const BASE = "/basic-auth-password";

const app = new Hono<AppEnv>({ strict: false }).basePath(BASE);

// matcher: ['/', '/index']
app.on("ALL", ["/", "/index"], async (c, next) => {
  const basicAuth = c.req.header("authorization");
  const url = new URL(c.req.url);

  if (basicAuth) {
    const authValue = basicAuth.split(" ")[1] ?? "";
    const [user, pwd] = atob(authValue).split(":");

    if (user === c.env.BASIC_AUTH_USER && pwd === c.env.BASIC_AUTH_PASSWORD) {
      return next();
    }
  }
  url.pathname = `${BASE}/api/auth`;

  return rewrite(app, c, url);
});

// pages/api/auth.ts
app.all("/api/auth", () => {
  return new Response("Auth Required.", {
    status: 401,
    headers: { "WWW-authenticate": 'Basic realm="Secure Area"' },
  });
});

// pages/index.tsx
const index = page(
  "Password-protected page demo",
  html`<h1>Password-protected page demo</h1>
    <p>You are in. The pair that let you through is the Worker's <code>BASIC_AUTH_USER</code> / <code>BASIC_AUTH_PASSWORD</code> secrets (see <code>.dev.vars.example</code>).</p>`,
  "basic-auth-password",
);
app.get("/", (c) => c.html(index));
app.get("/index", (c) => c.html(index));

export const meta: RecipeMeta = {
  slug: "basic-auth-password",
  title: "Basic auth password",
  summary: "Checks the Authorization: Basic header against a user and password; anything else is rewritten to a 401 with a WWW-Authenticate challenge.",
  primitive: "hard-coded credentials → Worker secrets BASIC_AUTH_USER / BASIC_AUTH_PASSWORD",
  try: [
    "curl -si http://localhost:8787/basic-auth-password | head -3",
    "curl -si -u 4dmin:testpwd123 http://localhost:8787/basic-auth-password | head -1   # with .dev.vars from .dev.vars.example",
  ],
};

export default app;
