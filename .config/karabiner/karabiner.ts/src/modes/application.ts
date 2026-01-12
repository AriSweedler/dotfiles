import { AriMode, app } from "../utils/mode"

const meta = {
  entrypoint: "a",
  layerName: "application-mode",
  description: "Open application",
}

const dict = {
  "b": app("Google Chrome"), // browser
  "m": app("Spotify"), // music
  "c": app("Slack"), // chat
  "t": app("Terminal"),
  "z": app("Zoom"),
}

// --- Export Final Rule ---
const applicationMode = new AriMode(meta, dict)
export default applicationMode.asRule()
