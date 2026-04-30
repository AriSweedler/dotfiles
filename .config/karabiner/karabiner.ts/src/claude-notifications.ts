import { map, rule } from "karabiner.ts"
import { karabiner_script } from "./utils/macros"

// Hyper+N → simulate a click on the latest Claude Code notification, then
// confetti on success or alert on "nothing to catch". The decision lives
// in the wrapper script; see src/scripts/bin/claude-notification-click.sh
// and ~/.config/claude/README.md.
export const claudeNotifications = [
  rule('Hyper+N → simulate Claude notification click')
    .manipulators([
      map('n', 'Hyper').to(karabiner_script("claude-notification-click")),
    ]),
]
