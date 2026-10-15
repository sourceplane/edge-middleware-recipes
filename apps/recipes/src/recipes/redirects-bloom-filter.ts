// vercel/examples/edge-middleware/redirects-bloom-filter — middleware.ts,
// app/api/redirects/route.ts and the app/{page,blog/[slug]} pages; the
// redirects/ directory (50,000 redirects, the generated Bloom filter, the
// generator) is kept at ./redirects-bloom-filter and scripts/.
//
// The Bloom filter rules most paths out without touching the table. On a hit,
// upstream fetches its own /api/redirects Route Handler so the 5 MB table
// stays out of the middleware bundle. A Worker cannot fetch itself, and here
// both live in one bundle, so the Route Handler is a function the middleware
// calls in-process — the table is a dynamic import, which esbuild keeps lazy:
// it is parsed on the first hit, not when the isolate starts. The route is
// still served at /api/redirects, as upstream.
import { Hono } from "hono";
import { html } from "hono/html";
import { ScalableBloomFilter } from "bloom-filters";
import type { AppEnv } from "../env";
import { page, type RecipeMeta } from "../lib/page";
import GeneratedBloomFilter from "./redirects-bloom-filter/redirects-bloom-filter.json";
import type { RedirectEntries, RedirectEntry } from "./redirects-bloom-filter/types";

const BASE = "/redirects-bloom-filter";

// Initialize bloom filter from a generated JSON file
const bloomFilter: ScalableBloomFilter = ScalableBloomFilter.fromJSON(GeneratedBloomFilter as unknown as JSON);

// app/api/redirects/route.ts — the lookup, as a function
async function findRedirect(pathname: string): Promise<RedirectEntry | undefined> {
  const { default: redirects } = await import("./redirects-bloom-filter/redirects.json");
  // Get the redirect entry from the redirects.json file
  return (redirects as RedirectEntries)[pathname];
}

const app = new Hono<AppEnv>({ strict: false }).basePath(BASE);

// matcher: everything but /api (upstream also excludes _next/* and favicon.ico)
app.use("*", async (c, next) => {
  // Get the path for the incoming request — the table's keys are app-relative
  const pathname = new URL(c.req.url).pathname.slice(BASE.length) || "/";
  if (pathname.startsWith("/api")) return next();

  // Check if the path is in the bloom filter
  if (bloomFilter.has(pathname)) {
    // Forward the pathname to the Route Handler
    try {
      // Fetch redirect data from the Route Handler
      const redirectEntry: RedirectEntry | undefined = await findRedirect(pathname);

      if (redirectEntry) {
        // Determine the status code
        const statusCode = redirectEntry.permanent ? 308 : 307;

        // Redirect to the destination
        return c.redirect(redirectEntry.target, statusCode);
      }
    } catch (error) {
      console.error(error);
    }
  }

  // No redirect found, continue the request without redirecting
  await next();
});

// app/api/redirects/route.ts
app.get("/api/redirects", async (c) => {
  const pathname = c.req.query("pathname");
  if (!pathname) {
    return new Response("Bad Request", { status: 400 });
  }

  const redirect = await findRedirect(pathname);

  // Account for bloom filter false positives
  if (!redirect) {
    return new Response("No redirect", { status: 400 });
  }

  // Return the redirect entry
  return c.json(redirect);
});

// app/blog/[slug]/page.tsx
app.get("/blog/:slug", (c) =>
  c.html(
    page(
      "Blog Post",
      html`<h1>Blog Post</h1>
        <p>/${c.req.param("slug")}.</p>`,
      "redirects-bloom-filter",
    ),
  ),
);

// app/page.tsx
const redirectingLinks = [
  { href: "/blog/should-redirect-to-google", text: "Redirect to Google" },
  { href: "/blog/should-redirect-to-yahoo", text: "Redirect to Yahoo" },
  { href: "/blog/should-redirect-to-1", text: "Redirect to Google with query string 1" },
  { href: "/blog/should-redirect-to-1000", text: "Redirect to Google with query string 1000" },
  { href: "/blog/should-redirect-to-9999", text: "Redirect to Google with query string 9999" },
];
const regularLinks = [{ href: "/blog/should-render-basic-blog-post", text: "Render basic blog post" }];

app.get("/", (c) =>
  c.html(
    page(
      "Redirects with Bloom Filter",
      html`<h1>Redirects with Bloom Filter</h1>
        <p>
          This recipe shows how you can use a
          <a href="https://en.wikipedia.org/wiki/Bloom_filter">Bloom Filter</a> in a Worker to
          improve the lookup performance of a large list of redirects (50,000).
        </p>
        <p>
          Although this recipe stores the redirects in a JSON file bundled with the Worker, you can
          also use Workers KV or D1. Before using it, measure which is more performant: 1. Directly
          querying your data or 2. Using a Bloom Filter to check if the redirect exists before
          querying the data.
        </p>
        <h2>Redirecting links</h2>
        <ul>
          ${redirectingLinks.map((l) => html`<li><a href="${BASE}${l.href}">${l.text}</a></li>`)}
        </ul>
        <h2>Regular links</h2>
        <ul>
          ${regularLinks.map((l) => html`<li><a href="${BASE}${l.href}">${l.text}</a></li>`)}
        </ul>`,
      "redirects-bloom-filter",
    ),
  ),
);

export const meta: RecipeMeta = {
  slug: "redirects-bloom-filter",
  title: "Redirects with a Bloom filter",
  summary: "Checks every path against a Bloom filter of 50,000 redirects and, on a hit, looks the path up and redirects (307/308); misses fall through to the page.",
  primitive: "fetch to the app's own Route Handler → an in-process lookup (a Worker cannot fetch itself)",
  try: [
    "curl -si http://localhost:8787/redirects-bloom-filter/blog/should-redirect-to-google | grep -iE '^(HTTP|location)'",
    "curl -s http://localhost:8787/redirects-bloom-filter/blog/should-render-basic-blog-post | grep 'Blog Post'",
    "curl -s 'http://localhost:8787/redirects-bloom-filter/api/redirects?pathname=/blog/should-redirect-to-1'",
  ],
};

export default app;
