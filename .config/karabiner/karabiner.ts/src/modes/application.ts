import { map, toApp } from "karabiner.ts"
import { AriMode } from "../utils/mode"

const meta = {
  entrypoint: "a",
  layerName: "application-mode",
  description: "Open application",
}

const dict = {
  "a": "Arc",
  "f": "Finder",
  "t": "Terminal",
  "s": "Spotify",
  "v": "Cisco AnyConnect Secure Mobility Client",
}

const to_manipulator = ([key, app]: [string, string]) => {
  return map(key).to(toApp(app))
}

// --- Export Final Rule ---
const applicationMode = new AriMode(meta, dict, to_manipulator)
export default applicationMode.asRule()
