import { html } from "hono/html";

export type Html = ReturnType<typeof html>;

/** The recipe registry entry the index page lists. */
export interface RecipeMeta {
  /** The upstream directory name — also the route prefix (`/<slug>`). */
  slug: string;
  title: string;
  /** What the middleware does. */
  summary: string;
  /** The Vercel primitive the upstream leans on, and its counterpart here. */
  primitive: string;
  /** curl lines that show the behaviour against `wrangler dev`. */
  try: string[];
}

export const UPSTREAM = "https://github.com/vercel/examples/tree/main/edge-middleware";

/** The one HTML shell every demo page uses (the upstream pages share `@vercel/examples-ui`'s). */
export function page(title: string, body: Html, slug?: string): Html {
  return html`<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>${title}</title>
    <style>
      body { font: 16px/1.5 system-ui, sans-serif; color: #111; background: #fafafa; margin: 0; }
      main { max-width: 760px; margin: 0 auto; padding: 2rem 1rem 1rem; }
      h1 { font-size: 1.75rem; margin: 0 0 1rem; }
      h2 { font-size: 1.2rem; margin: 2rem 0 0.5rem; }
      p { margin: 0.5rem 0; }
      pre { background: #111; color: #eee; padding: 0.75rem 1rem; border-radius: 8px; overflow: auto; font-size: 0.9rem; }
      code { font-family: ui-monospace, SFMono-Regular, Menlo, monospace; font-size: 0.95em; }
      .card { background: #fff; border: 1px solid #e5e5e5; border-radius: 8px; padding: 1rem; margin: 1rem 0; }
      .row { display: flex; justify-content: space-between; gap: 1rem; padding: 0.5rem 0; border-bottom: 1px solid #eee; }
      .row:last-child { border-bottom: 0; }
      .button { display: inline-block; padding: 0.4rem 0.9rem; margin: 0.25rem 0.5rem 0.25rem 0; border: 1px solid #111; border-radius: 6px; text-decoration: none; color: #111; }
      .button.primary { background: #111; color: #fff; }
      table { border-collapse: collapse; width: 100%; }
      td, th { text-align: left; vertical-align: top; padding: 0.5rem; border-bottom: 1px solid #eee; }
      footer { max-width: 760px; margin: 0 auto; padding: 1rem; color: #666; font-size: 0.9rem; }
      a { color: #0070f3; }
    </style>
  </head>
  <body>
    <main>${body}</main>
    <footer>
      <a href="/">← all recipes</a>${slug ? html` · upstream: <a href="${UPSTREAM}/${slug}">vercel/examples/edge-middleware/${slug}</a>` : ""}
    </footer>
  </body>
</html>`;
}
