#!/usr/bin/env zsh
# A lane's worktree: --action open adds a worktree on its branch from a base and links the root's
# node_modules into it; --action handoff unlinks the symlink, expunges the worktree's Bazel output base
# (stopping its server), then removes the worktree, keeping the branch.
# Run: zsh $HOME/.claude/skills/ari-parallel-play/bin/worktree.zsh --help

set -euo pipefail

readonly SCRIPT_DIR="${0:A:h}"
readonly SKILLS_DIR="${HOME}/.claude/skills"
readonly LIB_LOGGING="${SKILLS_DIR}/ari-skill-shellscripts/lib/logging.zsh"
if [[ ! -r "${LIB_LOGGING}" ]]; then
  print -u2 "[ERROR] missing shared logging lib | path='${LIB_LOGGING}'"
  exit 1
fi
source "${LIB_LOGGING}"

# --- Constants ---

readonly VALID_ACTIONS=(open handoff)
readonly DEFAULT_BASE="origin/main"

help() {
  cat <<EOF
${c_green}worktree${c_rst} — open a lane's worktree with the shared node_modules, or hand it off keeping the branch

${c_bold}Usage:${c_rst}
  zsh $HOME/.claude/skills/ari-parallel-play/bin/worktree.zsh --action open --root DIR --dir DIR --branch NAME [--base REF] [--dry-run]
  zsh $HOME/.claude/skills/ari-parallel-play/bin/worktree.zsh --action handoff --root DIR --dir DIR [--dry-run]

${c_bold}Options:${c_rst}
  --action A     ${(j:|:)VALID_ACTIONS}
  --root DIR     The main checkout (its node_modules is linked, never copied or installed)
  --dir DIR      The worktree directory
  --branch NAME  The lane's branch (open: created from --base when it does not exist)
  --base REF     Where a new branch starts (default: ${DEFAULT_BASE}; a stack tip like origin/<game>-stack)
  --dry-run      Log what would happen, change nothing
  -h, --help     Show this help

Both actions are idempotent. Handoff never deletes the branch and never removes a node_modules that is not a symlink.
EOF
}

