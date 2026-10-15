// The recipe registry: one module per upstream example, each a Hono app on
// its own base path, mounted on the root app in src/index.ts.
import type { Hono } from "hono";
import type { AppEnv } from "../env";
import type { RecipeMeta } from "../lib/page";
import geolocation, { meta as geolocationMeta } from "./geolocation";
import i18n, { meta as i18nMeta } from "./i18n";
import basicAuthPassword, { meta as basicAuthPasswordMeta } from "./basic-auth-password";
import rateLimitAnyFramework, { meta as rateLimitAnyFrameworkMeta } from "./rate-limit-any-framework";
import abTestingSimple, { meta as abTestingSimpleMeta } from "./ab-testing-simple";
import maintenancePage, { meta as maintenancePageMeta } from "./maintenance-page";
import cookies, { meta as cookiesMeta } from "./cookies";
import addHeader, { meta as addHeaderMeta } from "./add-header";
import modifyRequestHeader, { meta as modifyRequestHeaderMeta } from "./modify-request-header";
import queryParamsFilter, { meta as queryParamsFilterMeta } from "./query-params-filter";
import jsonResponse, { meta as jsonResponseMeta } from "./json-response";
import userAgentBasedRendering, { meta as userAgentBasedRenderingMeta } from "./user-agent-based-rendering";
import redirectsBloomFilter, { meta as redirectsBloomFilterMeta } from "./redirects-bloom-filter";

/** What the index page lists, in the order the upstream catalog presents them. */
export const recipes: RecipeMeta[] = [
  geolocationMeta,
  i18nMeta,
  basicAuthPasswordMeta,
  rateLimitAnyFrameworkMeta,
  abTestingSimpleMeta,
  maintenancePageMeta,
  cookiesMeta,
  addHeaderMeta,
  modifyRequestHeaderMeta,
  queryParamsFilterMeta,
  jsonResponseMeta,
  userAgentBasedRenderingMeta,
  redirectsBloomFilterMeta,
];

/** Mounts every recipe on `app`; each carries its own base path. */
export function mount(app: Hono<AppEnv>): void {
  app
    .route("/", geolocation)
    .route("/", i18n)
    .route("/", basicAuthPassword)
    .route("/", rateLimitAnyFramework)
    .route("/", abTestingSimple)
    .route("/", maintenancePage)
    .route("/", cookies)
    .route("/", addHeader)
    .route("/", modifyRequestHeader)
    .route("/", queryParamsFilter)
    .route("/", jsonResponse)
    .route("/", userAgentBasedRendering)
    .route("/", redirectsBloomFilter);
}
