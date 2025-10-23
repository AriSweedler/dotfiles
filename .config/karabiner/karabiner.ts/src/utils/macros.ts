import { fileURLToPath } from "url"
import fs from "fs"
import path from "path"
import os from "os"
import { execSync } from "child_process"

const karabinerRoot = path.resolve(fileURLToPath(import.meta.url), "../../..")
console.log("Karabiner root path:", karabinerRoot)

// Find npm path in current context
const npmPath = execSync('which npm', { encoding: 'utf8' }).trim()
const npmDir = path.dirname(npmPath)
console.log("npm path...........:", npmDir)

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

  return {
    shell_command: `
{
  export REPO_ROOT="${karabinerRoot.replace(os.homedir(), "$HOME")}"
  export REPO_LIB="\${REPO_ROOT}/src/scripts/lib"
  export PATH="${npmDir}:/opt/homebrew/bin:/usr/local/bin:\${PATH}"
  set -x
  date
  cd "\${REPO_ROOT:?}"
  echo "Invoking ${scriptPathAbs}"
  ${scriptPathAbs}
} &> "/tmp/karabiner.${scriptPathRel}.txt"
`
  }
}
