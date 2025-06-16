import { fileURLToPath } from "url"
import path from "path"

const karabinerRoot = path.resolve(fileURLToPath(import.meta.url), "../..")
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
// TODO: This is not working
export const karabiner_script = (scriptPath: string) => {
  const fullPath = path.resolve(karabinerRoot, `scripts/bin/${scriptPath}`)
  console.log("Resolved script path:", fullPath)
  return {
    shell_command: fullPath,
  }
}
