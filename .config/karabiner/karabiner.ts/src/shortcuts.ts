import { map, rule } from "karabiner.ts"

export const shortcuts = [
  rule('Cmd+Ctrl+A → Ctrl+A twice')
    .manipulators([
      map('a', ['control', 'command'])
        .to({ key_code: 'a', modifiers: ['control'] })
        .to({ key_code: 'a', modifiers: ['control'] }),
    ]),
]
