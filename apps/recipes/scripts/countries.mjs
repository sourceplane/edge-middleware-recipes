// vercel/examples/edge-middleware/geolocation/scripts/countries.js — the
// `setupCountryInfo` step that upstream runs from next.config.js: fetch the
// mledoze/countries data and keep the three fields the middleware reads.
// Run with `pnpm --filter @app/recipes countries` to refresh countries.json.
import { writeFile } from 'node:fs/promises'

const JSON_URL =
  'https://raw.githubusercontent.com/mledoze/countries/master/dist/countries.json'

async function setupCountryInfo() {
  const req = await fetch(JSON_URL)
  const countriesData = await req.json()

  // grab only the country data we need
  const data = countriesData.map((x) => ({
    cca2: x.cca2,
    currencies: x.currencies,
    languages: x.languages,
  }))

  const filePath = new URL('../src/recipes/geolocation/countries.json', import.meta.url)
  const content = JSON.stringify(data)

  await writeFile(filePath, content)
}

await setupCountryInfo()
