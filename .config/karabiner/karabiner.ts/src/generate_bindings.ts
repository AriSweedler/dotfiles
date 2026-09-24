import { writeFileSync } from "node:fs"
import { resolve } from "node:path"
import type { Modifier } from "karabiner.ts"
import { AriMode } from "./utils/mode.ts"
import { deeplinkSlug, to_key_code, type Deeplink } from "./utils/actions.ts"
import { applicationMode } from "./modes/application.ts"
import { karabinerMode } from "./modes/karabiner.ts"
import { typingMode } from "./modes/typing.ts"
import { windowMode } from "./modes/window.ts"
import { raycastShortcuts } from "./raycast_shortcuts.ts"

// The Raycast bindings as data, from the TypeScript tables that also compile into Karabiner:
// every deeplink in an AriMode dict (reached by the layer chord "hyper+<entrypoint> <key>" when
// the mode has a layer, and by the direct chord when it has directModifiers) and every
// raycast_shortcuts.ts entry. The path is the identity; the widget addresses an entry by the
// path's last segment (the command slug), so slugs must be unique. Two outputs of one document:
//   - `npm run build` (index.ts) writes src/raycast_bindings.json, a generated artifact that is
//     committed for reading and diffing; nothing consumes it at runtime.
//   - `npm run bindings` (this file with --stdout) prints it; the raycast-link widget (zsh)
//     takes its bindings from that, so it always sees the tables as they are now.

const MODES: AriMode[] = [applicationMode, karabinerMode, typingMode, windowMode]

// Chord tokens use the short modifier names both parsers accept.
const MODIFIER_SHORT: Record<string, string> = {
  control: "ctrl",
  option: "opt",
  command: "cmd",
  shift: "shift",
  fn: "fn",
  caps_lock: "caps_lock",
}

export type BindingEntry = {
  path: string
  title: string
  chords: string[]
  keepFocus?: boolean
  allowId?: string
}

const keyName = (key: string): string => String(to_key_code(key.toLowerCase()))

// Normalizes a shortcut chord so the JSON always carries karabiner key names (hyper+` → hyper+grave_accent_and_tilde).
const canonicalChord = (chord: string): string => {
  const tokens = chord.split("+")
  const key = tokens.pop()
  if (!key) throw new Error(`chord has no key | chord=${chord}`)
  return [...tokens.map((t) => t.toLowerCase()), keyName(key)].join("+")
}

export const collectBindings = (): BindingEntry[] => {
  const byPath = new Map<string, BindingEntry>()
  const add = (d: Deeplink, chord: string) => {
    const existing = byPath.get(d.path)
    if (existing) {
      if (!existing.chords.includes(chord)) existing.chords.push(chord)
      return
    }
    byPath.set(d.path, {
      path: d.path,
      title: d.title,
      chords: [chord],
      ...(d.keepFocus ? { keepFocus: true } : {}),
      ...(d.allowId ? { allowId: d.allowId } : {}),
    })
  }
  for (const mode of MODES) {
    const direct = (mode.meta.directModifiers ?? []) as Modifier[]
    for (const [key, action] of Object.entries(mode.actionDict)) {
      if (action.kind !== "deeplink") continue
      const k = keyName(key)
      // The direct chord first: it is the one the widget shows.
      if (direct.length > 0) add(action, `${direct.map((m) => MODIFIER_SHORT[m] ?? m).join("+")}+${k}`)
      if (mode.meta.entrypoint) add(action, `hyper+${mode.meta.entrypoint} ${k}`)
    }
  }
  for (const { chord, action } of raycastShortcuts) add(action, canonicalChord(chord))
  const entries = [...byPath.values()].sort((a, b) => a.path.localeCompare(b.path))
  const seen = new Map<string, string>()
  for (const e of entries) {
    const slug = deeplinkSlug(e.path)
    const other = seen.get(slug)
    if (other) throw new Error(`two bindings share a command slug; the widget cannot address them | slug=${slug} paths=${other},${e.path}`)
    seen.set(slug, e.path)
  }
  return entries
}

const document = () => ({
  $generated: "by bake from karabiner.ts/src/*.ts (modes/*.ts, raycast_shortcuts.ts); do not edit",
  bindings: collectBindings(),
})

export const writeBindings = (file = resolve(process.cwd(), "src/raycast_bindings.json")): void => {
  const doc = document()
  writeFileSync(file, JSON.stringify(doc, null, 2) + "\n")
  console.log(`✓ raycast_bindings.json written | entries=${doc.bindings.length} file=${file}`)
}

// `tsx src/generate_bindings.ts --stdout`: the same document on stdout, nothing written.
if (process.argv.includes("--stdout")) {
  process.stdout.write(JSON.stringify(document()) + "\n")
}
