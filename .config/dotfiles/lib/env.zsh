# dotfiles/lib/env.zsh — the environment variables, constants and flag defaults every module reads.
# Sourced by ~/.config/bin/dotfiles in no particular order: this file sets variables from $HOME and the
# environment only, and nothing else runs when it is sourced, so it needs no other module first (see README.md).

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
# The local tier's init hooks: each installs what its tier needs outside ~/.local (see help).
readonly LOCAL_INIT_HOOKS_DIR="${XDG_DATA_HOME:-${HOME}/.local/share}/dotfiles/init.d"
readonly KEEP_BACKUPS=1
readonly IDENTITY_CACHE="${STATE_DIR}/identity"   # '<sha256 of token> <login> <epoch>': whose token, verified when
readonly IDENTITY_TTL_SECONDS=$(( 7 * 24 * 3600 ))
readonly REGISTRY_LINK="${HOME}/.config/claude/skills/ari-dotfiles-skill-registry/bin/link"
readonly VALID_COMMANDS=(init pull push status logs git)
readonly PUSH_PARTS=(local submodules shared)   # in run order
# Submodule paths declared in ~/.gitmodules, relative to $HOME; empty when none.
SUBMODULES=("${(@f)$(git config -f "${GITMODULES}" --get-regexp '^submodule\..*\.path$' 2>/dev/null | awk '{print $2}' || true)}")
readonly -a SUBMODULES=("${(@)SUBMODULES:#}")

# Flags, set by main.
DRY_RUN=false
PRINT_DIR=false          # --dir: print the tier's bare repo path and exit
GIT_TIER=shared          # git / --dir act on one tier; --local picks the local one
GIT_ARGS=()              # everything after 'git', verbatim
TIMING=false
PUSH_SCOPE=("${PUSH_PARTS[@]}")   # narrowed by --<part>, then --no-<part>
LOGS_PREVIOUS=false
LOGS_REPO=""
TOKEN=""              # the login's gh token, loaded before the first personal push; inherited by the background pushes
typeset -A PIDS STARTS   # background pushes in flight, by repo
