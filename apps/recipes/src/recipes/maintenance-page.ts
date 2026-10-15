// vercel/examples/edge-middleware/maintenance-page — middleware.ts and the
// pages/{big-promo,maintenance,missing-global-config} pages.
//
// Upstream reads `isInMaintenanceMode` from Edge Config through the
// GLOBAL_CONFIG connection string. Here the flag is the MAINTENANCE_MODE var
// in wrangler.jsonc (per environment); a flag that has to flip without a
// deploy belongs in a KV namespace read the same way. A missing var
// reproduces the upstream's "missing config" dialog.
import { Hono } from "hono";
import { html } from "hono/html";
import type { AppEnv } from "../env";
import { rewrite } from "../lib/middleware";
import { page, type RecipeMeta } from "../lib/page";

const BASE = "/maintenance-page";

const app = new Hono<AppEnv>({ strict: false }).basePath(BASE);

// matcher: ['/big-promo']
app.use("/big-promo", async (c, next) => {
  const url = new URL(c.req.url);

  if (c.env.MAINTENANCE_MODE === undefined) {
    url.pathname = `${BASE}/missing-config`;
    return rewrite(app, c, url);
  }

  // Check whether the maintenance page should be shown
  const isInMaintenanceMode = c.env.MAINTENANCE_MODE === "true";

  // If is in maintenance mode, point the url pathname to the maintenance page
  if (isInMaintenanceMode) {
    url.pathname = `${BASE}/maintenance`;

    // Rewrite to the url
    return rewrite(app, c, url);
  }

  return next();
});

// pages/big-promo.tsx
app.get("/big-promo", (c) =>
  c.html(
    page(
      "Something big is coming",
      html`<h1>Something big is coming 😶</h1>
        <p>But its not ready yet, refresh the page to see if its here already.</p>
        <p><a class="button primary" href="${BASE}/big-promo">Refresh</a></p>`,
      "maintenance-page",
    ),
  ),
);

// pages/maintenance.tsx
app.get("/maintenance", (c) =>
  c.html(
    page(
      "Under Maintenance",
      html`<h1>Under Maintenance</h1>
        <p>You can try to refresh the page to see if the issue is resolved.</p>
        <p><a class="button primary" href="${BASE}/big-promo">Refresh</a></p>`,
      "maintenance-page",
    ),
  ),
);

// pages/missing-global-config.tsx
app.get("/missing-config", (c) =>
  c.html(
    page(
      "Incomplete Environment Variables Setup",
      html`<div class="card">
        <h1>Incomplete Environment Variables Setup</h1>
        <p>Follow these steps to finish the setup of this recipe:</p>
        <ol>
          <li>Set <code>MAINTENANCE_MODE</code> to <code>"true"</code> or <code>"false"</code> under <code>vars</code> in <code>apps/recipes/wrangler.jsonc</code> (top level and in every <code>env.*</code> section)</li>
          <li>Restart <code>wrangler dev</code>, or redeploy</li>
        </ol>
        <p>Then reload the page and this dialog will go away if your setup is correct.</p>
      </div>`,
      "maintenance-page",
    ),
  ),
);

// pages/index.tsx
app.get("/", (c) =>
  c.html(
    page(
      "Maintenance page",
      html`<h1>Maintenance page</h1>
        <p>Open <a href="${BASE}/big-promo">/big-promo</a>. With <code>MAINTENANCE_MODE</code> set to <code>"true"</code> it is the maintenance page instead; unset, the setup dialog.</p>`,
      "maintenance-page",
    ),
  ),
);

export const meta: RecipeMeta = {
  slug: "maintenance-page",
  title: "Maintenance page",
  summary: "Serves the maintenance page for /big-promo while a flag is on, the real page when it is off, and a setup dialog when the flag is missing.",
  primitive: "Edge Config get('isInMaintenanceMode') → the MAINTENANCE_MODE var",
  try: [
    "curl -s http://localhost:8787/maintenance-page/big-promo | grep -E '<h1>'",
    "# flip: MAINTENANCE_MODE \"true\" in wrangler.jsonc vars, or wrangler dev --var MAINTENANCE_MODE:true",
  ],
};

export default app;
