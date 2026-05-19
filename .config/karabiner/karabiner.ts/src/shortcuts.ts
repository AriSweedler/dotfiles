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
]
