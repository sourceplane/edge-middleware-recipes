#!/usr/bin/env bash
# THE REBRAND WRITES EACH VALUE ONCE, AND WHAT IT WROTE STAYS WRITTEN.
#
# Drives the real tooling/rebrand/rebrand.mjs over one-file trees and compares
# the file. Each case is a shape this baseline's identity actually takes in the
# tree — the source link, the product-name seam, the Worker name in
# wrangler.jsonc and in the smoke's URL, the placeholder domain, the runtime
# secrets' refs — and the idempotence cases run through several passes (a
# phase re-run, a `--redo`, the deployment record's heal all re-run the rebrand
# over a tree it already wrote), so a value once written must survive every
# later pass unchanged.
#
# The identity is PINNED (fixtures/baseline-identity.edge-middleware-recipes.json)
# rather than read from .baseline/identity.json: what this tests is the engine,
# and its fixtures spell the identity out literally.
#
# Needs: node, git. No network.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
rebrand="$here/../tooling/rebrand/rebrand.mjs"
identity="$here/fixtures/baseline-identity.edge-middleware-recipes.json"

fail=0
# check NAME VALUES-JSON FILE CONTENT WANT [PASSES]
check() {
  local name="$1" values="$2" file="$3" content="$4" want="$5" passes="${6:-1}"
  local tmp got out i
  tmp="$(mktemp -d)"
  git -C "$tmp" init -q
  mkdir -p "$tmp/$(dirname "$file")" "$tmp/.rebrand"
  printf '%s\n' "$content" > "$tmp/$file"
  printf '%s\n' "$values" > "$tmp/.rebrand/values.json"
  for ((i = 1; i <= passes; i++)); do
    git -C "$tmp" add -A
    if ! out="$(cd "$tmp" && node "$rebrand" --baseline-identity "$identity" --values .rebrand/values.json --allow-dirty 2>&1)"; then
      echo "   ✕  $name: rebrand pass $i failed:" >&2
      printf '%s\n' "$out" | sed 's/^/        /' >&2
      fail=1
      rm -rf "$tmp"
      return
    fi
  done
  got="$(cat "$tmp/$file")"
  rm -rf "$tmp"
  if [ "$got" = "$want" ]; then
    echo "   ok  $name"
  else
    echo "   ✕  $name:" >&2
    echo "        got:  $got" >&2
    echo "        want: $want" >&2
    fail=1
  fi
}

acme='{"reponame":"acme-recipes","productname":"Acme Recipes","productdomain":"acme.dev","githuborg":"acme-inc","subdomain":"acme","orunWorkspace":"ws_79BDXAZQ"}'

echo "── rebrand: the product's own identity"
check "the source link names the product's owner and repository" \
  "$acme" apps/recipes/src/site.ts \
  'export const SOURCE_URL = "https://github.com/sourceplane/edge-middleware-recipes";' \
  'export const SOURCE_URL = "https://github.com/acme-inc/acme-recipes";'
check "the product-name seam takes the product's name" \
  "$acme" apps/recipes/src/site.ts 'export const SITE_NAME = "Edge Middleware Recipes";' \
  'export const SITE_NAME = "Acme Recipes";'
check "…and stays a valid string for a name with an apostrophe and an ampersand" \
  '{"reponame":"sams-recipes","productname":"Sam'"'"'s Middleware & More","productdomain":"sam.dev"}' \
  apps/recipes/src/site.ts 'export const SITE_NAME = "Edge Middleware Recipes";' \
  'export const SITE_NAME = "Sam'"'"'s Middleware & More";'
check "the display name elsewhere is content, and is left alone" \
  "$acme" apps/recipes/src/recipes/x.ts '// Edge Middleware Recipes, ported.' \
  '// Edge Middleware Recipes, ported.'
check "the Worker name is re-prefixed (wrangler --env adds the environment)" \
  "$acme" apps/recipes/wrangler.jsonc '  "name": "edge-middleware-recipes-recipes",' \
  '  "name": "acme-recipes-recipes",'
check "the smoke's URL: Worker name and subdomain" \
  "$acme" apps/recipes/component.yaml \
  'smokeCommand: "base=\"${DEPLOYED_URL:-https://edge-middleware-recipes-recipes-${ORUN_ENVIRONMENT}.your-workers-subdomain.workers.dev}\""' \
  'smokeCommand: "base=\"${DEPLOYED_URL:-https://acme-recipes-recipes-${ORUN_ENVIRONMENT}.acme.workers.dev}\""'
