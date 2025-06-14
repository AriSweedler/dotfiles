import { rule } from "karabiner.ts"

export const confettiRule = rule("Cmd+L → Raycast Confetti").manipulators([
  {
    type: "basic",
    from: {
      key_code: "l",
      modifiers: {
        mandatory: ["left_command"],
      },
    },
    to: ,
  },
])
