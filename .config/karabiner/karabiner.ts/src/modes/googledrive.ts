import {AriMode, script} from "../utils/mode"

const meta = {
  entrypoint: "g",
  layerName: "google-drive-mode",
  description: "Google Drive document macros",
}

const dict = {
  "s": script("osascript-google-drive-codeblock-shell"),
  "j": script("osascript-google-drive-codeblock-javascript"),
}

// --- Export Final Rule ---
const googleDriveMode = new AriMode(meta, dict)
export default googleDriveMode.asRule()
