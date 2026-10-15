// Verbatim but for two strict-mode touches (`noUncheckedIndexedAccess`): the
// return type and the `[0]!` in cryptoRandom.
export function getBucket(buckets: readonly string[]): string {
  // Get a random number between 0 and 1
  let n = cryptoRandom() * 100
  // Get the percentage of each bucket
  let percentage = 100 / buckets.length
  // Loop through the buckets and see if the random number falls
  // within the range of the bucket
  return (
    buckets.find(() => {
      n -= percentage
      return n <= 0
    }) ?? (buckets[0] as string)
  )
}

function cryptoRandom() {
  return crypto.getRandomValues(new Uint32Array(1))[0]! / (0xffffffff + 1)
}
