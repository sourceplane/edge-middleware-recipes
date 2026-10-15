// vercel/examples/edge-middleware/json-response — middleware.ts.
//
// The middleware answers `/` itself with a JSON body; the page behind it is
// never reached. `NextResponse.json(body)` is `c.json(body)`.
import { Hono } from "hono";
import type { AppEnv } from "../env";
import type { RecipeMeta } from "../lib/page";

const BASE = "/json-response";

const app = new Hono<AppEnv>({ strict: false }).basePath(BASE);

// matcher: '/'
app.use("/", async (c) => {
  return c.json({ message: "hello world!" });
});

// pages/index.tsx
app.get("/", (c) => c.text("This page should never be reached"));

export const meta: RecipeMeta = {
  slug: "json-response",
  title: "JSON response",
  summary: "Answers / from the middleware with {\"message\": \"hello world!\"}; the page behind it is never reached.",
  primitive: "NextResponse.json → c.json",
  try: ["curl -si http://localhost:8787/json-response | grep -iE 'content-type|message'"],
};

export default app;
