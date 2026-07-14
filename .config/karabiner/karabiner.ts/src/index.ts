import { writeToProfile } from "karabiner.ts"
import { homeRow } from "./homerow.ts"
import applicationMode from "./modes/application"
import karabinerMode from "./modes/karabiner"
import typingMode, { typingBuilderRules } from "./modes/typing"
import windowMode from "./modes/window"
import { shortcuts } from "./shortcuts.ts"
import { validateClaudeKeybindings } from "./claude/validate.ts"
import { claudeLeaderMode } from "./claude/rule.ts"

// Cross-check declared Claude Code leader chords against ~/.claude/keybindings.json
// before writing the profile; fails the bake (unless KARABINER_SKIP_CLAUDE_CHECK).
validateClaudeKeybindings()

writeToProfile("Default", [
  ...homeRow,
  applicationMode,
  karabinerMode,
  typingMode,
  windowMode,
  claudeLeaderMode,
  // Menu/builder rules claim bare keys gated only on their own variables;
  // they sit after every layer so an active layer beats a stale menu.
  ...typingBuilderRules,
  ...shortcuts,
])
