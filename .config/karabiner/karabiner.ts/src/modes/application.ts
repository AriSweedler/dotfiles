import { map } from "karabiner.ts"
import { AriMode, toApp } from "../utils/mode"

const meta = {
  entrypoint: "a",
  layerName: "application-mode",
  description: "Open applications",
}

const dict = Object.fromEntries(
  Object.entries({
    "a": "Arc",
    "f": "Finder",
    "t": "Terminal",
    "m": "Microsoft Outlook",
    "s": "Spotify",
    "v": "Cisco AnyConnect Secure Mobility Client",
  }).map(([key, value]) => [key, toApp(value)])
)

// --- Export Final Rule ---
const applicationMode = new AriMode(meta, dict)
export default applicationMode.asRule()
