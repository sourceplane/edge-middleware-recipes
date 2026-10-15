// vercel/examples/edge-middleware/user-agent-based-rendering — middleware.ts
// and the pages/_viewport/{mobile,desktop} pages (both render components/Home).
//
// `userAgent(req)` from next/server is ua-parser-js, which Next bundles; the
// recipe uses the same package, so `device.type` is what Next would report.
import { Hono } from "hono";
import { html } from "hono/html";
import type { AppEnv } from "../env";
import { rewrite, userAgent } from "../lib/middleware";
import { page, type RecipeMeta } from "../lib/page";

const BASE = "/user-agent-based-rendering";

const app = new Hono<AppEnv>({ strict: false }).basePath(BASE);

// Set pathname were middleware will be executed
app.use("/", async (c) => {
  // Parse user agent
  const { device } = userAgent(c.req.raw);

  // Check the viewport
  const viewport = device.type === "mobile" ? "mobile" : "desktop";

  // Update the expected url
  const url = new URL(c.req.url);
  url.pathname = `${BASE}/_viewport/${viewport}`;

  // Return rewrited response
  return rewrite(app, c, url);
});

// components/Home.tsx, as pages/_viewport/mobile.tsx and pages/_viewport/desktop.tsx
app.get("/_viewport/:viewport{mobile|desktop}", (c) => {
  const viewport = c.req.param("viewport");
  return c.html(
    page(
      "User-Agent Based Rendering",
      html`<h1>User-Agent Based Rendering</h1>
        <p>
          Sometimes the desktop version of our application differs a lot from our mobile version,
          because the UI is different or because we load different scripts, styles, etc. We want to
          decide which page to load based on the
          <a href="https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/User-Agent">User-Agent</a>
          header without loading unnecessary assets for the current viewport.
        </p>
        <h2>Checking the User-Agent</h2>
        <p>In the middleware, we check the User-Agent header and rewrite to the correct page:</p>
        <pre>// Parse user agent
const { device } = userAgent(c.req.raw)

// Check the viewport
const viewport = device.type === 'mobile' ? 'mobile' : 'desktop'

// Update the expected url
url.pathname = \`/_viewport/\${viewport}\`

// Return rewrited response
return rewrite(app, c, url)</pre>
        <h2>Result</h2>
        <p>This page is using this strategy, try it out in different devices and you will see the message below changing accordingly:</p>
        <pre>This page was loaded on a <b>${viewport}</b> device.</pre>`,
      "user-agent-based-rendering",
    ),
  );
});

export const meta: RecipeMeta = {
  slug: "user-agent-based-rendering",
  title: "User-Agent based rendering",
  summary: "Parses the User-Agent and rewrites / to the mobile or the desktop page.",
  primitive: "userAgent(req) from next/server → ua-parser-js (the package Next bundles)",
  try: [
    "curl -s -A 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148' http://localhost:8787/user-agent-based-rendering | grep 'loaded on'",
    "curl -s http://localhost:8787/user-agent-based-rendering | grep 'loaded on'",
  ],
};

export default app;
