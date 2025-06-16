import { fileURLToPath } from "url"
import fs from "fs"
import path from "path"

const karabinerRoot = path.resolve(fileURLToPath(import.meta.url), "../../..")
console.log("Karabiner root path:", karabinerRoot)

// Hyper key definition: cmd + opt + ctrl + shift
export const ariHyper = {
  mandatory: ["left_command", "left_option", "left_control", "left_shift"],
  optional: ["any"],
}

// Convenience for mapping Hyper + <key>
export const hyper_c = {
  modifiers: ariHyper,
  key_code: "c",
}

// Raycast deeplink shortcut helper
export const raycast_deeplink = (deeplink: string) => ({
  shell_command: `open raycast://${deeplink}`,
})

// Local script runner
export const karabiner_script = (scriptPath: string) => {
  const fullPath = path.resolve(karabinerRoot, `src/scripts/bin/${scriptPath}`)
  // make sure this file is executable - check permission bits

  // Check if file is executable
  try {
    fs.accessSync(fullPath, fs.constants.X_OK)
  } catch (err) {
    throw new Error(`Script is not executable or not found | scriptPath=${scriptPath}, fullPath=${fullPath}`)
  }

  const logFile = `/tmp/karabiner.${scriptPath}.txt`

  return {
    shell_command: `export LOG_FILE=${logFile}; export REPO_ROOT=${karabinerRoot}; ${fullPath}`
  }
}
