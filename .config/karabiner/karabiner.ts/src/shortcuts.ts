import { map, rule } from "karabiner.ts"
import { karabiner_script } from "./utils/macros.ts"

export const shortcuts = [
  rule('Cmd+Ctrl+A → Ctrl+A twice')
    .manipulators([
      map('a', ['control', 'command'])
        .to({ key_code: 'a', modifiers: ['control'] })
        .to({ key_code: 'a', modifiers: ['control'] }),
    ]),

  rule('Hyper+N → click the newest notification (fast, positional)')
    .manipulators([
      map('n', 'Hyper').to(karabiner_script("notif-click", { logKeep: 50 })),
    ]),

  rule('Hyper+C → jump to the Claude notification (terminal-notifier, fast)')
    .manipulators([
      map('c', 'Hyper').to(karabiner_script("claude-notification-click-simulator")),
    ]),
]
