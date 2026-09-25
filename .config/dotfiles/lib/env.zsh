# dotfiles/lib/env.zsh — every constant, seam and flag default the kernel, the verbs and the
# steps read. Derived from HOME and the environment only; nothing here logs or writes.
zmodload zsh/datetime

# --- Where this checkout lives ---
# bin/dotfiles exports DOTFILES_LIB; sourced alone (a test, a step subprocess) it is this file's dir.
typeset -gx DOTFILES_LIB="${DOTFILES_LIB:-${${(%):-%x}:A:h}}"
typeset -gx DOTFILES_ROOT="${DOTFILES_LIB:h}"          # …/dotfiles: lib/ steps/ cmd/ jobs/
typeset -gx DOTFILES_STEPS="${DOTFILES_ROOT}/steps"
typeset -gx DOTFILES_CMD="${DOTFILES_ROOT}/cmd"
typeset -gx DOTFILES_CONFIG="${DOTFILES_ROOT:h}"       # the .config of this checkout, not necessarily $HOME's
typeset -gx DOTFILES_TESTS="${DOTFILES_ROOT}/tests"
# The name fix hints print the CLI under.
typeset -gx CLI_NAME="${CLI_NAME:-dotfiles}"

# --- Environment variables (the help text documents each) ---
typeset -gx DOTFILES_REMOTE="${DOTFILES_REMOTE:-https://github.com/AriSweedler/dotfiles.git}"   # https: a fresh machine needs no key
# The ssh key's 1Password item and vault come from the local tier (~/.local/share/zsh/plugins/dotfiles.zsh); unset = no key.
typeset -g DOTFILES_SSH_KEY_OP_ITEM="${DOTFILES_SSH_KEY_OP_ITEM:-}"
typeset -g DOTFILES_SSH_KEY_OP_VAULT="${DOTFILES_SSH_KEY_OP_VAULT:-}"
typeset -g DOTFILES_SSH_KEY_PATH="${DOTFILES_SSH_KEY_PATH:-}"   # known = "already in the agent" costs no 1Password call (~1 s)
typeset -g DOTFILES_GITHUB_LOGIN="${DOTFILES_GITHUB_LOGIN:-AriSweedler}"   # every personal push authenticates as this, by its gh token
typeset -g DOTFILES_SLOW_STEP="${DOTFILES_SLOW_STEP:-0.5}"

# --- Process environment every run and every step subprocess share ---
# .zshenv exports the XDG set once HOME is checked out; the first run predates that.
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-${HOME}/.config}"
export XDG_DATA_HOME="${XDG_DATA_HOME:-${HOME}/.local/share}"
export XDG_STATE_HOME="${XDG_STATE_HOME:-${HOME}/.local/state}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-${HOME}/.cache}"
export GIT_TERMINAL_PROMPT=0 GIT_OPTIONAL_LOCKS=0
export HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_ANALYTICS=1 HOMEBREW_NO_ENV_HINTS=1
export HOMEBREW_NO_INSTALL_CLEANUP=1 HOMEBREW_COLOR=0 HOMEBREW_NO_EMOJI=1

