// Drives the Worker in-process through Hono's app.request(): no server, no
// workerd. `env` stands in for wrangler's vars, secrets and the rate limiting
// binding; `withCf` puts a `cf` object on a Request the way the Workers
// runtime does (Node's Request has none).
import type { Env } from "@/env";

export async function app() {
  const { default: app } = await import("@/index");
  return app;
}

export function fakeRateLimiter(limit: number): Env["RATE_LIMITER"] {
  const counts = new Map<string, number>();
  return {
    async limit({ key }) {
      const n = (counts.get(key) ?? 0) + 1;
      counts.set(key, n);
      return { success: n <= limit };
    },
  };
}

export function env(overrides: Partial<Env> = {}): Env {
  return {
    ENVIRONMENT: "test",
    MAINTENANCE_MODE: "false",
    RATE_LIMITER: fakeRateLimiter(5),
    ...overrides,
  };
}

export function withCf(url: string, cf: Record<string, string>, init?: RequestInit): Request {
  const req = new Request(url, init);
  Object.defineProperty(req, "cf", { value: cf, enumerable: true });
  return req;
}
