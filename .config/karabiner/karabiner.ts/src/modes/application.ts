import { map } from "karabiner.ts"
import { AriMode, app } from "../utils/mode"

const meta = {
  entrypoint: "a",
  layerName: "application-mode",
  description: "Open application",
}

const dict = {
  "a": app("Arc"),
  "f": app("Finder"),
  "t": app("Terminal"),
  "s": app("Spotify"),
  "v": app("Cisco AnyConnect Secure Mobility Client"),
  "z": app("Zoom"),
}

// --- Export Final Rule ---
const applicationMode = new AriMode(meta, dict)
export default applicationMode.asRule()
