// vercel/examples/edge-middleware/ab-testing-simple — middleware.ts with
// lib/ab-testing.ts and lib/buckets.ts kept verbatim (./ab-testing-simple/*),
// and the pages/home/[bucket] and pages/marketing/{[bucket],original} pages.
//
// The bucket lives in a cookie; /home and /marketing are rewritten to the
// page for the bucket, and a fresh assignment is set on the response.
import { Hono } from "hono";
import { getCookie } from "hono/cookie";
import { html } from "hono/html";
import { serialize } from "hono/utils/cookie";
import type { AppEnv } from "../env";
import { rewrite } from "../lib/middleware";
import { page, type Html, type RecipeMeta } from "../lib/page";
import { getBucket } from "./ab-testing-simple/ab-testing";
import { HOME_BUCKETS, MARKETING_BUCKETS } from "./ab-testing-simple/buckets";

const BASE = "/ab-testing-simple";

type Route = {
  page: string;
  cookie: string;
  buckets: readonly string[];
};

const ROUTES: Record<string, Route | undefined> = {
  [`${BASE}/home`]: {
    page: `${BASE}/home`,
    cookie: "bucket-home",
    buckets: HOME_BUCKETS,
  },
  [`${BASE}/marketing`]: {
    page: `${BASE}/marketing`,
    cookie: "bucket-marketing",
    buckets: MARKETING_BUCKETS,
  },
};

const app = new Hono<AppEnv>({ strict: false }).basePath(BASE);

// matcher: ['/home', '/marketing']
app.on("ALL", ["/home", "/marketing"], async (c, next) => {
  const { pathname } = new URL(c.req.url);
  const route = ROUTES[pathname];

  if (!route) return next();

  // Get the bucket from the cookie
  let bucket = getCookie(c, route.cookie);
  let hasBucket = !!bucket;

  // If there's no active bucket in cookies or its value is invalid, get a new one
  if (!bucket || !route.buckets.includes(bucket)) {
    bucket = getBucket(route.buckets);
    hasBucket = false;
  }

  // Create a rewrite to the page matching the bucket
  const url = new URL(c.req.url);
  url.pathname = `${route.page}/${bucket}`;
  const rewritten = await rewrite(app, c, url);
  const res = new Response(rewritten.body, rewritten);

  // Add the bucket to the response cookies if it's not there
  // or if its value was invalid
  if (!hasBucket) {
    res.headers.append("Set-Cookie", serialize(route.cookie, bucket, { path: "/" }));
  }

  return res;
});

// pages/home/[bucket].tsx, pages/marketing/[bucket].tsx, pages/marketing/original.tsx.
// Upstream's buttons set the cookie with js-cookie and reload; here they are
// links to /set?… which set it and redirect back.
function variant(title: string, current: string, which: "home" | "marketing", buckets: readonly string[]): Html {
  return page(
    title,
    html`<h1>${title}</h1>
      <p>You're currently on <b>${current}</b></p>
      <p>You can use the buttons below to change your assigned bucket and refresh the page:</p>
      <p>
        ${buckets.map((b) => html`<a class="button" href="${BASE}/set?page=${which}&bucket=${b}">Bucket ${b.toUpperCase()}</a>`)}
        <a class="button primary" href="${BASE}/set?page=${which}">Remove bucket</a>
      </p>`,
    "ab-testing-simple",
  );
}
app.get("/home/:bucket", (c) => c.html(variant("Home page variant", `bucket ${c.req.param("bucket").toUpperCase()}`, "home", HOME_BUCKETS)));
app.get("/marketing/original", (c) => c.html(variant("Marketing page", "/marketing/original — the original marketing page", "marketing", MARKETING_BUCKETS)));
app.get("/marketing/:bucket", (c) => c.html(variant("Marketing page variant", `bucket ${c.req.param("bucket").toUpperCase()}`, "marketing", MARKETING_BUCKETS)));

app.get("/set", (c) => {
  const which = c.req.query("page") === "marketing" ? "marketing" : "home";
  const bucket = c.req.query("bucket") ?? "";
  const cookie = serialize(`bucket-${which}`, bucket, { path: "/", maxAge: bucket ? undefined : 0 });
  return new Response(null, { status: 302, headers: { Location: `${BASE}/${which}`, "Set-Cookie": cookie } });
});

// pages/index.tsx
app.get("/", (c) =>
  c.html(
    page(
      "AB testing with buckets",
      html`<h1>AB testing with buckets</h1>
        <p>In this demo we use cookies to assign a bucket with the variant to show. Visit one of the pages below and a bucket will be assigned to you.</p>
        <ul>
          <li><a href="${BASE}/home">/home</a></li>
          <li><a href="${BASE}/marketing">/marketing</a></li>
        </ul>`,
      "ab-testing-simple",
    ),
  ),
);

export const meta: RecipeMeta = {
  slug: "ab-testing-simple",
  title: "A/B testing (simple)",
  summary: "Assigns /home and /marketing visitors to a bucket (a, b, c — or original) in a cookie and rewrites to that bucket's page.",
  primitive: "NextResponse.rewrite + res.cookies.set → in-process dispatch + Set-Cookie",
  try: [
    "curl -si http://localhost:8787/ab-testing-simple/home | grep -iE 'set-cookie|bucket'",
    "curl -s -b 'bucket-marketing=original' http://localhost:8787/ab-testing-simple/marketing | grep original",
  ],
};

export default app;
