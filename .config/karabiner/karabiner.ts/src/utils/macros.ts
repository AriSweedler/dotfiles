import { fileURLToPath } from "url"
import fs from "fs"
import path from "path"
import os from "os"

const karabinerRoot = path.resolve(fileURLToPath(import.meta.url), "../../..")

console.log("Karabiner root path:", karabinerRoot)

// Local script runner
export const karabiner_script = (scriptPathRel: string) => {
  const scriptPathAbs = path.resolve(karabinerRoot, `src/scripts/bin/${scriptPathRel}`)
  const scriptPathAbsEnv = scriptPathAbs.replace(os.homedir(), "$HOME")

  // make sure this file is executable - check permission bits
  try {
    const scriptPathAbs = path.resolve(karabinerRoot, `src/scripts/bin/${scriptPathRel}`)
    fs.accessSync(scriptPathAbs, fs.constants.X_OK)
  } catch (err) {
    throw new Error(`Script is not executable or not found | scriptPathRel=${scriptPathRel}, scriptPathAbs=${scriptPathAbs} scriptPathAbsEnv=${scriptPathAbsEnv}`)
  }

  const logFile = `/tmp/karabiner.${scriptPathRel}.txt`

  return {
    shell_command: `export LOG_FILE=${logFile}; export REPO_ROOT=${karabinerRoot.replace(os.homedir(), "$HOME")}; ${scriptPathAbsEnv}`
  }
}
