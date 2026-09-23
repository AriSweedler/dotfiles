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
  { logKeep = 5, args = [] }: { logKeep?: number; args?: string[] } = {},
) => {
  const scriptPathAbs = path.resolve(karabinerRoot, `src/scripts/bin/${scriptPathRel}`)
  const scriptPathAbsEnv = scriptPathAbs.replace(os.homedir(), "$HOME")

  // Fail loudly at bake time if the target script is missing or not executable.
  try {
    fs.accessSync(scriptPathAbs, fs.constants.X_OK)
  } catch {
    throw new Error(`Script is not executable or not found | scriptPathRel=${scriptPathRel} scriptPathAbs=${scriptPathAbs} scriptPathAbsEnv=${scriptPathAbsEnv}`)
  }

  // Args are baked into the generated shell_command. Keep them shell-simple
  // (no quotes/dollars) so the double-quoted embedding below can't be escaped.
  for (const arg of args) {
    if (!/^[A-Za-z0-9_.\/=-]+$/.test(arg)) {
      throw new Error(`Unsafe script arg | scriptPathRel=${scriptPathRel} arg=${arg}`)
    }
  }
  const argsSuffix = args.map((a) => ` "${a}"`).join("")

  const pathPrefix = PATH_PREFIX_DIRS.join(":")
  const logDir = `/tmp/karabiner.${scriptPathRel}`
  const logFile = `${logDir}/log.txt`

  // Two shells for the whole run (Karabiner's sh, then one zsh that execs nothing
  // but the script): the log dir is made only when missing, and the rotation, the
  // date line and the timer are zsh builtins. On a Mac with an endpoint agent every
  // process spawn costs ~17 ms, and this wrapper used to spend eight of them
  // (mkdir, a zsh for log_rotate and its rm/mv, date, a second zsh) before the
  // script even started — a fifth of Hyper+O's latency.
  // The zsh program sits in sh single quotes, so it contains none itself.
  // \${...} escapes TS interpolation. Bare $VAR passes through to the shell untouched.
  return {
    shell_command: `
d="${logDir}"; [ -d "$d" ] || mkdir -p "$d"
exec zsh -c '
  zmodload zsh/datetime
  source "$HOME/.config/zsh/plugins/log_rotate.zsh"
  log_rotate "$1" "$2" 2>/dev/null
  export REPO_ROOT="${karabinerRoot.replace(os.homedir(), "$HOME")}"
  export REPO_LIB="\${REPO_ROOT}/src/scripts/lib"
  export PATH="${pathPrefix}:\${PATH}"
  {
    strftime "%a %b %e %H:%M:%S %Z %Y" "$EPOCHSECONDS"
    cd "\${REPO_ROOT:?}"
    print -r -- "Invoking ${scriptPathAbs}${argsSuffix}"
    typeset -F _s=$EPOCHREALTIME
    "${scriptPathAbs}"${argsSuffix}
    _rc=$?
    typeset -F _e=$EPOCHREALTIME
    printf "elapsed_ms=%.0f rc=%d\\n" $(( (_e - _s) * 1000 )) $_rc
    exit $_rc
  } &> "$1"
' _ "${logFile}" "${logKeep}"
`
  }
}
