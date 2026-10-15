import { DICTIONARIES } from './constants'
import { Dictionary } from './types'

const api = {
  dictionaries: {
    // upstream: `async (locale): Promise<Dictionary>` — `locale: string` and the
    // cast are the two strict-mode touches; the lookup is as written
    fetch: async (locale: string): Promise<Dictionary> =>
      (DICTIONARIES[locale] || DICTIONARIES['default']) as Dictionary,
  },
}

export default api