#######################################
# Check that required binaries are installed.
# Returns: 1 if any are missing
#######################################
check_prerequisites() {
  local missing=()
  for cmd in git; do
    command -v "${cmd}" >/dev/null 2>&1 || missing+=("${cmd}")
  done
  if (( ${#missing} > 0 )); then
    log::err "Missing required commands | missing='${(j:, :)missing}'"
    return 1
  fi
}

#######################################
# Check if a value is in an array of valid options.
# Arguments:
#   $1 - value; $2.. - options
# Returns: 0 if valid
#######################################
is_valid_option() {
  local val="${1}"; shift
  for opt in "${@}"; do
    [[ "${val}" == "${opt}" ]] && return 0
  done
  return 1
}

#######################################
# Run a mutation, or log it under --dry-run.
# Globals: DRY_RUN
# Arguments: the command
#######################################
mutate() {
  if [[ "${DRY_RUN}" == "true" ]]; then
    log::info "Dry run | command='${*}'"
    return 0
  fi
  run_cmd "${@}"
}

#######################################
# Add the worktree unless the directory already is one.
# Globals: DRY_RUN
# Arguments:
#   $1 - root; $2 - dir; $3 - branch; $4 - base
#######################################
open_worktree() {
  local root="${1}" dir="${2}" branch="${3}" base="${4}"
  if [[ -d "${dir}" ]] && git -C "${dir}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    local current
    current="$(git -C "${dir}" branch --show-current)"
    if [[ "${current}" != "${branch}" ]]; then
      log::err "Directory holds another lane's worktree | dir='${dir}' current='${current}' expected='${branch}'"
      return 1
    fi
    log::info "Worktree exists | dir='${dir}' branch='${current}'"
    return 0
  fi
  if git -C "${root}" show-ref --verify --quiet "refs/heads/${branch}"; then
    log::info "Branch exists; checking it out | branch='${branch}'"
    mutate git -C "${root}" worktree add "${dir}" "${branch}"
    return 0
  fi
  log::info "Creating the branch | branch='${branch}' base='${base}'"
  mutate git -C "${root}" worktree add -b "${branch}" "${dir}" "${base}"
}

#######################################
# Link the root's node_modules into the worktree unless a link is already there.
# Globals: DRY_RUN
# Arguments:
#   $1 - root; $2 - dir
# Returns: 1 when a real node_modules directory sits there
#######################################
link_modules() {
  local root="${1}" dir="${2}" target="${dir}/node_modules"
  if [[ -L "${target}" ]]; then
    log::info "node_modules already linked | target='${target}'"
    return 0
  fi
  if [[ -e "${target}" ]]; then
    log::err "node_modules is a real path, refusing to replace it | target='${target}'"
    return 1
  fi
  mutate ln -s "${root}/node_modules" "${target}"
}

#######################################
# Unlink the node_modules symlink, expunge the Bazel output base (which stops the worktree's
# server), then remove the worktree; the branch stays.
# Globals: DRY_RUN
# Arguments:
#   $1 - root; $2 - dir
# Returns: 1 when node_modules is a real directory (never removed by this script)
#######################################
handoff_worktree() {
  local root="${1}" dir="${2}" target="${dir}/node_modules"
  if [[ ! -d "${dir}" ]]; then
    log::info "Worktree already gone | dir='${dir}'"
    mutate git -C "${root}" worktree prune
    return 0
  fi
  if [[ -L "${target}" ]]; then
    mutate unlink "${target}"
  elif [[ -e "${target}" ]]; then
    log::err "node_modules is a real directory; a forced remove would delete it, refusing | target='${target}'"
    return 1
  fi
  local dirty
  dirty="$(git -C "${dir}" status --porcelain | wc -l | tr -d ' ')"
  if (( dirty > 0 )); then
    log::err "Worktree has uncommitted changes; commit or discard them first | dir='${dir}' changed_files='${dirty}'"
    return 1
  fi
  if [[ -f "${dir}/MODULE.bazel" ]]; then
    ( cd "${dir}" && mutate bazel clean --expunge_async )
  fi
  mutate git -C "${root}" worktree remove "${dir}"
  log::info "Branch kept | branch='$(git -C "${root}" branch --list | grep -c . || true) local branches'"
}

main() {
  check_prerequisites || exit 1

  # === PARSE ===
  local action="" root="" dir="" branch="" base="${DEFAULT_BASE}" dry_run=false
  while (( $# > 0 )); do case "${1}" in
    -h|--help)  help; return 0 ;;
    --action)   action="${2:?--action requires a value}"; shift 2 ;;
    --root)     root="${2:?--root requires a value}"; shift 2 ;;
    --dir)      dir="${2:?--dir requires a value}"; shift 2 ;;
    --branch)   branch="${2:?--branch requires a value}"; shift 2 ;;
    --base)     base="${2:?--base requires a ref}"; shift 2 ;;
    --dry-run)  dry_run=true; shift ;;
    -*)         log::err "Unknown flag | flag='${1}'"; help; return 1 ;;
    *)          log::err "Unexpected argument | argument='${1}'"; help; return 1 ;;
  esac; done

  # === MASSAGE ===
  action="${action:l}"
  typeset -g DRY_RUN="${dry_run}"

  # === VALIDATE ===
  is_valid_option "${action}" "${VALID_ACTIONS[@]}" || { log::err "Invalid --action | action='${action}' valid='${(j:, :)VALID_ACTIONS}'"; help; return 1; }
  [[ -n "${root}" && -n "${dir}" ]] || { log::err "Missing --root or --dir | root='${root}' dir='${dir}'"; help; return 1; }
  git -C "${root}" rev-parse --show-toplevel >/dev/null 2>&1 || { log::err "Not a git checkout | root='${root}'"; return 1; }
  [[ -d "${root}/node_modules" ]] || { log::err "The root has no node_modules to link | root='${root}'"; return 1; }
  if [[ "${action}" == "open" ]]; then
    [[ -n "${branch}" ]] || { log::err "Missing --branch for open"; help; return 1; }
  fi

  # === LOGIC ===
  if [[ "${action}" == "open" ]]; then
    open_worktree "${root}" "${dir}" "${branch}" "${base}"
    link_modules "${root}" "${dir}"
  else
    handoff_worktree "${root}" "${dir}"
  fi

  cat <<EOF
action=${action}
dir=${dir}
branch=${branch:-$(git -C "${dir}" branch --show-current 2>/dev/null || true)}
base=${base}
node_modules=${root}/node_modules
dry_run=${dry_run}
EOF
}

main "$@"
