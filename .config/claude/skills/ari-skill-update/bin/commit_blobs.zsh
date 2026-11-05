#!/usr/bin/env zsh
# Commit exactly the blobs a proposal recorded. Refuses, committing nothing,
# unless HEAD still holds the proposal's base and the working tree still yields
# the proposal's blobs; then stages those blobs in a private index (never
# `git add`, which takes the working tree as it is now, nor `commit -- <path>`,
# which does the same) and commits it. help() has the flags and output.

set -euo pipefail

readonly SCRIPT_DIR="${0:A:h}"
readonly SKILLS_DIR="${HOME}/.claude/skills"
readonly LIB_LOGGING="${SKILLS_DIR}/ari-skill-shellscripts/lib/logging.zsh"
if [[ ! -r "${LIB_LOGGING}" ]]; then
  print -u2 "[ERROR] missing shared logging lib | path='${LIB_LOGGING}'"
  exit 1
fi
source "${LIB_LOGGING}"

readonly LIB_REGISTRY="${SKILLS_DIR}/ari-dotfiles-skill-registry/lib/registry.zsh"
if [[ ! -r "${LIB_REGISTRY}" ]]; then
  print -u2 "[ERROR] missing skill registry lib | path='${LIB_REGISTRY}'"
  exit 1
fi
source "${LIB_REGISTRY}"
source "${SCRIPT_DIR:h}/lib/blobs.zsh"

readonly ADOPT="${SKILLS_DIR}/ari-dotfiles-skill-registry/bin/adopt"

# --- Prerequisites ---

