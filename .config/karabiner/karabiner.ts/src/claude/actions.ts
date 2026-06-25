// Single source of truth for the Claude Code "leader" chords.
//
// This array drives everything: the Karabiner manipulators (generated elsewhere)
// AND the bake-time validation that the matching chords exist in
// ~/.claude/keybindings.json. Add a binding here and the bake will tell you
// exactly what to add to keybindings.json if it's missing.

export const LEADER = "alt+l" // global leader; every chord is LEADER + suffix

export type ClaudeAction = {
  suffix: string // key pressed after the leader (e.g. "j")
  ccContext: string // Claude Code keybinding context the chord lives in
  ccAction: string // Claude Code action the chord maps to
  desc: string // human description
}

export const claudeActions: ClaudeAction[] = [
  { suffix: "j", ccContext: "Footer", ccAction: "footer:down", desc: "next agent" },
  { suffix: "k", ccContext: "Footer", ccAction: "footer:up", desc: "prev agent" },
]

// The chord exactly as it appears as a key in keybindings.json, e.g. "alt+l j".
export const chordFor = (a: ClaudeAction): string => `${LEADER} ${a.suffix}`
