// The product's identity, written once. The index page's heading and <title>
// and every page's footer read SITE_NAME; the footer links SOURCE_URL. When the
// product is instantiated both are rewritten to its own name and repository,
// so keep them literal and on one line each. Templates escape them (`html`),
// so a name may carry `&` or `'`.
export const SITE_NAME = "Edge Middleware Recipes";
export const SOURCE_URL = "https://github.com/sourceplane/edge-middleware-recipes";