#######################################
# Check that required binaries are installed.
# Globals: None
# Arguments: None
# Returns: 1 if any are missing
#######################################
check_prerequisites() {
  local missing=()
  for cmd in awk diff find git mktemp readlink sort; do
    command -v "${cmd}" >/dev/null 2>&1 || missing+=("${cmd}")
  done
  if (( ${#missing} > 0 )); then
    log::err "Missing required commands | missing='${(j:, :)missing}'"
    return 1
  fi
}

# --- Helpers ---

#######################################
# True (0) when HEAD already holds every proposed entry and the working tree
# matches HEAD at the skill directory: an earlier run committed the proposal.
# Arguments:
#   $1 - tier
#   $2 - source
#   $3 - skill directory, repo-relative
#   $4 - proposed entry lines
#######################################
is_already_committed() {
  local tier="${1}" source="${2}" skill_rel="${3}" proposed="${4}"
  [[ -z "$(changed_entries "${tier}" "${source}" "${skill_rel}" false)" ]] || return 1
  local line mode blob file held
  for line in "${(@f)proposed}"; do
    read -r mode blob file <<< "${line}"
    held="$(repo_git "${tier}" "${source}" ls-tree HEAD -- "${skill_rel}/${file}" | awk '{ print $1, $3 }' || true)"
    if [[ "${mode}" == "deleted" ]]; then
      [[ -z "${held}" ]] || return 1
      continue
    fi
    [[ "${held}" == "${mode} ${blob}" ]] || return 1
  done
}

#######################################
# Refuse unless the working tree still yields exactly the proposed entries,
# writing their blobs as it hashes: a match leaves the proposed content in the
# object store.
# Arguments:
#   $1 - tier
#   $2 - source
#   $3 - skill name
#   $4 - skill directory, repo-relative
#   $5 - adopt (true|false): hash the real directory not yet in a tier
#   $6 - proposed entry lines
# Returns: 1 on a mismatch
#######################################
require_working_tree_match() {
  local tier="${1}" source="${2}" skill="${3}" skill_rel="${4}" adopt="${5}" proposed="${6}"
  local current
  if [[ "${adopt}" == "true" ]]; then
    current="$(adopt_entries "${tier}" "${source}" "${SKILLS_DIR}/${skill}" "${skill_rel}" true)"
  else
    current="$(changed_entries "${tier}" "${source}" "${skill_rel}" true)"
  fi
  if [[ "${current}" == "${proposed}" ]]; then
    log::info "Working tree matches the proposal | skill='${skill}' adopt='${adopt}'"
    return 0
  fi
  local mismatched
  mismatched="$(mismatched_paths "${proposed}" "${current}")"
  log::err "Working tree no longer matches the proposal; nothing committed | mismatched='${mismatched}' hint='send the driver re-propose'"
  print -r -- "result=refused"
  print -r -- "mismatched=${mismatched}"
  return 1
}

#######################################
# Refuse unless HEAD holds the skill directory the proposal was diffed against,
# so the commit's diff is the proposal's diff.
# Arguments:
#   $1 - tier
#   $2 - source
#   $3 - skill directory, repo-relative
#   $4 - the proposal's base tree (or none)
# Returns: 1 when HEAD moved under the proposal
#######################################
require_base_tree() {
  local tier="${1}" source="${2}" skill_rel="${3}" proposed_base="${4}"
  local current_base
  current_base="$(base_tree "${tier}" "${source}" "${skill_rel}")"
  if [[ "${current_base}" == "${proposed_base}" ]]; then
    return 0
  fi
  log::err "HEAD changed the skill since the proposal; nothing committed | proposed_base='${proposed_base}' current_base='${current_base}' hint='send the driver re-propose'"
  print -r -- "result=refused"
  print -r -- "mismatched=HEAD:${skill_rel}"
  return 1
}

#######################################
# Adopt the skill into its tier unless an earlier run already did.
# Globals: ADOPT, SKILLS_DIR
# Arguments:
#   $1 - skill name
#   $2 - tier
#######################################
adopt_unless_linked() {
  local skill="${1}" tier="${2}"
  if [[ -L "${SKILLS_DIR}/${skill}" ]]; then
    log::info "Already adopted | skill='${skill}' link='${SKILLS_DIR}/${skill}'"
    return 0
  fi
  log::info "Adopting before the commit | skill='${skill}' tier='${tier}'"
  zsh "${ADOPT}" --skill "${skill}" --tier "${tier}" >&2
}

#######################################
# Stage the proposed entries over HEAD in the given index file.
# Arguments:
#   $1 - tier
#   $2 - source
#   $3 - skill directory, repo-relative
#   $4 - index file
#   $5 - proposed entry lines
#######################################
stage_entries() {
  local tier="${1}" source="${2}" skill_rel="${3}" index="${4}" proposed="${5}"
  local line mode blob file
  GIT_INDEX_FILE="${index}" repo_git "${tier}" "${source}" read-tree HEAD
  for line in "${(@f)proposed}"; do
    [[ -n "${line}" ]] || continue
    read -r mode blob file <<< "${line}"
    if [[ "${mode}" == "deleted" ]]; then
      GIT_INDEX_FILE="${index}" repo_git "${tier}" "${source}" update-index --force-remove -- "${skill_rel}/${file}"
      continue
    fi
    GIT_INDEX_FILE="${index}" repo_git "${tier}" "${source}" update-index --add --cacheinfo "${mode},${blob},${skill_rel}/${file}"
  done
}

#######################################
# Print the entry lines a tree-ish holds against HEAD at the skill directory:
# the index file's staged content, or a commit's against its parent.
# Arguments:
#   $1 - tier
#   $2 - source
#   $3 - skill directory, repo-relative
#   $4 - `--cached` (with $5 the index file) or a commit
#   $5 - index file, for --cached
#######################################
entries_of() {
  local tier="${1}" source="${2}" skill_rel="${3}" what="${4}" index="${5:-}"
  local -a raw
  if [[ "${what}" == "--cached" ]]; then
    raw=("${(@f)$(GIT_INDEX_FILE="${index}" repo_git "${tier}" "${source}" diff-index --cached --no-renames HEAD)}")
  else
    raw=("${(@f)$(repo_git "${tier}" "${source}" diff-tree -r --no-renames --root --no-commit-id "${what}")}")
  fi
  print -rl -- "${raw[@]}" | awk -v p="${skill_rel}/" '
    NF {
      split($0, tab, "\t"); split(tab[1], f, " "); file = tab[2]
      if (index(file, p) != 1) { print "outside - " file; next }
      file = substr(file, length(p) + 1)
      if (f[5] == "D") print "deleted - " file
      else print f[2] " " f[4] " " file
    }' | sort -k3
}

#######################################
# Point the shared index at the committed blobs for the proposal's paths, so the
# tier's status is clean; a path another session staged since is left alone.
# Arguments:
#   $1 - tier
#   $2 - source
#   $3 - skill directory, repo-relative
#   $4 - proposed entry lines
#   $5 - the commit's parent
#######################################
sync_shared_index() {
  local tier="${1}" source="${2}" skill_rel="${3}" proposed="${4}" parent="${5}"
  local line mode blob file staged before
  for line in "${(@f)proposed}"; do
    [[ -n "${line}" ]] || continue
    read -r mode blob file <<< "${line}"
    staged="$(repo_git "${tier}" "${source}" ls-files -s -- "${skill_rel}/${file}" | awk '{ print $1, $2 }')"
    before="$(repo_git "${tier}" "${source}" ls-tree "${parent}" -- "${skill_rel}/${file}" 2>/dev/null | awk '{ print $1, $3 }' || true)"
    if [[ "${mode}" == "deleted" ]]; then
      [[ -z "${staged}" ]] && continue
      if [[ "${staged}" != "${before}" ]]; then
        log::warn "Left another session's staged entry | file='${file}' staged='${staged}'"
        continue
      fi
      repo_git "${tier}" "${source}" update-index --force-remove -- "${skill_rel}/${file}"
      continue
    fi
    [[ "${staged}" == "${mode} ${blob}" ]] && continue
    if [[ -n "${staged}" && "${staged}" != "${before}" ]]; then
      log::warn "Left another session's staged entry | file='${file}' staged='${staged}'"
      continue
    fi
    repo_git "${tier}" "${source}" update-index --add --cacheinfo "${mode},${blob},${skill_rel}/${file}"
  done
}

# --- Help ---

help() {
  cat <<EOF
${c_green}commit_blobs${c_rst} — commit exactly the blobs a proposal recorded, or refuse

${c_bold}Usage:${c_rst}
  zsh \$HOME/.claude/skills/ari-skill-update/bin/commit_blobs.zsh --skill <name> --tier <df|ldf> --base-tree <tree|none> --message <msg> [--source submodule:<path>] [--adopt] [--blob <mode>:<blob>:<path>]... [--delete <path>]... [--dry-run]

${c_bold}Options:${c_rst}
  --skill NAME         Skill to commit (required)
  --tier TIER          df or ldf (required)
  --source SOURCE      submodule:<path> when a submodule's repo versions the skill
  --base-tree TREE     HEAD's tree at the skill dir when the proposal was recorded, or none (required)
  --message MSG        Commit message (required)
  --adopt              Adopt the skill into --tier first (registry adopt)
  --blob SPEC          <mode>:<blob>:<path relative to the skill dir>; repeat
  --delete PATH        A file the proposal removes, relative to the skill dir; repeat
  --dry-run            Check and stage in the private index; commit nothing
  -h, --help           Show this help

record_blobs.zsh writes this command into the proposal; run it as written.

${c_bold}Output:${c_rst}
  key=value lines: result (committed | already-committed | dry-run | refused), sha, mismatched.
  Exit 1 on a refusal or an error; a refusal commits nothing.
EOF
}

# --- Main ---

main() {
  check_prerequisites || exit 1

  # === PARSE ===
  local skill="" tier="" source="" proposed_base="" message="" adopt=false dry_run=false
  local -a specs=() deletes=()
  while (( $# > 0 )); do case "${1}" in
    -h|--help)   help; return 0 ;;
    --skill)     skill="${2:?--skill requires a value}"; shift 2 ;;
    --tier)      tier="${2:?--tier requires a value}"; shift 2 ;;
    --source)    source="${2?--source requires a value}"; shift 2 ;;
    --base-tree) proposed_base="${2:?--base-tree requires a value}"; shift 2 ;;
    --message)   message="${2:?--message requires a value}"; shift 2 ;;
    --blob)      specs+=("${2:?--blob requires a value}"); shift 2 ;;
    --delete)    deletes+=("${2:?--delete requires a value}"); shift 2 ;;
    --adopt)     adopt=true; shift ;;
    --dry-run)   dry_run=true; shift ;;
    -*)          log::err "Unknown flag | flag='${1}'"; help; return 1 ;;
    *)           log::err "Unexpected argument | argument='${1}'"; help; return 1 ;;
  esac; done

  # === MASSAGE ===
  tier="${tier:l}"
  local -a lines=()
  local spec mode blob file
  for spec in "${specs[@]}"; do
    mode="${spec%%:*}"; spec="${spec#*:}"
    blob="${spec%%:*}"; file="${spec#*:}"
    lines+=("${mode} ${blob} ${file}")
  done
  for file in "${deletes[@]}"; do
    lines+=("deleted - ${file}")
  done
  local proposed
  proposed="$(print -rl -- "${lines[@]}" | awk 'NF' | sort -k3)"

  # === VALIDATE ===
  local -a missing=()
  [[ -n "${skill}" ]] || missing+=(--skill)
  [[ -n "${tier}" ]] || missing+=(--tier)
  [[ -n "${proposed_base}" ]] || missing+=(--base-tree)
  [[ -n "${message}" ]] || missing+=(--message)
  (( ${#lines} > 0 )) || missing+=(--blob/--delete)
  if (( ${#missing} > 0 )); then
    log::err "Missing required flags | missing='${(j:, :)missing}'"
    help
    return 1
  fi
  if ! is_valid_tier "${tier}"; then
    log::err "Invalid tier | tier='${tier}' valid_tiers='${(j:, :)TIERS}'"
    return 1
  fi
  local line
  for line in "${lines[@]}"; do
    read -r mode blob file <<< "${line}"
    if [[ ! "${mode} ${blob}" =~ '^(100644|100755|120000) [0-9a-f]{40,64}$|^deleted -$' || -z "${file}" || "${file}" == (/*|*..*) ]]; then
      log::err "Invalid entry | line='${line}' expected='<100644|100755|120000>:<blob>:<relative path>, or --delete <relative path>'"
      return 1
    fi
  done

  # === LOGIC ===
  local skill_rel
  skill_rel="$(repo_skill_rel "${tier}" "${source}" "${skill}")"

  local adopt_pending="${adopt}"
  [[ "${adopt}" == "true" && -L "${SKILLS_DIR}/${skill}" ]] && adopt_pending=false
  if [[ "${adopt_pending}" == "false" ]] && is_already_committed "${tier}" "${source}" "${skill_rel}" "${proposed}"; then
    local head
    head="$(repo_git "${tier}" "${source}" rev-parse HEAD)"
    log::info "HEAD already holds the proposal's blobs | head='${head}'"
    sync_shared_index "${tier}" "${source}" "${skill_rel}" "${proposed}" "${head}~1"
    print -r -- "result=already-committed"
    print -r -- "sha=${head}"
    return 0
  fi
  require_base_tree "${tier}" "${source}" "${skill_rel}" "${proposed_base}" || return 1
  require_working_tree_match "${tier}" "${source}" "${skill}" "${skill_rel}" "${adopt_pending}" "${proposed}" || return 1

  if [[ "${dry_run}" == "true" ]]; then
    log::info "Dry run: would adopt (if pending), stage the proposal's blobs and commit | skill='${skill}' adopt_pending='${adopt_pending}'"
    print -r -- "result=dry-run"
    return 0
  fi

  if [[ "${adopt_pending}" == "true" ]]; then
    adopt_unless_linked "${skill}" "${tier}"
    require_working_tree_match "${tier}" "${source}" "${skill}" "${skill_rel}" false "${proposed}" || return 1
  fi

  local index_dir
  index_dir="$(mktemp -d)"
  trap "rm -rf -- ${(q)index_dir}" EXIT
  local index="${index_dir}/index"
  stage_entries "${tier}" "${source}" "${skill_rel}" "${index}" "${proposed}"

  local staged
  staged="$(entries_of "${tier}" "${source}" "${skill_rel}" --cached "${index}")"
  local parent
  parent="$(repo_git "${tier}" "${source}" rev-parse HEAD)"
  if [[ "${staged}" != "${proposed}" ]]; then
    log::err "Staged content differs from the proposal; nothing committed | mismatched='$(mismatched_paths "${proposed}" "${staged}")'"
    print -r -- "result=refused"
    return 1
  fi

  GIT_INDEX_FILE="${index}" repo_git "${tier}" "${source}" commit -q -m "${message}" >&2
  local sha committed
  sha="$(repo_git "${tier}" "${source}" rev-parse HEAD)"
  committed="$(entries_of "${tier}" "${source}" "${skill_rel}" "${sha}")"
  sync_shared_index "${tier}" "${source}" "${skill_rel}" "${proposed}" "${parent}"
  if [[ "${committed}" != "${proposed}" ]]; then
    log::err "The commit differs from the proposal | sha='${sha}' mismatched='$(mismatched_paths "${proposed}" "${committed}")'"
    print -r -- "result=committed-differs"
    print -r -- "sha=${sha}"
    return 1
  fi
  log::info "Committed exactly the proposal's blobs | sha='${sha}' skill='${skill}'"

  cat <<EOF
result=committed
sha=${sha}
EOF
}

main "${@}"
