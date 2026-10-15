// edge-middleware-recipes: Vercel's Edge Middleware examples as one Cloudflare
// Worker. `/` lists the recipes; each lives under its own path (src/recipes).
import { Hono } from "hono";
import { html } from "hono/html";
import type { AppEnv } from "./env";
import { page, UPSTREAM } from "./lib/page";
import { mount, recipes } from "./recipes";

const app = new Hono<AppEnv>({ strict: false });

app.get("/", (c) =>
  c.html(
    page(
      "Edge Middleware recipes",
      html`<h1>Edge Middleware recipes</h1>
        <p>
          Vercel's <a href="${UPSTREAM}">Edge Middleware examples</a>, each ported as a recipe in
          this one Cloudflare Worker (Hono-routed). Open a recipe, or run the
          <code>curl</code> lines against <code>wrangler dev</code>.
        </p>
        <table>
          <thead>
            <tr><th>Recipe</th><th>What it does</th><th>Vercel → Cloudflare</th></tr>
          </thead>
          <tbody>
            ${recipes.map(
              (r) => html`<tr>
                <td><a href="/${r.slug}"><strong>${r.title}</strong></a><br /><code>/${r.slug}</code></td>
                <td>${r.summary}</td>
                <td>${r.primitive}<br /><a href="${UPSTREAM}/${r.slug}">upstream</a></td>
              </tr>`,
            )}
          </tbody>
        </table>
        <h2>Try them</h2>
        ${recipes.map((r) => html`<pre>${r.try.join("\n")}</pre>`)}`,
    ),
  ),
);

mount(app);

export default app;
