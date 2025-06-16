import { map, rule, writeToProfile } from "karabiner.ts"
import { hyper_c, raycast_deeplink } from "./utils/macros"
import applicationMode from "./modes/application"
import karabinerMode from "./modes/karabiner"
import windowMode from "./modes/window"

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
  windowMode,
])