# --- Seams: every default is the real machine; tests override and nothing else ---
typeset -gx NEW_MACHINE_SHARED_DIR="${NEW_MACHINE_SHARED_DIR:-${DOTFILES_CONFIG}/new-machine}"
typeset -gx NEW_MACHINE_LOCAL_DIR="${NEW_MACHINE_LOCAL_DIR:-${XDG_DATA_HOME}/new-machine}"
typeset -gx NEW_MACHINE_STATE_DIR="${NEW_MACHINE_STATE_DIR:-${XDG_STATE_HOME}/new-machine}"
typeset -gx NEW_MACHINE_DESKTOP_DIR="${NEW_MACHINE_DESKTOP_DIR:-${HOME}/Desktop}"
typeset -gx NEW_MACHINE_LAUNCH_AGENTS_DIR="${NEW_MACHINE_LAUNCH_AGENTS_DIR:-${HOME}/Library/LaunchAgents}"
typeset -gx NEW_MACHINE_TERMINAL_PLIST="${NEW_MACHINE_TERMINAL_PLIST:-${HOME}/Library/Preferences/com.apple.Terminal.plist}"
typeset -gx NEW_MACHINE_DF_GIT_DIR="${NEW_MACHINE_DF_GIT_DIR:-${HOME}/dotfiles.git}"
typeset -gx NEW_MACHINE_LDF_GIT_DIR="${NEW_MACHINE_LDF_GIT_DIR:-${HOME}/.local/local-dotfiles.git}"
typeset -gx NEW_MACHINE_DF_HOOKS="${NEW_MACHINE_DF_HOOKS:-${HOME}/.config/git/dotfiles-hooks}"
typeset -gx NEW_MACHINE_LDF_HOOKS="${NEW_MACHINE_LDF_HOOKS:-${HOME}/.config/git/local-dotfiles-hooks}"
typeset -gx NEW_MACHINE_BREW_PREFIXES="${NEW_MACHINE_BREW_PREFIXES-/opt/homebrew /usr/local}"
typeset -gx NEW_MACHINE_NOW="${NEW_MACHINE_NOW:-${EPOCHSECONDS}}"
typeset -gx NEW_MACHINE_HOST="${NEW_MACHINE_HOST:-$(hostname -s)}"
typeset -gx NEW_MACHINE_CHECK_TIMEOUT_SECS="${NEW_MACHINE_CHECK_TIMEOUT_SECS:-120}"
typeset -gx NEW_MACHINE_APPLY_TIMEOUT_SECS="${NEW_MACHINE_APPLY_TIMEOUT_SECS:-1800}"
typeset -gx NEW_MACHINE_RETRY_SECS="${NEW_MACHINE_RETRY_SECS:-60}"
typeset -gx NEW_MACHINE_LOCK_MAX_AGE_SECS="${NEW_MACHINE_LOCK_MAX_AGE_SECS:-7200}"
typeset -gx NEW_MACHINE_BREW_BUSY_PATTERN="${NEW_MACHINE_BREW_BUSY_PATTERN:-Homebrew/Library/Homebrew/brew.rb}"
# zsh arithmetic reads a non-numeric string as 0, which would silently disable a watchdog.
for _seam in NEW_MACHINE_CHECK_TIMEOUT_SECS NEW_MACHINE_APPLY_TIMEOUT_SECS NEW_MACHINE_RETRY_SECS NEW_MACHINE_LOCK_MAX_AGE_SECS; do
  if [[ "${(P)_seam}" != <-> ]]; then
    print -u2 "[ERROR] seam must be a non-negative integer | var='${_seam}' value='${(P)_seam}'"
    return 3
  fi
done
unset _seam

# launchd's PATH lacks Homebrew, so a tool is also probed by absolute path under the prefixes.
# Prints the path, or nothing.
probe_tool() {
  local tool="${1}" found prefix
  found="$(command -v "${tool}" 2>/dev/null || true)"
  if [[ -n "${found}" ]]; then
    print -r -- "${found}"
    return 0
  fi
  for prefix in ${=NEW_MACHINE_BREW_PREFIXES}; do
    if [[ -x "${prefix}/bin/${tool}" ]]; then
      print -r -- "${prefix}/bin/${tool}"
      return 0
    fi
  done
  return 0
}
typeset -gx NEW_MACHINE_BREW="${NEW_MACHINE_BREW:-$(probe_tool brew)}"
typeset -gx NEW_MACHINE_NOTIFIER="${NEW_MACHINE_NOTIFIER:-$(probe_tool terminal-notifier)}"
typeset -gx NEW_MACHINE_CODE="${NEW_MACHINE_CODE:-$(probe_tool code)}"
# Through the seam, not DOTFILES_CONFIG: the tests point the seam into the fake HOME while the code
# runs from the real checkout, and the click command must name the HOME the report is in.
typeset -gx NEW_MACHINE_EDIT_WINDOW="${NEW_MACHINE_SHARED_DIR:h}/bin/tmux-edit-window"

# PATH self-heal: brew's own helpers and `code` must resolve for `brew bundle check` under launchd,
# and ~/.local/bin holds the claude installer's symlink. Local bin wins, as in the interactive shell.
typeset -U path
if [[ -n "${NEW_MACHINE_BREW}" ]]; then
  path=("${NEW_MACHINE_BREW:h}" $path)
fi
if [[ -d "${HOME}/.local/bin" ]]; then
  path=("${HOME}/.local/bin" $path)
fi

# --- Run identity: from NEW_MACHINE_NOW alone, so the report marker can depend on it ---
run_id() {
  local id
  strftime -s id '%Y%m%dT%H%M%S' "${1:-${NEW_MACHINE_NOW}}"
  print -r -- "${id}"
}
typeset -gx RUN_ID="${RUN_ID:-$(run_id)}"
typeset -gx RUN_DIR="${RUN_DIR:-${NEW_MACHINE_STATE_DIR}/runs/${RUN_ID}}"

