// vercel/examples/edge-middleware/add-header — middleware.ts.
//
// `NextResponse.next()` then `response.headers.set(...)` is Hono's
// `await next()` then `c.res.headers.set(...)`: the response the route
// produced, with one more header.
import { Hono } from "hono";
import { html } from "hono/html";
import type { AppEnv } from "../env";
import { page, type RecipeMeta } from "../lib/page";

const BASE = "/add-header";

const app = new Hono<AppEnv>({ strict: false }).basePath(BASE);

app.use("*", async (c, next) => {
  // Store the response so we can modify its headers
  await next();

  // Set custom header
  c.res.headers.set("x-modified-edge", "true");

  // Return response
});

// pages/index.tsx
app.get("/", (c) =>
  c.html(
    page(
      "Adding headers at the edge",
      html`<h1>Adding headers at the edge</h1>
        <p>
          In some cases we might want to add or modify the headers from an incoming request for
          different reasons, AB testing, personalization, analytics, etc. To have access to the
          tentative response we <code>await next()</code> and then modify its headers:
        </p>
        <pre>// Store the response so we can modify its headers
await next()

// Set custom header
c.res.headers.set(
  "x-modified-edge",
  "true"
)</pre>
        <p>Open the network tab in devtools to see the response headers</p>
        <pre><strong>x-modified-edge: </strong>true</pre>`,
      "add-header",
    ),
  ),
);

export const meta: RecipeMeta = {
  slug: "add-header",
  title: "Add header",
  summary: "Adds x-modified-edge: true to every response.",
  primitive: "NextResponse.next() + response.headers.set → await next() + c.res.headers.set",
  try: ["curl -si http://localhost:8787/add-header | grep -i x-modified-edge"],
};

export default app;
