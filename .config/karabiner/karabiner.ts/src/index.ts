import { writeToProfile } from "karabiner.ts"
import { homeRow } from "./homerow.ts"
import applicationMode from "./modes/application"
import karabinerMode from "./modes/karabiner"
import windowMode from "./modes/window"
import { shortcuts } from "./shortcuts.ts"
import { validateClaudeKeybindings } from "./claude/validate.ts"

// Cross-check declared Claude Code leader chords against ~/.claude/keybindings.json
// before writing the profile; fails the bake (unless KARABINER_SKIP_CLAUDE_CHECK).
validateClaudeKeybindings()

writeToProfile("Default", [
  ...homeRow,
  applicationMode,
  karabinerMode,
  windowMode,
  ...shortcuts,
])
