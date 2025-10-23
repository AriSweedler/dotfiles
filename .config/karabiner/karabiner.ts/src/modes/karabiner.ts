import { AriMode, deeplink, script } from "../utils/mode"

const meta = {
  entrypoint: "k",
  layerName: "karabiner-mode",
  description: "Karabiner development helpers",
}

const dict = {
  d: deeplink("extensions/raycast/raycast/confetti"),
  s: script("script-example"),
  e: script("karabiner-edit-index"),
  r: script("karabiner-recompile"),
  l: script("karabiner-logs"),
  x: script("karabiner-hello-world"),
}

// --- Export Final Rule ---
const karabinerMode = new AriMode(meta, dict)
export default karabinerMode.asRule()
