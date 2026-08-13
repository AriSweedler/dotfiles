// Build Monkeytype "share test settings" URLs from a typed settings tuple.
// Opening such a URL applies the settings to that one test only, leaving the
// visitor's saved Monkeytype configuration untouched. Monkeytype encodes the
// tuple as compressToEncodedURIComponent(JSON.stringify(settings)).

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

// --- LZ-string codec --------------------------------------------------------
// TypeScript port of the compress half of pieroxy/lz-string 1.5.0 (WTFPL),
// reduced to the URI-safe variant Monkeytype uses. The bit-level output must
// match the original exactly or Monkeytype cannot decode the payload.

const URI_SAFE_ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+-$"
const BITS_PER_CHAR = 6

class BitWriter {
  private chars: string[] = []
  private value = 0
  private position = 0

  // Emit `count` bits of `value`, least significant bit first.
  writeBits(value: number, count: number) {
    for (let i = 0; i < count; i++) {
      this.pushBit(value & 1)
      value >>= 1
    }
  }

  private pushBit(bit: number) {
    this.value = (this.value << 1) | bit
    if (this.position === BITS_PER_CHAR - 1) {
      this.chars.push(URI_SAFE_ALPHABET.charAt(this.value))
      this.value = 0
      this.position = 0
    } else {
      this.position++
    }
  }

  // Zero-pad the final partial character and return the encoded string.
  flush(): string {
    for (;;) {
      this.value <<= 1
      if (this.position === BITS_PER_CHAR - 1) {
        this.chars.push(URI_SAFE_ALPHABET.charAt(this.value))
        return this.chars.join("")
      }
      this.position++
    }
  }
}

export function compressToEncodedURIComponent(input: string): string {
  const writer = new BitWriter()
  const dictionary = new Map<string, number>()
  // Characters seen but not yet emitted; their first emission is a literal
  // (marker + char code) that implicitly defines the dictionary entry.
  const pendingLiterals = new Set<string>()
  let dictSize = 3
  let numBits = 2
  let enlargeIn = 2 // Compensate for the first entry, which should not count.

  const growCodeWidth = () => {
    if (--enlargeIn === 0) {
      enlargeIn = 2 ** numBits
      numBits++
    }
  }

  const writeSymbol = (symbol: string) => {
    if (pendingLiterals.has(symbol)) {
      const code = symbol.charCodeAt(0)
      if (code < 256) {
        writer.writeBits(0, numBits)
        writer.writeBits(code, 8)
      } else {
        writer.writeBits(1, numBits)
        writer.writeBits(code, 16)
      }
      growCodeWidth()
      pendingLiterals.delete(symbol)
    } else {
      writer.writeBits(dictionary.get(symbol)!, numBits)
    }
    growCodeWidth()
  }

  let w = ""
  for (let i = 0; i < input.length; i++) {
    const c = input.charAt(i)
    if (!dictionary.has(c)) {
      dictionary.set(c, dictSize++)
      pendingLiterals.add(c)
    }
    const wc = w + c
    if (dictionary.has(wc)) {
      w = wc
    } else {
      writeSymbol(w)
      dictionary.set(wc, dictSize++)
      w = c
    }
  }
  if (w !== "") {
    writeSymbol(w)
  }
  writer.writeBits(2, numBits) // End-of-stream marker.
  return writer.flush()
}
