# recipes — architecture

Built by the turbo pipeline from `apps/recipes` and deployed with wrangler.

|                     |                               |
| ------------------- | ----------------------------- |
| Worker config       | `apps/recipes/wrangler.jsonc` |
| Entry               | `src/index.ts`                |
| Compatibility date  | `2026-10-01`                  |
| Compatibility flags | `nodejs_compat`               |

## Bindings

| Binding        | Kind         | Source                        |
| -------------- | ------------ | ----------------------------- |
| `RATE_LIMITER` | Rate limiter | 5 requests / 10s per location |

## Variables

`ENVIRONMENT`, `MAINTENANCE_MODE` — overridden per environment (`dev`, `prod`, `stage`).

## Secrets resolved by the lane (names only)

- `BASIC_AUTH_PASSWORD` (optional)
- `BASIC_AUTH_USER` (optional)