# --- Tier files the brew model edits or commits ---
# Resources needed before HOME is checked out resolve relative to the checkout; files the tool
# edits or commits resolve under HOME once the checkout exists.
if [[ -d "${HOME}/.config/new-machine" ]]; then
  typeset -gx NEW_MACHINE_GLOBAL_DIR="${NEW_MACHINE_GLOBAL_DIR:-${HOME}/.config/new-machine}"
else
  typeset -gx NEW_MACHINE_GLOBAL_DIR="${NEW_MACHINE_GLOBAL_DIR:-${NEW_MACHINE_SHARED_DIR}}"
fi
typeset -gx GLOBAL_BREWFILE="${NEW_MACHINE_GLOBAL_DIR}/Brewfile"
typeset -gx GLOBAL_BREWFILE_IGNORE="${NEW_MACHINE_GLOBAL_DIR}/Brewfile.ignore"
typeset -gx LOCAL_BREWFILE="${NEW_MACHINE_LOCAL_DIR}/Brewfile"
typeset -gx LOCAL_BREWFILE_IGNORE="${NEW_MACHINE_LOCAL_DIR}/Brewfile.ignore"
typeset -gx LDF_EXCLUDE_TEMPLATE="${NEW_MACHINE_GLOBAL_DIR}/local-dotfiles-exclude"
typeset -gx LAST_RESULT_FILE="${NEW_MACHINE_STATE_DIR}/last_result.json"
typeset -gx VERIFY_TRAIL="${NEW_MACHINE_STATE_DIR}/verify.log"
typeset -gx REPORT_PATH="${NEW_MACHINE_DESKTOP_DIR}/new-machine-FAILED.md"
# The brew model, a domain library steps and verbs load on demand.
typeset -gx DOTFILES_BREW_LIB="${DOTFILES_CMD}/brew/brew.zsh"

# --- The two tiers, by repo name; a submodule needs no row: its git is its checkout, ~/<path> ---
typeset -gA TIER_GIT_DIR=(shared "${NEW_MACHINE_DF_GIT_DIR}" local "${NEW_MACHINE_LDF_GIT_DIR}")
typeset -gA TIER_WORK_TREE=(shared "${HOME}" local "${HOME}/.local")
typeset -gA TIER_HOOKS=(shared "${NEW_MACHINE_DF_HOOKS}" local "${NEW_MACHINE_LDF_HOOKS}")
typeset -gA TIER_ALIAS=(shared df local ldf)   # the git alias a human types
# The pre-harness layout kept the shared bare repo at ~/dotfiles; init's first step renames it.
typeset -g LEGACY_SHARED_GIT_DIR="${HOME}/dotfiles"
typeset -g GITMODULES="${HOME}/.gitmodules"
typeset -g STATE_DIR="${XDG_STATE_HOME}/dotfiles"
typeset -g LOG_DIR="${STATE_DIR}/push"
typeset -g KEEP_BACKUPS=5
typeset -g IDENTITY_CACHE="${STATE_DIR}/identity"   # '<sha256 of token> <login> <epoch>': whose token, verified when
typeset -g IDENTITY_TTL_SECONDS=$(( 7 * 24 * 3600 ))
typeset -g REGISTRY_LINK="${HOME}/.config/claude/skills/ari-dotfiles-skill-registry/bin/link"
typeset -ga PUSH_PARTS=(local submodules shared)   # in run order
# Submodule paths declared in ~/.gitmodules, relative to $HOME; empty when none.
SUBMODULES=("${(@f)$(git config -f "${GITMODULES}" --get-regexp '^submodule\..*\.path$' 2>/dev/null | awk '{print $2}' || true)}")
typeset -ga SUBMODULES=("${(@)SUBMODULES:#}")
# Every dotfiles submodule is a public personal repo, so its commits carry the personal identity.
typeset -g SUBMODULE_GIT_NAME="Ari Sweedler"
typeset -g SUBMODULE_GIT_EMAIL="ari@sweedler.com"

