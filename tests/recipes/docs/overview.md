# recipes-tests

The Worker's vitest suite (the index, the site identity and each of the thirteen recipes, driven in-process through Hono with a fake rate limiter), run with pnpm test

The test suite for **recipes**. It deploys nothing: its lane installs, builds and runs the tests.

|              |                      |
| ------------ | -------------------- |
| Type         | `turbo-package`      |
| Source       | `tests/recipes`      |
| Package      | `@app/recipes-tests` |
| Environments | `dev`: `quick-check` |

## Depends on

- (none)

## Depended on by

- (none)
