import { map, rule } from "karabiner.ts"
import { karabiner_script } from "./utils/macros"

export const shortcuts = [
  rule('Cmd+Ctrl+A → Ctrl+A twice')
    .manipulators([
      map('a', ['control', 'command'])
        .to({ key_code: 'a', modifiers: ['control'] })
        .to({ key_code: 'a', modifiers: ['control'] }),
    ]),

  rule('Hyper+P → open go/pr/<clipboard>')
    .manipulators([
      map('p', 'Hyper').to(karabiner_script("karabiner-go-pr")),
    ]),

  rule('Hyper+Q → open PR for focused claude session (no fallback)')
    .manipulators([
      map('q', 'Hyper').to(karabiner_script("karabiner-open-pr-from-focussed-claude")),
    ]),

  rule('Hyper+N → click the newest notification (fast, positional)')
    .manipulators([
      // logKeep: 50 — keep more runs of this handler's log while debugging it.
      map('n', 'Hyper').to(karabiner_script("notif-click", { logKeep: 50 })),
    ]),

  rule('Hyper+C → jump to the Claude notification (terminal-notifier, fast)')
    .manipulators([
      map('c', 'Hyper').to(karabiner_script("claude-notification-click-simulator")),
    ]),
]
