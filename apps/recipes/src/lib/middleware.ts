// The Edge Middleware verbs on a Worker — what each recipe under ../recipes
// uses in place of `next/server`, `@vercel/functions` and `@vercel/edge`:
//
//   NextResponse.next()                   `await next()`, then edit `c.res`
//   NextResponse.next({ request })        `rewrite(pages, c, url, { headers })`
//   NextResponse.rewrite(url)             `rewrite(app, c, url)` — below
//   NextResponse.redirect(url, status)    `c.redirect(url, status)` (307 is Next's default)
//   NextResponse.json(body)               `c.json(body)`
//   req.nextUrl                           `new URL(c.req.url)`
//   req.cookies.get(name)?.value          `getCookie(c, name)` from hono/cookie
//   res.cookies.set(name, value)          `setCookie(c, ...)` / `serialize` from hono/cookie
//   geolocation(req)  (@vercel/functions) `geolocation(c.req.raw)` — below, from request.cf
//   ipAddress(req)    (@vercel/edge)      `ipAddress(c.req.raw)` — below, from CF-Connecting-IP
//   userAgent(req)    (next/server)       `userAgent(c.req.raw)` — below, ua-parser-js as in Next

import type { Context, ExecutionContext, Hono } from "hono";
import type { Env, Schema } from "hono/types";
import type { IncomingRequestCfProperties } from "@cloudflare/workers-types";
import UAParser from "ua-parser-js";

/**
 * `NextResponse.rewrite(url)`: answer with another route's response while the
 * browser keeps the URL it asked for. A Worker cannot fetch itself, so the
 * rewrite is an in-process dispatch — the recipe's own router (`app`) handles
 * `url` with the original request's method, headers and body. `request.headers`
 * replaces them, which is `NextResponse.next({ request: { headers } })`.
 */
export function rewrite<E extends Env, S extends Schema, P extends string>(
  app: Hono<E, S, P>,
  c: Context<E>,
  url: URL | string,
  request: { headers?: Headers } = {},
): Response | Promise<Response> {
  const rewritten = request.headers
    ? new Request(url, { ...requestInit(c.req.raw), headers: request.headers })
    : new Request(url, c.req.raw);
  return app.fetch(rewritten, c.env, executionCtx(c));
}

/** `new Request(url, request)` keeps everything but the URL; this is the same spread, for a headers swap. */
function requestInit(request: Request): RequestInit {
  return {
    method: request.method,
    body: request.body,
    redirect: request.redirect,
    signal: request.signal,
  };
}

function executionCtx(c: Context): ExecutionContext | undefined {
  try {
    return c.executionCtx;
  } catch {
    // Hono throws when there is none (tests through app.request()); the recipes never waitUntil
    return undefined;
  }
}

/** What `geolocation(request)` from `@vercel/functions` returns. */
export interface Geo {
  /** The city that the request originated from. */
  city?: string;
  /** The country that the request originated from. */
  country?: string;
  /** The flag emoji for the country the request originated from. */
  flag?: string;
  /** The Vercel Edge Network region that received the request — here the Cloudflare colo. */
  region?: string;
  /** The region part of the ISO 3166-2 code of the client IP. */
  countryRegion?: string;
  /** The latitude of the client. */
  latitude?: string;
  /** The longitude of the client. */
  longitude?: string;
  /** The timezone of the client (Cloudflare adds it; Vercel does not). */
  timezone?: string;
}

/**
 * `geolocation(request)`: Vercel reads its `x-vercel-ip-*` request headers;
 * Cloudflare puts the same data on `request.cf`, present on every request that
 * reaches a deployed Worker (and under `wrangler dev`, which fetches the
 * machine's own). Absent in unit tests unless the Request carries a `cf`.
 */
export function geolocation(request: Request): Geo {
  const cf = (request as unknown as { cf?: IncomingRequestCfProperties }).cf;
  return {
    city: cf?.city,
    country: cf?.country,
    flag: cf?.country ? getFlag(cf.country) : undefined,
    region: cf?.colo,
    countryRegion: cf?.regionCode,
    latitude: cf?.latitude,
    longitude: cf?.longitude,
    timezone: cf?.timezone,
  };
}

/** The regional-indicator pair for an ISO 3166-1 alpha-2 code, as `@vercel/functions` builds it. */
function getFlag(countryCode: string): string | undefined {
  if (!/^[A-Z]{2}$/.test(countryCode)) return undefined;
  return String.fromCodePoint(
    ...countryCode.split("").map((ch) => 0x1f1e6 + ch.charCodeAt(0) - 65),
  );
}

/** `ipAddress(request)` from `@vercel/edge`: Vercel's `x-real-ip` is Cloudflare's `CF-Connecting-IP`. */
export function ipAddress(request: Request): string | undefined {
  return request.headers.get("cf-connecting-ip") ?? undefined;
}

/** `userAgent(request)` from `next/server`: the same `ua-parser-js` result Next returns. */
export function userAgent(request: Request): UAParser.IResult {
  return new UAParser(request.headers.get("user-agent") ?? "").getResult();
}
