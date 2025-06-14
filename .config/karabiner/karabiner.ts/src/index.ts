import { map, rule, writeToProfile } from "karabiner.ts"
import { hyper_c, raycast_deeplink } from "./utils"
import { symbolModeLayer } from "./rules/symbol-mode"
import { applicationMode } from "./rules/application-mode"
import { karabinerMode } from "./rules/karabiner-mode"


writeToProfile("Default", [
  rule('Right option → Hyper').manipulators([
    map('right_option').toHyper().toIfAlone('right_option'),
  ]),
  rule('confetti').manipulators([{
    type: "basic",
    from: hyper_c,
    to: [raycast_deeplink("extensions/raycast/raycast/confetti")],
  }]),

  applicationMode,
  karabinerMode,
])
