import type { RateLimit } from "@cloudflare/workers-types";

/** The Worker's bindings (wrangler.jsonc `vars` + `ratelimits`, and the secrets). */
export interface Env {
  ENVIRONMENT: string;
  /**
   * maintenance-page: Edge Config's `isInMaintenanceMode` flag as a var
   * ("true" | "false"). Unset reproduces the upstream's "missing config" dialog.
   */
  MAINTENANCE_MODE?: string;
  /** basic-auth-password: Worker secrets (`wrangler secret put`, `.dev.vars` locally). */
  BASIC_AUTH_USER?: string;
  BASIC_AUTH_PASSWORD?: string;
  /** rate-limit-any-framework: the Workers Rate Limiting binding (5 per 10 s per key). */
  RATE_LIMITER: RateLimit;
}

export type AppEnv = { Bindings: Env };
