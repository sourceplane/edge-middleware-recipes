// vercel/examples/edge-middleware/redirects-bloom-filter/redirects/generate-bloom-filter.ts.
// Run with `pnpm --filter @app/recipes generate-bloom-filter` (Node 22.6+ strips
// the types) after editing redirects.json; the filter is bundled with the Worker.
import { ScalableBloomFilter } from 'bloom-filters'
import { writeFileSync } from 'node:fs'
import redirects from '../src/recipes/redirects-bloom-filter/redirects.json' with { type: 'json' }

// Initialize bloom filter
const filter = new ScalableBloomFilter(Object.keys(redirects).length, 0.0001)

// Add all paths to the bloom filter
for (const key in redirects) {
  filter.add(key)
}

// Save the bloom filter to a JSON file
const filterJson = filter.saveAsJSON()
writeFileSync(
  new URL('../src/recipes/redirects-bloom-filter/redirects-bloom-filter.json', import.meta.url),
  JSON.stringify(filterJson)
)
