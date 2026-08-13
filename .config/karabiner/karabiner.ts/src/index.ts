import { writeToProfile } from "karabiner.ts"
import { homeRow } from "./homerow.ts"
import applicationMode from "./modes/application.ts"
import karabinerMode from "./modes/karabiner.ts"
import typingMode, { typingBuilderRules } from "./modes/typing.ts"
import windowMode from "./modes/window.ts"
import { shortcuts } from "./shortcuts.ts"
import { validateClaudeKeybindings } from "./claude/validate.ts"
import { claudeLeaderMode } from "./claude/rule.ts"

// Drift between the declared leader chords and ~/.claude/keybindings.json
// fails the bake unless KARABINER_SKIP_CLAUDE_CHECK is set.
validateClaudeKeybindings()

writeToProfile("Default", [
  ...homeRow,
  applicationMode,
  karabinerMode,
  typingMode,
  windowMode,
  claudeLeaderMode,
  // Menu/builder rules claim bare keys gated only on their own variables.
  // They sit after every layer so an active layer beats a stale menu.
  ...typingBuilderRules,
  ...shortcuts,
])
