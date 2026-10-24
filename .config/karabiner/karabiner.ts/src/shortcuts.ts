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

  rule('Hyper+O → oneshot picker (tmux popup on the active client; Terminal window without tmux)')
    .manipulators([
      // Terminal comes forward natively — no shell, dispatched the instant the key goes
      // down and not awaited — so it is frontmost by the time the popup lands. The
      // shell_command that opens the popup runs in parallel with it.
      map('o', 'Hyper')
        .to({ software_function: { open_application: { bundle_identifier: 'com.apple.Terminal' } } })
        .to(karabiner_script("oneshot-popup")),
    ]),
]
