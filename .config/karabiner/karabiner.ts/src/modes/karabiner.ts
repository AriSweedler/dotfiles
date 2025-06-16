import { map } from "karabiner.ts"
import { AriMode, deeplink, script } from "../utils/mode"
import { raycast_deeplink, karabiner_script } from "../utils/macros"

const meta = {
  entrypoint: "k",
  layerName: "karabiner-mode",
  description: "Karabiner development helpers",
}

const dict = {
  d: deeplink("extensions/raycast/raycast/confetti"),
  s: script("confetti"),
}

const to_manipulator = ([key, action]) => {
  switch (action.kind) {
    case "deeplink":
      return map(key).to(raycast_deeplink(action.path))
    case "script":
      return map(key).to(karabiner_script(action.name))
    default:
      throw new Error("Unknown action kind")
  }
}

// --- Export Final Rule ---
const karabinerMode = new AriMode(meta, dict, to_manipulator)
export default karabinerMode.asRule()
