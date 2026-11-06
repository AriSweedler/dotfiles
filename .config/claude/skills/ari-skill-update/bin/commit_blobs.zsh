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
source "${SKILLS_DIR}/ari-skill-shellscripts/lib/dry_run.zsh"
readonly SCRIPT_PATH="${0:a}"

readonly LIB_REGISTRY="${SKILLS_DIR}/ari-dotfiles-skill-registry/lib/registry.zsh"
if [[ ! -r "${LIB_REGISTRY}" ]]; then
  print -u2 "[ERROR] missing skill registry lib | path='${LIB_REGISTRY}'"
  exit 1
fi
source "${LIB_REGISTRY}"
source "${SCRIPT_DIR:h}/lib/blobs.zsh"
source "${SCRIPT_DIR:h}/lib/claim.zsh"

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
  local -a shared=("${(@f)$(print -r -- "${proposed}" | shared_paths_of)}")
  shared=("${(@)shared:#}")
  if (( ${#shared} > 0 )); then
    [[ -z "$(shared_entries "${tier}" "${source}" false "${shared[@]}")" ]] || return 1
  fi
  local line mode blob file held
  for line in "${(@f)proposed}"; do
    read -r mode blob file <<< "${line}"
    held="$(repo_git "${tier}" "${source}" ls-tree HEAD -- "$(entry_repo_path "${skill_rel}" "${file}")" | awk '{ print $1, $3 }' || true)"
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
  local -a shared=("${(@f)$(print -r -- "${proposed}" | shared_paths_of)}")
  shared=("${(@)shared:#}")
  if (( ${#shared} > 0 )); then
    current="$(merge_entries "${current}" "$(shared_entries "${tier}" "${source}" true "${shared[@]}")")"
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
# Refuse unless HEAD still holds, at each shared path, the blob the proposal was
# diffed against (the shared files' counterpart of the base tree).
# Arguments:
#   $1 - tier
#   $2 - source
#   $3 - lines `<head blob|none> <repo-relative path>`
# Returns: 1 when HEAD moved under the proposal
#######################################
require_shared_base() {
  local tier="${1}" source="${2}" heads="${3}" line recorded rel current
  for line in "${(@f)heads}"; do
    [[ -n "${line}" ]] || continue
    recorded="${line%% *}"; rel="${line#* }"
    current="$(head_blob "${tier}" "${source}" "${rel}")"
    [[ "${current}" == "${recorded}" ]] && continue
    log::err "HEAD changed a shared file since the proposal; nothing committed | file='${rel}' proposed_base='${recorded}' current_base='${current}' hint='send the driver re-propose'"
    print -r -- "result=refused"
    print -r -- "mismatched=HEAD:${rel}"
    return 1
  done
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
  run_mut run_adopt "${skill}" "${tier}"
}

#######################################
# Run the registry adopt with its stdout on stderr. The registry adopt is a dry run unless
# --execute is on its command line, so this passes it; callers reach this through run_mut.
# Globals: ADOPT
# Arguments:
#   $1 - skill name
#   $2 - tier
#######################################
run_adopt() {
  zsh "${ADOPT}" --skill "${1}" --tier "${2}" --execute >&2
}

#######################################
# Commit the index file's content with the tier's hooks, their stdout on stderr.
# Arguments:
#   $1 - tier
#   $2 - source
#   $3 - index file
#   $4 - message
#######################################
commit_index() {
  GIT_INDEX_FILE="${3}" repo_git "${1}" "${2}" commit -q -m "${4}" >&2
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
    file="$(entry_repo_path "${skill_rel}" "${file}")"
    if [[ "${mode}" == "deleted" ]]; then
      GIT_INDEX_FILE="${index}" repo_git "${tier}" "${source}" update-index --force-remove -- "${file}"
      continue
    fi
    GIT_INDEX_FILE="${index}" repo_git "${tier}" "${source}" update-index --add --cacheinfo "${mode},${blob},${file}"
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
  local roots="${(j.:.)$(shared_roots "${tier}")}"
  print -rl -- "${raw[@]}" | awk -v p="${skill_rel}/" -v roots="${roots}" -v sp="${SHARED_ENTRY_PREFIX}" '
    NF {
      split($0, tab, "\t"); split(tab[1], f, " "); file = tab[2]
      n = split(roots, rs, ":"); shared = 0
      for (i = 1; i <= n; i++) if (rs[i] != "" && index(file, rs[i] "/") == 1) shared = 1
      if (shared) file = sp file
      else if (index(file, p) != 1) { print "outside - " file; next }
      else file = substr(file, length(p) + 1)
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
    file="$(entry_repo_path "${skill_rel}" "${file}")"
    staged="$(repo_git "${tier}" "${source}" ls-files -s -- "${file}" | awk '{ print $1, $2 }')"
    before="$(repo_git "${tier}" "${source}" ls-tree "${parent}" -- "${file}" 2>/dev/null | awk '{ print $1, $3 }' || true)"
    if [[ "${mode}" == "deleted" ]]; then
      [[ -z "${staged}" ]] && continue
      if [[ "${staged}" != "${before}" ]]; then
        log::warn "Left another session's staged entry | file='${file}' staged='${staged}'"
        continue
      fi
      run_mut repo_git "${tier}" "${source}" update-index --force-remove -- "${file}"
      continue
    fi
    [[ "${staged}" == "${mode} ${blob}" ]] && continue
    if [[ -n "${staged}" && "${staged}" != "${before}" ]]; then
      log::warn "Left another session's staged entry | file='${file}' staged='${staged}'"
      continue
    fi
    run_mut repo_git "${tier}" "${source}" update-index --add --cacheinfo "${mode},${blob},${file}"
  done
}

#######################################
# Refuse, committing nothing, while another live driver holds the skill's claim.
# Without --claim-dir (an older Commit command) there is no claim to check.
# Globals: None
# Arguments:
#   $1 - skill name
#   $2 - claim-dir (empty when not given)
# Returns: 1 when another live driver holds the claim
#######################################
require_claim_not_held_by_other() {
  local skill="${1}" claim_dir="${2}" blocker
  [[ -n "${claim_dir}" ]] || return 0
  blocker="$(claim_blocker "${skill}" "${claim_dir}")"
  [[ -n "${blocker}" ]] || return 0
  log::err "Another driver holds this skill; nothing committed | skill='${skill}' owner='${blocker}' hint='send the driver re-propose once that driver lands or stops'"
  print -r -- "result=refused"
  print -r -- "claim_holder=${blocker}"
  return 1
}

#######################################
# Release the claim after a commit; a dry run keeps it.
# Globals: None
# Arguments:
#   $1 - skill name
#   $2 - claim-dir (empty when not given)
#######################################
release_claim() {
  local skill="${1}" claim_dir="${2}"
  [[ -n "${claim_dir}" ]] || return 0
  if is_dry_run; then
    log::info "would release | what='the skill claim' skill='${skill}'"
    return 0
  fi
  claim_release "${skill}" "${claim_dir}"
  log::info "Released the skill claim | skill='${skill}'"
}

# --- Help ---

help() {
  cat <<EOF
${c_green}commit_blobs${c_rst} — commit exactly the blobs a proposal recorded, or refuse

${c_bold}Usage:${c_rst}
  zsh \$HOME/.claude/skills/ari-skill-update/bin/commit_blobs.zsh --skill <name> --tier <df|ldf> --base-tree <tree|none> --message <msg> [--source submodule:<path>] [--claim-dir <dir>] [--adopt] [--blob <mode>:<blob>:<path>]... [--delete <path>]... [--shared <head>:<mode>:<blob>:<path>]... [--shared-delete <head>:<path>]... [--execute] [--dry-run]

${c_bold}Options:${c_rst}
  --skill NAME         Skill to commit (required)
  --tier TIER          df or ldf (required)
  --source SOURCE      submodule:<path> when a submodule's repo versions the skill
  --base-tree TREE     HEAD's tree at the skill dir when the proposal was recorded, or none (required)
  --claim-dir DIR      The investigation folder that owns the skill's claim (record_blobs.zsh writes it):
                       refuses while another live driver holds the claim, releases it once committed
  --message MSG        Commit message (required)
  --adopt              Adopt the skill into --tier first (registry adopt)
  --blob SPEC          <mode>:<blob>:<path relative to the skill dir>; repeat
  --delete PATH        A file the proposal removes, relative to the skill dir; repeat
  --shared SPEC        A shared file outside the skill dir (under the tier's lib root, ~/.config/claude/lib for df):
                       <HEAD's blob when recorded, or none>:<mode>:<blob>:<path relative to the repo root>; repeat.
                       Refused unless the path is under an allowed root and HEAD and the working tree still match
  --shared-delete SPEC A shared file the proposal removes: <HEAD's blob when recorded>:<path relative to the repo root>; repeat
  --execute            Adopt (if --adopt) and commit; without it the run is a dry run
  --dry-run            The default made explicit; wins over --execute and exports DRY_RUN=1
  -h, --help           Show this help

record_blobs.zsh writes this command into the proposal; run it as written.

${c_bold}Output:${c_rst}
  key=value lines: result (committed | already-committed | dry-run | refused), sha, mismatched,
  dry_run (1 | 0). A dry run runs every check and stages in the private index; it adopts and
  commits nothing and logs the exact rerun with --execute.
  Exit 1 on a refusal or an error; a refusal commits nothing. A claim held by another live driver
  is a refusal (result=refused, claim_holder=<its folder>).

${c_bold}Environment:${c_rst}
  DRY_RUN              Set and not 0 (a parent's dry run): a dry run, --execute or not; 0 alone never acts
EOF
}

# --- Main ---

main() {
  check_prerequisites || exit 1

  # === PARSE ===
  local skill="" tier="" source="" proposed_base="" message="" claim_dir="" adopt=false execute=false dry_run_flag=false
  local -a specs=() deletes=() shared_specs=() shared_deletes=()
  while (( $# > 0 )); do case "${1}" in
    -h|--help)   help; return 0 ;;
    --skill)     skill="${2:?--skill requires a value}"; shift 2 ;;
    --tier)      tier="${2:?--tier requires a value}"; shift 2 ;;
    --source)    source="${2?--source requires a value}"; shift 2 ;;
    --base-tree) proposed_base="${2:?--base-tree requires a value}"; shift 2 ;;
    --message)   message="${2:?--message requires a value}"; shift 2 ;;
    --claim-dir) claim_dir="${2:?--claim-dir requires a value}"; shift 2 ;;
    --blob)     specs+=("${2:?--blob requires a value}"); shift 2 ;;
    --delete)    deletes+=("${2:?--delete requires a value}"); shift 2 ;;
    --shared)        shared_specs+=("${2:?--shared requires a value}"); shift 2 ;;
    --shared-delete) shared_deletes+=("${2:?--shared-delete requires a value}"); shift 2 ;;
    --adopt)     adopt=true; shift ;;
    --execute)   execute=true; shift ;;
    --dry-run)   dry_run_flag=true; shift ;;
    -*)          log::err "Unknown flag | flag='${1}'"; help; return 1 ;;
    *)           log::err "Unexpected argument | argument='${1}'"; help; return 1 ;;
  esac; done
  resolve_dry_run "${execute}" "${dry_run_flag}" || return 1

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
  local head_blob_recorded shared_heads=""
  for spec in "${shared_specs[@]}"; do
    [[ "${spec}" == *:*:*:?* ]] || { log::err "--shared needs <head>:<mode>:<blob>:<path> | value='${spec}'"; return 1; }
    head_blob_recorded="${spec%%:*}"; spec="${spec#*:}"
    mode="${spec%%:*}"; spec="${spec#*:}"
    blob="${spec%%:*}"; file="${spec#*:}"
    [[ "${head_blob_recorded}" =~ '^([0-9a-f]{40,64}|none)$' ]] || { log::err "--shared head must be a blob id or none | head='${head_blob_recorded}'"; return 1; }
    lines+=("${mode} ${blob} ${SHARED_ENTRY_PREFIX}${file}")
    shared_heads+="${head_blob_recorded} ${file}"$'\n'
  done
  for spec in "${shared_deletes[@]}"; do
    [[ "${spec}" == *:?* ]] || { log::err "--shared-delete needs <head>:<path> | value='${spec}'"; return 1; }
    head_blob_recorded="${spec%%:*}"; file="${spec#*:}"
    [[ "${head_blob_recorded}" =~ '^([0-9a-f]{40,64}|none)$' ]] || { log::err "--shared-delete head must be a blob id or none | head='${head_blob_recorded}'"; return 1; }
    lines+=("deleted - ${SHARED_ENTRY_PREFIX}${file}")
    shared_heads+="${head_blob_recorded} ${file}"$'\n'
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
    if [[ "${file}" == "${SHARED_ENTRY_PREFIX}"* ]]; then
      if [[ -n "${source}" ]] || ! is_shared_path "${tier}" "${file#${SHARED_ENTRY_PREFIX}}"; then
        log::err "Shared file outside the tier's shared roots; nothing committed | file='${file#${SHARED_ENTRY_PREFIX}}' tier='${tier}' source='${source}' allowed_roots='${(j:, :)$(shared_roots "${tier}")}'"
        return 1
      fi
    fi
    if [[ ! "${mode} ${blob}" =~ '^(100644|100755|120000) [0-9a-f]{40,64}$|^deleted -$' || -z "${file}" || "${file}" == (/*|*..*) ]]; then
      log::err "Invalid entry | line='${line}' expected='<100644|100755|120000>:<blob>:<relative path>, or --delete <relative path>'"
      return 1
    fi
  done

  # === LOGIC ===
  local skill_rel
  skill_rel="$(repo_skill_rel "${tier}" "${source}" "${skill}")"
  require_claim_not_held_by_other "${skill}" "${claim_dir}" || return 1

  local adopt_pending="${adopt}"
  [[ "${adopt}" == "true" && -L "${SKILLS_DIR}/${skill}" ]] && adopt_pending=false
  if [[ "${adopt_pending}" == "false" ]] && is_already_committed "${tier}" "${source}" "${skill_rel}" "${proposed}"; then
    local head
    head="$(repo_git "${tier}" "${source}" rev-parse HEAD)"
    log::info "HEAD already holds the proposal's blobs | head='${head}'"
    sync_shared_index "${tier}" "${source}" "${skill_rel}" "${proposed}" "${head}~1"
    release_claim "${skill}" "${claim_dir}"
    cat <<EOF
result=already-committed
sha=${head}
dry_run=${DRY_RUN}
EOF
    report_dry_run "${SCRIPT_PATH}" "${ARGS[@]}"
    return 0
  fi
  require_base_tree "${tier}" "${source}" "${skill_rel}" "${proposed_base}" || return 1
  require_shared_base "${tier}" "${source}" "${shared_heads}" || return 1
  require_working_tree_match "${tier}" "${source}" "${skill}" "${skill_rel}" "${adopt_pending}" "${proposed}" || return 1

  if [[ "${adopt_pending}" == "true" ]]; then
    adopt_unless_linked "${skill}" "${tier}"
    if ! is_dry_run; then
      require_working_tree_match "${tier}" "${source}" "${skill}" "${skill_rel}" false "${proposed}" || return 1
    fi
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

  run_mut commit_index "${tier}" "${source}" "${index}" "${message}"
  if is_dry_run; then
    log::info "Dry run: the proposal's blobs stage cleanly | skill='${skill}' adopt_pending='${adopt_pending}'"
    cat <<EOF
result=dry-run
dry_run=${DRY_RUN}
EOF
    report_dry_run "${SCRIPT_PATH}" "${ARGS[@]}"
    return 0
  fi
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
  release_claim "${skill}" "${claim_dir}"

  cat <<EOF
result=committed
sha=${sha}
dry_run=${DRY_RUN}
EOF
  report_dry_run "${SCRIPT_PATH}" "${ARGS[@]}"
}

readonly -a ARGS=("${@}")
main "${@}"
