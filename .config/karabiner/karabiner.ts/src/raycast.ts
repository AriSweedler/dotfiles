import { map, rule, type FromKeyParam, type Modifier } from "karabiner.ts"
import { actionToTos, deeplink } from "./utils/actions.ts"
import bindings from "./raycast_bindings.json"

// Raycast actions bound in Karabiner, declared once in raycast_bindings.json. The raycast-link
// widget (zsh/plugins/raycast_link.zsh) renders "<Raycast: Clipboard History | key: '✦4'>" from
// the same file this compiles, so the key Claude prints is the key Karabiner has. Raycast's own hotkeys live in its
// encrypted store and cannot be read, which is why the source of truth is here.
//
// Chord grammar: "+"-joined lowercase tokens, modifiers first, one key last:
//   hyper+4   cmd+shift+k   ctrl+opt+return_or_enter
type Binding = { alias: string; title: string; path: string; chord: string }

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

const parseChord = (chord: string): { key: FromKeyParam; modifiers: Modifier[] } => {
  const tokens = chord.toLowerCase().split("+")
  const key = tokens.pop()
  if (!key) throw new Error(`chord has no key | chord=${chord}`)
  const modifiers = new Set<Modifier>()
  for (const token of tokens) {
    const expanded = MODIFIER_ALIASES[token]
    if (!expanded) throw new Error(`unknown modifier | modifier=${token} chord=${chord}`)
    expanded.forEach((m) => modifiers.add(m))
  }
  return { key: key as FromKeyParam, modifiers: [...modifiers] }
}

export const raycastRules = (bindings as Binding[]).map((binding) => {
  const { key, modifiers } = parseChord(binding.chord)
  let manipulator = map(key, modifiers)
  for (const to of actionToTos(deeplink(binding.path))) manipulator = manipulator.to(to)
  return rule(`${binding.title} → raycast://${binding.path}`).manipulators([manipulator])
})
