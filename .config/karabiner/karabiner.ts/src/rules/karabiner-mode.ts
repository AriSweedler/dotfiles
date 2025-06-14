import { hyperLayer, map } from "karabiner.ts"
import { raycast_deeplink, karabiner_script } from "../utils"

export const karabinerMode = hyperLayer("k", "karabiner-mode")
  .description("Karabiner Mode (hyper + k)")
  .leaderMode()
  .notification()
  .manipulators([
    map("d").to(raycast_deeplink("extensions/raycast/raycast/confetti")),

    // TODO: how to get scripts working
    map("s").to(karabiner_script("confetti")),
    // source new karabiner config
    // open index.ts file for editing
  ])
