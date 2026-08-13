// Single source of truth for the Claude Code "leader" chords.
//
// This array drives everything: the Karabiner hyper+l mode (rule.ts)
// AND the bake-time validation (validate.ts) that the matching chords
// exist in ~/.claude/keybindings.json. Add a binding here and the bake tells you
// exactly what to add to keybindings.json if it's missing (and vice-versa).

import { type FromAndToKeyCode } from "karabiner.ts"

export const LEADER = "alt+l" // global leader — every chord is LEADER + suffix

export type ClaudeAction = {
  suffix: FromAndToKeyCode // key pressed after the leader (e.g. "j")
  ccContext: string // Claude Code keybinding context the chord lives in
  ccAction: string // Claude Code action the chord maps to
  desc: string // human description
}

export const claudeActions: ClaudeAction[] = [
  { suffix: "j", ccContext: "Footer", ccAction: "footer:down", desc: "next agent" },
  { suffix: "k", ccContext: "Footer", ccAction: "footer:up", desc: "prev agent" },
]

// The chord exactly as it appears as a key in keybindings.json, e.g. "alt+l alt+j".
// The second key is alt-modified so a mistimed/stray press never types a literal letter.
export const chordFor = (a: ClaudeAction): string => `${LEADER} alt+${a.suffix}`

// Inverse of chordFor: recover the suffix from a keybindings.json chord key.
export const CHORD_PREFIX = `${LEADER} `
export const suffixFromChord = (chord: string) => chord.slice(CHORD_PREFIX.length).replace(/^alt\+/, "")