# --- jobs: one launchd job runs every job plugin, from both tiers (jobs.zsh) ---
typeset -g JOBS_LABEL="com.$(id -un).dotfiles-jobs"
typeset -g JOBS_PLIST="${HOME}/Library/LaunchAgents/${JOBS_LABEL}.plist"
typeset -g JOBS_ROOT_DF="${HOME}/.config/dotfiles/jobs"                              # the shared tier's plugins
typeset -g JOBS_ROOT_LDF="${XDG_DATA_HOME}/dotfiles/jobs"                             # the local tier's
typeset -g JOBS_STATE_DIR="${STATE_DIR}/jobs"                                         # logs, success stamps, the agent
typeset -g JOBS_AGENT_BIN="${JOBS_STATE_DIR}/bin/dotfiles-jobs-agent"   # the job's program; launchd keeps it alive
typeset -g JOBS_UNLOCK_NOTIFICATION="com.apple.screenIsUnlocked"          # a distributed notification, hence the agent
typeset -g JOBS_INTERVAL_SECONDS=300          # the tick; cron schedules are checked on it, so it is their resolution
typeset -g JOBS_TIMEOUT_SECONDS=900           # a plugin's run is killed after this unless its '# timeout:' line says otherwise
typeset -g JOBS_HUD_SECONDS=2                 # how long the engine's "job ok" banner stays up
typeset -g JOBS_NOTIFIER_TIMEOUT_SECONDS=10   # terminal-notifier occasionally never returns (seen on -remove); a banner is never worth a hang
# launchd's PATH has no Homebrew; plugins shell out to jq, terminal-notifier, python3.
typeset -g JOBS_LAUNCHD_PATH="/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
# The per-plugin jobs this framework replaced; install boots them out and removes their plists.
typeset -ga JOBS_LEGACY_LABELS=("com.$(id -un).git-health" "com.$(id -un).aws-sso-autologin" "com.$(id -un).new-machine-verify")
typeset -gA JOB_PATH=() JOB_TIER=()         # name → executable, name → df | ldf; filled by jobs_discover
# A plugin's `# deps:` names run as its setup first; the local root wins (how *this* machine provides X).
typeset -g DEPS_ROOT_DF="${HOME}/.config/dotfiles/deps"
typeset -g DEPS_ROOT_LDF="${XDG_DATA_HOME}/dotfiles/deps"
typeset -g JOBS_DEP_TIMEOUT_SECONDS=120       # a dep is setup, not the job; one that takes longer is hung
typeset -g JOBS_DEP_FAILED_RC=125             # the run's rc when a dep blocked the plugin (124 is the timeout)
typeset -gA DEP_PATH=() DEP_TIER=()         # name → executable, name → df | ldf; filled by deps_discover

# What the test harness asserts hermeticity against: where HOME, brew and PATH resolve.
env_probe() {
  jq -n --arg home "${HOME}" --arg path "${PATH}" --arg brew_on_path "$(command -v brew 2>/dev/null || true)" \
        --arg brew "${NEW_MACHINE_BREW}" --arg notifier "${NEW_MACHINE_NOTIFIER}" --arg code "${NEW_MACHINE_CODE}" \
        --arg shared_dir "${NEW_MACHINE_SHARED_DIR}" --arg global_dir "${NEW_MACHINE_GLOBAL_DIR}" \
        --arg local_dir "${NEW_MACHINE_LOCAL_DIR}" --arg state_dir "${NEW_MACHINE_STATE_DIR}" \
        --arg desktop_dir "${NEW_MACHINE_DESKTOP_DIR}" --arg launch_agents_dir "${NEW_MACHINE_LAUNCH_AGENTS_DIR}" \
        --arg now "${NEW_MACHINE_NOW}" --arg host "${NEW_MACHINE_HOST}" --arg run_id "${RUN_ID}" \
    '{home:$home, path:$path, brew_on_path:$brew_on_path, brew:$brew, notifier:$notifier, code:$code,
      shared_dir:$shared_dir, global_dir:$global_dir, local_dir:$local_dir, state_dir:$state_dir,
      desktop_dir:$desktop_dir, launch_agents_dir:$launch_agents_dir, now:$now, host:$host, run_id:$run_id}'
}

# --- Flags, set by main (before the verb) ---
# --dry-run is the exported DOTFILES_DRY_RUN=1, one truth for this process, every subprocess and every lib (run.zsh: is_dry_run).
typeset -g PRINT_DIR=false          # --dir: print the tier's bare repo path and exit
typeset -g GIT_TIER=shared          # git / --dir act on one tier; --local picks the local one
typeset -g TIMING=false
typeset -ga PUSH_SCOPE=("${PUSH_PARTS[@]}")   # narrowed by push's --<part>, then --no-<part>
typeset -g TOKEN=""              # the login's gh token, loaded before the first personal push; inherited by the background pushes
typeset -gA PIDS=() STARTS=()    # background pushes in flight, by repo