check "an environment URL in the intent" \
  "$acme" intent.yaml '    url: https://edge-middleware-recipes-recipes-stage.your-workers-subdomain.workers.dev' \
  '    url: https://acme-recipes-recipes-stage.acme.workers.dev'
check "the placeholder domain is the product's domain, not a renamed slug" \
  "$acme" intent.yaml '      BASE_DOMAIN: edge-middleware-recipes.example.com' \
  '      BASE_DOMAIN: acme.dev'
check "no domain given: the reserved placeholder, for an owner to replace later" \
  '{"reponame":"acme-recipes","productname":"Acme Recipes","githuborg":"acme-inc","subdomain":"acme"}' \
  intent.yaml '      BASE_DOMAIN: edge-middleware-recipes.example.com' \
  '      BASE_DOMAIN: acme-recipes.example.com'
check "an empty domain is no domain" \
  '{"reponame":"acme-recipes","productname":"Acme Recipes","productdomain":""}' \
  intent.yaml '      BASE_DOMAIN: edge-middleware-recipes.example.com' \
  '      BASE_DOMAIN: acme-recipes.example.com'
check "the repo slug" \
  "$acme" package.json '  "name": "edge-middleware-recipes",' \
  '  "name": "acme-recipes",'
check "a runtime secret's ref names the product's workspace and project" \
  "$acme" apps/recipes/component.yaml \
  '    BASIC_AUTH_USER: "secret://ws_CHANGE_ME/edge-middleware-recipes/{{ .environment }}/BASIC_AUTH_USER"' \
  '    BASIC_AUTH_USER: "secret://ws_79BDXAZQ/acme-recipes/{{ .environment }}/BASIC_AUTH_USER"'
check "…and without a workspace, the repo name stands in for it" \
  '{"reponame":"acme-recipes","productname":"Acme Recipes","productdomain":"acme.dev"}' apps/recipes/component.yaml \
  '    BASIC_AUTH_USER: "secret://ws_CHANGE_ME/edge-middleware-recipes/{{ .environment }}/BASIC_AUTH_USER"' \
  '    BASIC_AUTH_USER: "secret://acme-recipes/acme-recipes/{{ .environment }}/BASIC_AUTH_USER"'
check "the @app package scope is not identity" \
  "$acme" apps/recipes/package.json '  "name": "@app/recipes",' \
  '  "name": "@app/recipes",'
check "org-owned identity is not renamed" \
  "$acme" intent.yaml 'apiVersion: sourceplane.io/v1 # mail ops@sourceplane.ai' \
  'apiVersion: sourceplane.io/v1 # mail ops@sourceplane.ai'
check "without githuborg the source link keeps the baseline's owner" \
  '{"reponame":"acme-recipes","productname":"Acme Recipes","productdomain":"acme.dev"}' \
  apps/recipes/src/site.ts 'const SOURCE_URL = "https://github.com/sourceplane/edge-middleware-recipes"' \
  'const SOURCE_URL = "https://github.com/sourceplane/acme-recipes"'

echo "── rebrand: a written value is not rewritten, in any later pass"
contains='{"reponame":"edge-middleware-recipes-2","productname":"Edge Middleware Recipes 2","productdomain":"edge-middleware-recipes.example.com.au","githuborg":"sourceplane","subdomain":"your-workers-subdomain-2","orunWorkspace":"ws_79BDXAZQ"}'
check "a repo slug containing the baseline's slug survives three passes" \
  "$contains" package.json '  "name": "edge-middleware-recipes",' \
  '  "name": "edge-middleware-recipes-2",' 3
check "a Worker name built on it survives three passes" \
  "$contains" apps/recipes/wrangler.jsonc '  "name": "edge-middleware-recipes-recipes",' \
  '  "name": "edge-middleware-recipes-2-recipes",' 3
check "a domain containing the baseline's domain survives three passes" \
  "$contains" intent.yaml 'BASE_DOMAIN: edge-middleware-recipes.example.com' \
  'BASE_DOMAIN: edge-middleware-recipes.example.com.au' 3
