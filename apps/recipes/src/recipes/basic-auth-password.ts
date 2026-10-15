// vercel/examples/edge-middleware/basic-auth-password — middleware.ts + pages/api/auth.ts.
//
// The upstream compares against a user and password written into the
// middleware ('4dmin' / 'testpwd123'); here the pair is the Worker secrets
// BASIC_AUTH_USER / BASIC_AUTH_PASSWORD (.dev.vars locally, `wrangler secret
// put` per environment). Everything else is as written: a missing or wrong
// Authorization header rewrites to /api/auth, which answers 401 with the
// WWW-Authenticate challenge.
//
// Not upstream: a fresh deploy has no secrets, and with none set nobody could
// ever pass the challenge. So until both are set the protected page rewrites
// to /missing-config — a 503 that says how to set them — instead of
// challenging forever. Nothing behind the check is served either way.
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

  if (!c.env.BASIC_AUTH_USER || !c.env.BASIC_AUTH_PASSWORD) {
    url.pathname = `${BASE}/missing-config`;
    return rewrite(app, c, url);
  }

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

// The setup dialog, after maintenance-page's pages/missing-global-config.tsx.
app.all("/missing-config", (c) =>
  c.html(
    page(
      "Incomplete Secrets Setup",
      html`<div class="card">
        <h1>Incomplete Secrets Setup</h1>
        <p>This recipe checks a user and password, and this deployment has none set yet, so nothing can pass the check. Set both Worker secrets for the environment:</p>
        <ol>
          <li>With Orun, pushed to the Worker on its next deploy: <code>orun secrets set BASIC_AUTH_USER --env &lt;stage|prod&gt;</code>, then the same for <code>BASIC_AUTH_PASSWORD</code></li>
          <li>Or directly: <code>pnpm exec wrangler secret put BASIC_AUTH_USER --env &lt;stage|prod&gt;</code> in <code>apps/recipes</code>, then the same for <code>BASIC_AUTH_PASSWORD</code></li>
          <li>Locally, copy <code>apps/recipes/.dev.vars.example</code> to <code>.dev.vars</code> and restart <code>wrangler dev</code></li>
        </ol>
        <p>Then reload the page: it asks for the user and password instead.</p>
      </div>`,
      "basic-auth-password",
    ),
    503,
  ),
);

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
    "curl -si http://localhost:8787/basic-auth-password | head -3   # 503 and the setup steps until the secrets are set",
    "curl -si -u 4dmin:testpwd123 http://localhost:8787/basic-auth-password | head -1   # with .dev.vars from .dev.vars.example",
  ],
};

export default app;
