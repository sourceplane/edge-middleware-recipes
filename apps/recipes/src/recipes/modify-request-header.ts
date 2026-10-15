// vercel/examples/edge-middleware/modify-request-header — middleware.ts and
// pages/index.tsx (which prints the request headers it received).
//
// `NextResponse.next({ request: { headers } })` runs the page with the new
// request headers. A Worker's incoming Request is immutable, so the page is
// dispatched a fresh Request carrying the modified headers (`rewrite(pages,
// c, url, { headers })`); the page then reads them as any handler would.
import { Hono } from "hono";
import { html } from "hono/html";
import type { AppEnv } from "../env";
import { rewrite } from "../lib/middleware";
import { page, type RecipeMeta } from "../lib/page";

const BASE = "/modify-request-header";

// pages/index.tsx — getServerSideProps forwards ctx.req.headers to the page
const pages = new Hono<AppEnv>({ strict: false }).basePath(BASE);
pages.get("/", (c) =>
  c.html(
    page(
      "Modifying request headers in middleware",
      html`<h1>Modifying request headers in middleware</h1>
        <p>
          In some cases we might want to add, modify, or delete request headers from clients to
          change behavior or pass data to the route. The middleware clones the request headers
          with the <a href="https://developer.mozilla.org/en-US/docs/Web/API/Headers">Headers API</a>
          and dispatches the route with them.
        </p>
        <p>Request headers as the route received them:</p>
        <pre><strong>x-hello-from-middleware1: </strong>${c.req.header("x-hello-from-middleware1")}
<strong>x-hello-from-middleware2: </strong>${c.req.header("x-hello-from-middleware2")}
<strong>user-agent: </strong>${c.req.header("user-agent")}
<strong>x-from-client: </strong>${c.req.header("x-from-client") ?? "(deleted)"}</pre>`,
      "modify-request-header",
    ),
  ),
);

const app = new Hono<AppEnv>({ strict: false }).basePath(BASE);

app.all("*", async (c) => {
  // Clone the request headers
  // You can modify them with headers API: https://developer.mozilla.org/en-US/docs/Web/API/Headers
  const requestHeaders = new Headers(c.req.raw.headers);

  // Add new request headers
  requestHeaders.set("x-hello-from-middleware1", "hello");
  requestHeaders.set("x-hello-from-middleware2", "world!");

  // Update an existing request header
  requestHeaders.set("user-agent", "New User Agent overriden by middleware!");

  // Delete an existing request header
  requestHeaders.delete("x-from-client");

  // NextResponse.next({ request: { headers: requestHeaders } })
  return rewrite(pages, c, c.req.url, { headers: requestHeaders });
});

export const meta: RecipeMeta = {
  slug: "modify-request-header",
  title: "Modify request header",
  summary: "Adds two request headers, overrides User-Agent and deletes x-from-client before the route runs; the page prints what it received.",
  primitive: "NextResponse.next({ request: { headers } }) → dispatch a new Request with the headers",
  try: ["curl -s -H 'x-from-client: secret' http://localhost:8787/modify-request-header | grep -E 'middleware|user-agent|client'"],
};

export default app;