check "a subdomain containing the placeholder survives three passes" \
  "$contains" intent.yaml 'url: https://edge-middleware-recipes-recipes-prod.your-workers-subdomain.workers.dev' \
  'url: https://edge-middleware-recipes-2-recipes-prod.your-workers-subdomain-2.workers.dev' 3
check "a product name containing the baseline's name survives three passes" \
  "$contains" apps/recipes/src/site.ts 'export const SITE_NAME = "Edge Middleware Recipes";' \
  'export const SITE_NAME = "Edge Middleware Recipes 2";' 3
check "a secret ref built on the slug survives three passes" \
  "$contains" apps/recipes/component.yaml \
  'X: "secret://ws_CHANGE_ME/edge-middleware-recipes/{{ .environment }}/BASIC_AUTH_PASSWORD"' \
  'X: "secret://ws_79BDXAZQ/edge-middleware-recipes-2/{{ .environment }}/BASIC_AUTH_PASSWORD"' 3
check "a slug ending in the Worker's base is renamed once (acme-recipes → acme-recipes-recipes)" \
  "$acme" apps/recipes/wrangler.jsonc '  "name": "edge-middleware-recipes-recipes",' \
  '  "name": "acme-recipes-recipes",' 3

# --verify runs in every phase. Without the product's values it cannot tell
# the product's own identity from a leftover; with them it can. A real
# leftover must fail it either way.
verify() { # NAME VALUES FILE CONTENT WANT(pass|fail) [--values]
  local name="$1" values="$2" file="$3" content="$4" want="$5" withvalues="${6:-}" tmp got
  tmp="$(mktemp -d)"
  git -C "$tmp" init -q
  mkdir -p "$tmp/$(dirname "$file")" "$tmp/.rebrand"
  printf '%s\n' "$content" > "$tmp/$file"
  printf '%s\n' "$values" > "$tmp/.rebrand/values.json"
  git -C "$tmp" add -A
  if (cd "$tmp" && node "$rebrand" --baseline-identity "$identity" --verify ${withvalues:+--values .rebrand/values.json} >/dev/null 2>&1); then got=pass; else got=fail; fi
  rm -rf "$tmp"
  if [ "$got" = "$want" ]; then echo "   ok  $name"; else echo "   ✕  $name: --verify ${got}ed, want $want" >&2; fail=1; fi
}
echo "── rebrand --verify: the product's own identity is not residue"
verify "given the values, a slug containing the baseline's passes" \
  "$contains" package.json '"name": "edge-middleware-recipes-2"' pass --values
verify "without them it cannot know, and fails" \
  "$contains" package.json '"name": "edge-middleware-recipes-2"' fail
verify "given the values, a real leftover still fails" \
  "$acme" package.json '"name": "edge-middleware-recipes"' fail --values
verify "a leftover Worker name fails" \
  "$acme" apps/recipes/wrangler.jsonc '"name": "edge-middleware-recipes-recipes"' fail --values
verify "a leftover code identifier fails (no rule renames it — so nothing may spell it)" \
  "$acme" apps/recipes/src/x.ts 'export class EdgeMiddlewareRecipes {}' fail --values
verify "a leftover placeholder domain fails" \
  "$acme" intent.yaml 'BASE_DOMAIN: edge-middleware-recipes.example.com' fail --values
verify "a clean product passes" \
  "$acme" package.json '"name": "acme-recipes"' pass --values

echo "── rebrand: a residue it cannot rename fails the rebrand itself"
tmp="$(mktemp -d)"; git -C "$tmp" init -q; mkdir -p "$tmp/.rebrand" "$tmp/apps/recipes"
printf '%s\n' "$acme" > "$tmp/.rebrand/values.json"
printf 'const x = "EDGE_MIDDLEWARE_RECIPES_TOKEN"\n' > "$tmp/apps/recipes/x.ts"
git -C "$tmp" add -A
if (cd "$tmp" && node "$rebrand" --baseline-identity "$identity" --values .rebrand/values.json --allow-dirty >/dev/null 2>&1); then
  echo "   ✕  an unrenamable env-var prefix passed the rebrand" >&2; fail=1
else
  echo "   ok  an unrenamable env-var prefix fails the rebrand, naming the file"
fi
rm -rf "$tmp"

[ "$fail" -eq 0 ] || exit 1
echo "rebrand.test.sh: ok"
