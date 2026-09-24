import { map, rule, type FromKeyParam, type Modifier } from "karabiner.ts"
import { actionToTos, to_key_code } from "./utils/actions.ts"
import { raycastShortcuts } from "./raycast_shortcuts.ts"

// Compiles raycast_shortcuts.ts (direct chord → Raycast deeplink) into Karabiner rules. The
// window-management chords come from modes/window.ts (directModifiers), not from here. The
// raycast-link widget reads raycast_bindings.json, which bake GENERATES from both tables
// (generate_bindings.ts); nothing reads that JSON at compile time.
//
// Chord grammar: "+"-joined tokens, modifiers first, one key last. The key is a karabiner key
// name (a-z, 0-9, spacebar, return_or_enter, equal_sign, open_bracket, …) or one of the symbol
// aliases in utils/actions.ts (=, -, [, ], ., ,, `, ⏎, ⌫):
//   hyper+4   cmd+shift+k   ctrl+opt+return_or_enter   ctrl+opt+]   hyper+`

const MODIFIER_ALIASES: Record<string, Modifier[]> = {
  hyper: ["control", "option", "shift", "command"],
  cmd: ["command"],
  command: ["command"],
  ctrl: ["control"],
  control: ["control"],
  opt: ["option"],
  option: ["option"],
  alt: ["option"],
  shift: ["shift"],
  fn: ["fn"],
  caps: ["caps_lock"],
  caps_lock: ["caps_lock"],
}

export const parseChord = (chord: string): { key: FromKeyParam; modifiers: Modifier[] } => {
  const tokens = chord.split("+")
  const rawKey = tokens.pop()
  if (!rawKey) throw new Error(`chord has no key | chord=${chord}`)
  const key = to_key_code(rawKey.toLowerCase())
  const modifiers = new Set<Modifier>()
  for (const token of tokens.map((t) => t.toLowerCase())) {
    const expanded = MODIFIER_ALIASES[token]
    if (!expanded) throw new Error(`unknown modifier | modifier=${token} chord=${chord}`)
    expanded.forEach((m) => modifiers.add(m))
  }
  return { key: key as unknown as FromKeyParam, modifiers: [...modifiers] }
}

export const raycastRules = raycastShortcuts.map(({ chord, action }) => {
  const { key, modifiers } = parseChord(chord)
  let manipulator = map(key, modifiers)
  for (const to of actionToTos(action)) manipulator = manipulator.to(to)
  return rule(`${action.title} → raycast://${action.path}`).manipulators([manipulator])
})
