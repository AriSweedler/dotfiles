import { fileURLToPath } from "url"
import fs from "fs"
import path from "path"
import os from "os"
import { execSync } from "child_process"

const karabinerRoot = path.resolve(fileURLToPath(import.meta.url), "../../..")
console.log("Karabiner root path:", karabinerRoot)

// npm's dir, so shell_commands can reach the active node toolchain. Best-effort:
// if npm isn't on PATH at bake time, skip it (the Homebrew dirs below usually
// cover node too) rather than throwing and failing the whole bake.
let npmDir = ""
try {
  npmDir = path.dirname(execSync("which npm", { encoding: "utf8" }).trim())
  console.log("npm path...........:", npmDir)
} catch {
  console.log("npm path...........: (not found — skipping)")
}

// Directories prepended to PATH for every karabiner-invoked shell_command.
// Karabiner-Elements inherits launchd's minimal PATH, so we re-prepend the
// places where user-installed scripts and tooling actually live.
const PATH_PREFIX_DIRS = [
  "$HOME/.config/bin",   // user CLI helpers
  npmDir,                // active node toolchain (empty if npm wasn't found)
  "/opt/homebrew/bin",   // Homebrew (Apple Silicon)
  "/usr/local/bin",      // Homebrew (Intel) + manual installs
].filter(Boolean)

// Local script runner. Runs <repo>/src/scripts/bin/<rel> and keeps the last
// `logKeep` runs of its output under /tmp/karabiner.<rel>/ (rotated via
// log_rotate, not truncated) so intermittent failures can be compared across
// presses. logKeep defaults to 5; bump it per-binding for ones under active
// debugging, e.g. karabiner_script("notif-click", { logKeep: 50 }).
// Each run ends with an `elapsed_ms=<n> rc=<n>` line (zsh EPOCHREALTIME) so any
// binding's latency is greppable across presses.
export const karabiner_script = (
  scriptPathRel: string,
  { logKeep = 5 }: { logKeep?: number } = {},
) => {
  const scriptPathAbs = path.resolve(karabinerRoot, `src/scripts/bin/${scriptPathRel}`)
  const scriptPathAbsEnv = scriptPathAbs.replace(os.homedir(), "$HOME")

  // Fail loudly at bake time if the target script is missing or not executable.
  try {
    fs.accessSync(scriptPathAbs, fs.constants.X_OK)
  } catch {
    throw new Error(`Script is not executable or not found | scriptPathRel=${scriptPathRel} scriptPathAbs=${scriptPathAbs} scriptPathAbsEnv=${scriptPathAbsEnv}`)
  }

  const pathPrefix = PATH_PREFIX_DIRS.join(":")
  const logDir = `/tmp/karabiner.${scriptPathRel}`
  const logFile = `${logDir}/log.txt`

  return {
    shell_command: `
mkdir -p "${logDir}"
zsh -c 'source "\$HOME/.config/zsh/plugins/log_rotate.zsh" && log_rotate "\$1" "\$2"' _ "${logFile}" "${logKeep}" 2>/dev/null || true
{
  export REPO_ROOT="${karabinerRoot.replace(os.homedir(), "$HOME")}"
  export REPO_LIB="\${REPO_ROOT}/src/scripts/lib"
  export PATH="${pathPrefix}:\${PATH}"
  set -x
  date
  cd "\${REPO_ROOT:?}"
  echo "Invoking ${scriptPathAbs}"
  zsh -c 'zmodload zsh/datetime; typeset -F _s=\$EPOCHREALTIME; "\$1"; _rc=\$?; typeset -F _e=\$EPOCHREALTIME; printf "elapsed_ms=%.0f rc=%d\\n" \$(( (_e - _s) * 1000 )) \$_rc; exit \$_rc' _ "${scriptPathAbs}"
} &> "${logFile}"
`
  }
}
