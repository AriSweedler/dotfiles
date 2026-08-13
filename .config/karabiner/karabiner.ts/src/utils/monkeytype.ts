import { createRequire } from "module"

// Build Monkeytype "share test settings" URLs from a typed settings tuple.
// Opening such a URL applies the settings to that one test only, leaving the
// visitor's saved Monkeytype configuration untouched. Monkeytype encodes the
// tuple as compressToEncodedURIComponent(JSON.stringify(settings)). The codec
// is the vendored lz-string, shared with monkeytype_url.cjs (the runtime
// consumer).

const require = createRequire(import.meta.url)
const { compressToEncodedURIComponent } = require("../scripts/lib/lz-string.js") as {
  compressToEncodedURIComponent: (s: string) => string
}

type Mode = "time" | "words" | "quote" | "zen" | "custom"
type Difficulty = "normal" | "expert" | "master"

// Mirrors Monkeytype's SharedTestSettings tuple; null leaves the visitor's
// current setting in place for that slot.
export type MonkeytypeTestSettings = [
  mode: Mode | null,
  mode2: string | null,
  customText: unknown,
  punctuation: boolean | null,
  numbers: boolean | null,
  language: string | null,
  difficulty: Difficulty | null,
  funbox: string[] | null,
]

export const monkeytypeTestUrl = (settings: MonkeytypeTestSettings): string =>
  `https://monkeytype.com?testSettings=${compressToEncodedURIComponent(JSON.stringify(settings))}`
