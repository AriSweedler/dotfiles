# dotfiles/lib/env.zsh — the environment variables, constants and flag defaults every module reads.

# --- Environment variables (the help text documents each) ---

readonly DOTFILES_REMOTE="${DOTFILES_REMOTE:-https://github.com/AriSweedler/dotfiles.git}"   # https: a fresh machine needs no key
# The ssh key's 1Password item and vault come from the local tier (~/.local/share/zsh/plugins/dotfiles.zsh); unset = no key.
readonly DOTFILES_SSH_KEY_OP_ITEM="${DOTFILES_SSH_KEY_OP_ITEM:-}"
readonly DOTFILES_SSH_KEY_OP_VAULT="${DOTFILES_SSH_KEY_OP_VAULT:-}"
readonly DOTFILES_SSH_KEY_PATH="${DOTFILES_SSH_KEY_PATH:-}"   # known = "already in the agent" costs no 1Password call (~1 s)
readonly DOTFILES_GITHUB_LOGIN="${DOTFILES_GITHUB_LOGIN:-AriSweedler}"   # every personal push authenticates as this, by its gh token
readonly DOTFILES_SLOW_STEP="${DOTFILES_SLOW_STEP:-0.5}"

# --- Constants ---

# The tiers, by repo name. A submodule needs no row: its git is its checkout, ~/<path>.
readonly -A TIER_GIT_DIR=(shared "${HOME}/dotfiles.git" local "${HOME}/.local/local-dotfiles.git")
readonly -A TIER_WORK_TREE=(shared "${HOME}" local "${HOME}/.local")
readonly -A TIER_HOOKS=(shared "${HOME}/.config/git/dotfiles-hooks" local "${HOME}/.config/git/local-dotfiles-hooks")
readonly -A TIER_ALIAS=(shared df local ldf)   # the git alias a human types
# The pre-harness layout kept the shared bare repo at ~/dotfiles; init's first step renames it.
# (The local tier is per machine and was never migrated by anything; nothing to do there.)
readonly LEGACY_SHARED_GIT_DIR="${HOME}/dotfiles"
readonly GITMODULES="${HOME}/.gitmodules"
readonly STATE_DIR="${XDG_STATE_HOME:-${HOME}/.local/state}/dotfiles"
readonly LOG_DIR="${STATE_DIR}/push"
readonly KEEP_BACKUPS=1
readonly IDENTITY_CACHE="${STATE_DIR}/identity"   # '<sha256 of token> <login> <epoch>': whose token, verified when
readonly IDENTITY_TTL_SECONDS=$(( 7 * 24 * 3600 ))
readonly REGISTRY_LINK="${HOME}/.config/claude/skills/ari-dotfiles-skill-registry/bin/link"
readonly VALID_COMMANDS=(init pull push status logs git jobs)
readonly PUSH_PARTS=(local submodules shared)   # in run order
# Submodule paths declared in ~/.gitmodules, relative to $HOME; empty when none.
SUBMODULES=("${(@f)$(git config -f "${GITMODULES}" --get-regexp '^submodule\..*\.path$' 2>/dev/null | awk '{print $2}' || true)}")
readonly -a SUBMODULES=("${(@)SUBMODULES:#}")

# --- jobs: one launchd job runs every job plugin, from both tiers (lib/jobs.zsh) ---

readonly JOBS_LABEL="com.$(id -un).dotfiles-jobs"
readonly JOBS_PLIST="${HOME}/Library/LaunchAgents/${JOBS_LABEL}.plist"
readonly JOBS_ROOT_DF="${HOME}/.config/dotfiles/jobs"                              # the shared tier's plugins
readonly JOBS_ROOT_LDF="${XDG_DATA_HOME:-${HOME}/.local/share}/dotfiles/jobs"       # the local tier's
readonly JOBS_STATE_DIR="${STATE_DIR}/jobs"                                         # logs, success stamps, the consumer
readonly JOBS_CONSUMER_BIN="${JOBS_STATE_DIR}/bin/launch-event-consume"
readonly JOBS_EVENT_STREAM="com.apple.notifyd.matching"
readonly JOBS_EVENT_NAME="com.apple.screenIsUnlocked"
readonly JOBS_EVENT_WAIT_SECONDS=2          # the consumer's wait for an event before deciding none started the job
readonly JOBS_INTERVAL_SECONDS=300          # the tick; cron schedules are checked on it, so it is their resolution
readonly JOBS_TIMEOUT_SECONDS=900           # a plugin's run is killed after this unless its '# timeout:' line says otherwise
readonly JOBS_HUD_SECONDS=2                 # how long the engine's "job ok" banner stays up
readonly JOBS_NOTIFIER_TIMEOUT_SECONDS=10   # terminal-notifier occasionally never returns (seen on -remove); a banner is never worth a hang
# launchd's PATH has no Homebrew; plugins shell out to jq, terminal-notifier, python3.
readonly JOBS_LAUNCHD_PATH="/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
# The per-plugin jobs this framework replaced; install boots them out and removes their plists.
readonly -a JOBS_LEGACY_LABELS=("com.$(id -un).git-health" "com.$(id -un).aws-sso-autologin" "com.$(id -un).new-machine-verify")
typeset -gA JOB_PATH=() JOB_TIER=()         # name → executable, name → df | ldf; filled by jobs_discover

# Flags, set by main.
DRY_RUN=false
PRINT_DIR=false          # --dir: print the tier's bare repo path and exit
GIT_TIER=shared          # git / --dir act on one tier; --local picks the local one
GIT_ARGS=()              # everything after 'git', verbatim
JOBS_ARGS=()             # everything after 'jobs', verbatim
TIMING=false
PUSH_SCOPE=("${PUSH_PARTS[@]}")   # narrowed by --<part>, then --no-<part>
LOGS_PREVIOUS=false
LOGS_REPO=""
TOKEN=""              # the login's gh token, loaded before the first personal push; inherited by the background pushes
typeset -A PIDS STARTS   # background pushes in flight, by repo
