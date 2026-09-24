import { AriMode, app, deeplink, script, which_keyboard } from "../utils/mode.ts"

const meta = {
  entrypoint: "k",
  layerName: "karabiner-mode",
  description: "Karabiner development helpers",
}

const dict = {
  d: deeplink("extensions/raycast/raycast/confetti", { title: "Confetti", allowId: "builtin_command_confetti" }),
  s: script("script-example"),
  e: script("karabiner-edit-index"),
  r: script("karabiner-recompile"),
  l: script("karabiner-logs"),
  x: script("karabiner-hello-world"),
  n: which_keyboard(),
  v: app("Karabiner-EventViewer"),
}

export const karabinerMode = new AriMode(meta, dict)
export default karabinerMode.asRule()
