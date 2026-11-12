#!/usr/bin/env zsh
# Record a proposal's blobs: hash every file of the skill that differs from HEAD
# (all of them for an adoption), write the diff Ari will see, and write the
# Commit command that lands exactly those blobs. help() has the flags and output.

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

# --- Prerequisites ---

#######################################
# Check that required binaries are installed.
# Globals: None
# Arguments: None
# Returns: 1 if any are missing
#######################################
check_prerequisites() {
  local missing=()
  for cmd in awk diff find git paste readlink sort; do
    command -v "${cmd}" >/dev/null 2>&1 || missing+=("${cmd}")
  done
  if (( ${#missing} > 0 )); then
    log::err "Missing required commands | missing='${(j:, :)missing}'"
    return 1
  fi
}

# --- Helpers ---

#######################################
# Print the entry lines for the skill: an adoption hashes its real directory,
# anything else what its tier's working tree holds against HEAD.
# Globals: SKILLS_DIR
# Arguments:
#   $1 - tier
#   $2 - source
#   $3 - skill name
#   $4 - skill directory, repo-relative
#   $5 - adopt (true|false)
#   $6 - write (true|false)
#######################################
entries_for() {
  local tier="${1}" source="${2}" skill="${3}" skill_rel="${4}" adopt="${5}" write="${6}"
  if [[ "${adopt}" == "true" ]]; then
    adopt_entries "${tier}" "${source}" "${SKILLS_DIR}/${skill}" "${skill_rel}" "${write}"
    return
  fi
  changed_entries "${tier}" "${source}" "${skill_rel}" "${write}"
}

#######################################
# Print an --edited value relative to the skill directory, or nothing when it
# lies outside it. A relative value is taken from the skill directory. Both
# sides resolve symlinks and `..`, so the $HOME/.claude/skills path and the
# tier's real path match alike.
# Arguments:
#   $1 - skill directory
#   $2 - the --edited value
#######################################
skill_relative_path() {
  local skill_dir="${1}" file="${2}"
  [[ "${file}" == /* ]] || file="${skill_dir}/${file}"
  local real_dir="${skill_dir:A}" real_file="${file:A}"
  # A symlink the skill holds is recorded under its own name, not its target's.
  [[ -L "${file}" ]] && real_file="${file:h:A}/${file:t}"
  if [[ "${real_file}" != "${real_dir}/"?* ]]; then
    log::debug "--edited path is outside the skill directory | file='${file}' real_dir='${real_dir}'"
    return
  fi
  log::debug "Resolved an --edited path | file='${file}' real_dir='${real_dir}'"
  print -r -- "${real_file#${real_dir}/}"
}

#######################################
# Print a --shared value as a path relative to the tier's repo root, or nothing
# when it is not a file (or a tracked, now-deleted file) under an allowed shared
# root. Symlinks in the directory part resolve; the file's own name does not.
# Arguments:
#   $1 - tier
#   $2 - source
#   $3 - the --shared value (absolute, or relative to $HOME)
#######################################
shared_relative_path() {
  local tier="${1}" source="${2}" file="${3}"
  [[ "${file}" == /* ]] || file="${HOME}/${file}"
  local real_root real_file
  real_root="$(repo_root "${tier}" "${source}")"
  real_root="${real_root:A}"
  real_file="${file:h:A}/${file:t}"
  [[ "${real_file}" == "${real_root}/"?* ]] || return 0
  local rel="${real_file#${real_root}/}"
  is_shared_path "${tier}" "${rel}" || return 0
  print -r -- "${rel}"
}

#######################################
# Print the diff of each shared path against HEAD, untracked files included.
# Arguments:
#   $1 - tier
#   $2 - source
#   $@ - repo-relative shared paths
#######################################
write_shared_diff() {
  local tier="${1}" source="${2}"
  shift 2
  local rel exit_code
  for rel in "$@"; do
    if [[ "$(head_blob "${tier}" "${source}" "${rel}")" == none && -z "$(repo_git "${tier}" "${source}" ls-files --cached -- "${rel}")" ]]; then
      exit_code=0
      repo_git "${tier}" "${source}" diff --no-index -- /dev/null "${rel}" || exit_code=$?
      (( exit_code <= 1 )) || { log::err "git diff --no-index failed | file='${rel}' exit_code='${exit_code}'"; return 1; }
      continue
    fi
    repo_git "${tier}" "${source}" diff HEAD -- "${rel}"
  done
}

#######################################
# Print the path of each entry line on stdin; a path may hold spaces.
# Arguments: None
#######################################
entry_paths() {
  awk 'NF { sub(/^[^ ]+ [^ ]+ /, ""); print }'
}

#######################################
# Print each changed path that no --edited value names. An adoption records
# every file of a skill no driver has edited, so none is foreign.
# Arguments:
#   $1 - adopt (true|false)
#   $2 - changed paths, newline-separated
#   $3 - --edited paths, skill-dir-relative, newline-separated
#######################################
foreign_paths() {
  local adopt="${1}" changed="${2}" edited="${3}"
  if [[ "${adopt}" == "true" ]]; then
    log::debug "An adoption has no foreign files | adopt='${adopt}'"
    return
  fi
  local -a changed_list=("${(@f)changed}") edited_list=("${(@f)edited}")
  print -rl -- "${(@)changed_list:|edited_list}"
}

#######################################
# Hold the skill's claim for this investigation folder: take it under
# --execute (a dry run only checks), refuse when another live driver holds it.
# Prints how it stands: taken, renewed, taken-stale, or in a dry run would-take
# and would-renew.
# Globals: None
# Arguments:
#   $1 - skill name
#   $2 - investigation folder
# Returns: 1 when another live driver holds the claim
#######################################
hold_claim() {
  local skill="${1}" investigation_dir="${2}" blocker
  blocker="$(claim_blocker "${skill}" "${investigation_dir}")"
  if [[ -n "${blocker}" ]]; then
    log::err "Another driver holds this skill; nothing recorded | skill='${skill}' owner='${blocker}' hint='SendMessage the change to that driver, or list it under Open questions'"
    return 1
  fi
  if is_dry_run; then
    local owner
    owner="$(claim_owner "${skill}")"
    if [[ -n "${owner}" && "${owner:A}" == "${investigation_dir:A}" ]]; then
      print -r -- would-renew
      return 0
    fi
    log::info "would take | what='the skill claim' skill='${skill}'"
    print -r -- would-take
    return 0
  fi
  local result
  result="$(claim_take "${skill}" "${investigation_dir}" false)" || {
    log::err "Could not take the skill claim; nothing recorded | skill='${skill}' result='${result}'"
    return 1
  }
  print -r -- "${result}"
}

#######################################
# Print the diff of the recorded files: per file `git diff --no-index` for an
# adoption; else the tier's `diff HEAD` plus each untracked file, which
# `diff HEAD` omits.
# Arguments:
#   $1 - tier
#   $2 - source
#   $3 - skill name
#   $4 - skill directory, repo-relative
#   $5 - adopt (true|false)
#######################################
write_diff() {
  local tier="${1}" source="${2}" skill="${3}" skill_rel="${4}" adopt="${5}"
  local file exit_code
  if [[ "${adopt}" == "true" ]]; then
    for file in "${(@f)$(adopt_entries "${tier}" "${source}" "${SKILLS_DIR}/${skill}" "${skill_rel}" false | entry_paths)}"; do
      [[ -n "${file}" ]] || continue
      exit_code=0
      git diff --no-index -- /dev/null "${SKILLS_DIR}/${skill}/${file}" || exit_code=$?
      (( exit_code <= 1 )) || { log::err "git diff --no-index failed | file='${file}' exit_code='${exit_code}'"; return 1; }
    done
    return 0
  fi
  repo_git "${tier}" "${source}" diff HEAD -- "${skill_rel}"
  for file in "${(@f)$(repo_git "${tier}" "${source}" ls-files --others --exclude-standard -- "${skill_rel}")}"; do
    [[ -n "${file}" ]] || continue
    exit_code=0
    repo_git "${tier}" "${source}" diff --no-index -- /dev/null "${file}" || exit_code=$?
    (( exit_code <= 1 )) || { log::err "git diff --no-index failed | file='${file}' exit_code='${exit_code}'"; return 1; }
  done
}

#######################################
# Print the fenced Commit command for the recorded entries (it acts: --execute, run only
# after the user's yes), or `none — empty diff` when there are none.
# Arguments:
#   $1 - tier
#   $2 - source
#   $3 - entries (newline-separated entry lines)
#   $@ - the leading commit_blobs.zsh flags, unquoted words
#######################################
write_command() {
  local tier="${1}" source="${2}" entries="${3}"
  shift 3
  if [[ -z "${entries}" ]]; then
    log::info "No changed files; the Commit command is none"
    print -r -- 'none — empty diff'
    return
  fi
  local line mode blob file spec head
  {
    print -r -- '```zsh'
    print -rn -- "zsh \$HOME/.claude/skills/ari-skill-update/bin/commit_blobs.zsh ${(j: :)${(q-)@}}"
    for line in "${(@f)entries}"; do
      [[ -n "${line}" ]] || continue
      read -r mode blob file <<< "${line}"
      if [[ "${file}" == "${SHARED_ENTRY_PREFIX}"* ]]; then
        file="${file#${SHARED_ENTRY_PREFIX}}"
        head="$(head_blob "${tier}" "${source}" "${file}")"
        if [[ "${mode}" == "deleted" ]]; then
          spec="${head}:${file}"
          print -rn -- " \\"$'\n'"  --shared-delete ${(q-)spec}"
          continue
        fi
        spec="${head}:${mode}:${blob}:${file}"
        print -rn -- " \\"$'\n'"  --shared ${(q-)spec}"
        continue
      fi
      if [[ "${mode}" == "deleted" ]]; then
        print -rn -- " \\"$'\n'"  --delete ${(q-)file}"
        continue
      fi
      spec="${mode}:${blob}:${file}"
      print -rn -- " \\"$'\n'"  --blob ${(q-)spec}"
    done
    print -r -- " \\"$'\n'"  --execute"
    print -r -- '```'
  }
}

# --- Help ---

help() {
  cat <<EOF
${c_green}record_blobs${c_rst} — record a proposal's blobs, write its diff and its Commit command

${c_bold}Usage:${c_rst}
  zsh \$HOME/.claude/skills/ari-skill-update/bin/record_blobs.zsh --skill <name> --tier <df|ldf> --investigation-dir <dir> --message <msg> [--source submodule:<path>] [--adopt] [--edited <path>]... [--shared <path>]... [--execute] [--dry-run]

${c_bold}Options:${c_rst}
  --skill NAME              Skill whose files are recorded (required)
  --tier TIER               df or ldf: init.zsh's tier, or the tier picked for an adoption (required)
  --source SOURCE           init.zsh's source= value when a submodule holds the skill
  --investigation-dir DIR   Where <skill>.diff.patch and <skill>.commit.md are written (required)
  --message MSG             Commit message for the Commit command (required)
  --adopt                   The skill is not in a tier yet (state unlinked or ignored, or new)
  --edited PATH             A file you edited: relative to the skill dir (the held directory unless --adopt),
                            or absolute under it or under \$HOME/.claude/skills/<name>; repeat.
                            A changed file not named is foreign (never under --adopt)
  --shared PATH             A shared file outside the skill dir under the tier's lib root (~/.config/claude/lib for df;
                            the local tier has none): absolute, or relative to $HOME; repeat. Recorded with the skill's
                            blobs and committed in the same commit_blobs run; refused for a submodule skill
  --execute                 Write the blobs, the diff and the Commit command; without it the run is a dry run
  --dry-run                 The default made explicit; wins over --execute and exports DRY_RUN=1
  -h, --help                Show this help

${c_bold}Output:${c_rst}
  key=value lines: diff, command, files, insertions, deletions, foreign, unmatched_edited
  (--edited files with no change against HEAD), concurrent, claim (taken | renewed | taken-stale
  | would-take | would-renew in a dry run), dry_run (1 | 0). A dry run hashes and diffs but writes no blob and no
  file, takes no claim, and logs the exact rerun with --execute.
  Refuses (exit 1) when another live driver holds the skill's claim, when an --edited path is not
  a file in the skill dir, when --tier/--source do not hold the skill, when the repo has no
  commit yet, or when a file changes while it records (moved_files= in the log).
EOF
}

# --- Main ---

main() {
  check_prerequisites || exit 1

  # === PARSE ===
  local skill="" tier="" source="" investigation_dir="" message="" adopt=false execute=false dry_run_flag=false
  local -a edited=() shared=()
  while (( $# > 0 )); do case "${1}" in
    -h|--help)           help; return 0 ;;
    --skill)             skill="${2:?--skill requires a value}"; shift 2 ;;
    --tier)              tier="${2:?--tier requires a value}"; shift 2 ;;
    --source)            source="${2?--source requires a value}"; shift 2 ;;
    --investigation-dir) investigation_dir="${2:?--investigation-dir requires a value}"; shift 2 ;;
    --message)           message="${2:?--message requires a value}"; shift 2 ;;
    --edited)            edited+=("${2:?--edited requires a value}"); shift 2 ;;
    --shared)            shared+=("${2:?--shared requires a value}"); shift 2 ;;
    --adopt)             adopt=true; shift ;;
    --execute)           execute=true; shift ;;
    --dry-run)           dry_run_flag=true; shift ;;
    -*)                  log::err "Unknown flag | flag='${1}'"; help; return 1 ;;
    *)                   log::err "Unexpected argument | argument='${1}'"; help; return 1 ;;
  esac; done
  resolve_dry_run "${execute}" "${dry_run_flag}" || return 1

  # === MASSAGE ===

  tier="${tier:l}"
  investigation_dir="${investigation_dir%/}"
  local write=true
  is_dry_run && write=false
  local skill_dir="${SKILLS_DIR}/${skill}"
  local file i
  local -a shared_rel=()
  for (( i = 1; i <= ${#shared}; i += 1 )); do
    [[ "${shared[i]}" == /* ]] || shared[i]="${HOME}/${shared[i]}"
    shared_rel+=("$(shared_relative_path "${tier}" "${source}" "${shared[i]}")")
  done

  # === VALIDATE ===
  local -a missing=()
  [[ -n "${skill}" ]] || missing+=(--skill)
  [[ -n "${tier}" ]] || missing+=(--tier)
  [[ -n "${investigation_dir}" ]] || missing+=(--investigation-dir)
  [[ -n "${message}" ]] || missing+=(--message)
  if (( ${#missing} > 0 )); then
    log::err "Missing required flags | missing='${(j:, :)missing}'"
    help
    return 1
  fi
  if ! is_valid_tier "${tier}"; then
    log::err "Invalid tier | tier='${tier}' valid_tiers='${(j:, :)TIERS}'"
    return 1
  fi
  if [[ -n "${source}" && "${source}" != submodule:?* ]]; then
    log::err "Invalid source | source='${source}' expected='submodule:<path> or empty'"
    return 1
  fi
  if [[ ! -d "${investigation_dir}" ]]; then
    log::err "No investigation folder | investigation_dir='${investigation_dir}'"
    return 1
  fi
  for (( i = 1; i <= ${#shared}; i += 1 )); do
    if [[ -z "${shared_rel[i]}" || -d "${shared[i]}" ]] || { [[ ! -e "${shared[i]}" && ! -L "${shared[i]}" ]] && [[ "$(head_blob "${tier}" "${source}" "${shared_rel[i]}")" == none ]]; }; then
      log::err "--shared must name a file under an allowed shared root | shared='${shared[i]}' tier='${tier}' source='${source}' allowed_roots='${(j:, :)$(shared_roots "${tier}")}'"
      return 1
    fi
  done
  shared_rel=("${(@u)shared_rel}")
  if [[ "${adopt}" == "true" && ( -L "${skill_dir}" || ! -d "${skill_dir}" ) ]]; then
    log::err "--adopt needs the skill as a real directory | skill_dir='${skill_dir}'"
    return 1
  fi
  local link_dir="${skill_dir}"
  if [[ "${adopt}" == "false" ]]; then
    local holder held_source=""
    holder="$(skill_holder_root "${tier}" "${skill}")"
    [[ -n "${holder}" ]] && held_source="$(root_source "${tier}" "${holder}")"
    # A held skill with no link yet is fine: its held directory is the skill. A link, when present, must point there.
    if [[ -z "${holder}" || "${held_source}" != "${source}" ]] || [[ ( -e "${link_dir}" || -L "${link_dir}" ) && "${link_dir:A}" != "${holder:A}/${skill}" ]]; then
      log::err "--tier and --source do not hold the skill | skill_dir='${link_dir:A}' holder='${holder}' held_source='${held_source}' tier='${tier}' source='${source}' hint='pass tier= and source= as init.zsh printed them; if they match, re-run the registry status and stop on any state but linked or missing'"
      return 1
    fi
    skill_dir="${holder}/${skill}"
    require_head "${tier}" "${source}" || return 1
  fi
  local -a edited_rel=()
  for file in "${edited[@]}"; do
    # The $HOME/.claude/skills form names a link that a held skill may not have yet.
    [[ ! -e "${link_dir}" && ! -L "${link_dir}" && "${file}" == "${link_dir}/"?* ]] && file="${skill_dir}/${file#${link_dir}/}"
    edited_rel+=("$(skill_relative_path "${skill_dir}" "${file}")")
  done
  for (( i = 1; i <= ${#edited}; i += 1 )); do
    if [[ -z "${edited_rel[i]}" || ( -d "${skill_dir}/${edited_rel[i]}" && ! -L "${skill_dir}/${edited_rel[i]}" ) ]]; then
      log::err "--edited must name a file in the skill directory | edited='${edited[i]}' skill_dir='${skill_dir:A}'"
      return 1
    fi
  done

  # === LOGIC ===
  local claim
  claim="$(hold_claim "${skill}" "${investigation_dir}")" || return 1
  local skill_rel
  skill_rel="$(repo_skill_rel "${tier}" "${source}" "${skill}")"
  local diff_out="${investigation_dir}/${skill}.diff.patch" command_out="${investigation_dir}/${skill}.commit.md"

  local before after
  before="$(entries_for "${tier}" "${source}" "${skill}" "${skill_rel}" "${adopt}" "${write}")"
  local skill_before="${before}"
  if (( ${#shared_rel} > 0 )); then
    before="$(merge_entries "${before}" "$(shared_entries "${tier}" "${source}" "${write}" "${shared_rel[@]}")")"
  fi
  (( MUT_COUNT += 1 ))
  is_dry_run && log::info "would write | what='blobs of the recorded files to the tier object store'"
  local diff_text
  diff_text="$(write_diff "${tier}" "${source}" "${skill}" "${skill_rel}" "${adopt}")"
  after="$(entries_for "${tier}" "${source}" "${skill}" "${skill_rel}" "${adopt}" false)"
  if (( ${#shared_rel} > 0 )); then
    local shared_diff
    shared_diff="$(write_shared_diff "${tier}" "${source}" "${shared_rel[@]}")"
    [[ -z "${shared_diff}" ]] || diff_text="${diff_text}"$'\n'"${shared_diff}"
    after="$(merge_entries "${after}" "$(shared_entries "${tier}" "${source}" false "${shared_rel[@]}")")"
  fi
  if [[ "${before}" != "${after}" ]]; then
    local moved_files
    moved_files="$(mismatched_paths "${before}" "${after}")"
    log::err "Files changed while recording; another session is editing this skill | moved_files='${moved_files}' hint='re-run once it settles; list it under Open questions'"
    return 1
  fi

  local base
  base="$(base_tree "${tier}" "${source}" "${skill_rel}")"
  [[ "${adopt}" == "true" ]] && base=none
  local -a leading=(--skill "${skill}" --tier "${tier}")
  [[ -n "${source}" ]] && leading+=(--source "${source}")
  [[ "${adopt}" == "true" ]] && leading+=(--adopt)
  leading+=(--base-tree "${base}" --claim-dir "${investigation_dir}" --message "${message}")
  write_command "${tier}" "${source}" "${before}" "${leading[@]}" | write_mut "${command_out}"
  print -r -- "${diff_text}" | write_mut "${diff_out}"

  local -a changed
  changed=("${(@f)$(print -r -- "${skill_before}" | entry_paths)}")
  changed=("${(@)changed:#}")
  local -a foreign unmatched
  foreign=("${(@f)$(foreign_paths "${adopt}" "${(F)changed}" "${(F)edited_rel}")}")
  foreign=("${(@)foreign:#}")
  unmatched=("${(@)edited_rel:|changed}")
  local -a shared_changed
  shared_changed=("${(@f)$(print -r -- "${before}" | shared_paths_of)}")
  unmatched+=("${(@)shared_rel:|shared_changed}")

  local files insertions deletions
  files="$(awk '/^diff --git / { n += 1 } END { print n + 0 }' <<< "${diff_text}")"
  insertions="$(awk '/^\+\+\+ / { next } /^\+/ { n += 1 } END { print n + 0 }' <<< "${diff_text}")"
  deletions="$(awk '/^--- / { next } /^-/ { n += 1 } END { print n + 0 }' <<< "${diff_text}")"

  local concurrent
  concurrent="$(live_sibling_dirs "${skill}" "${investigation_dir}" "$(last_commit_epoch "${tier}" "${source}" "${skill_rel}")")"
  log::info "Recorded the proposal's blobs | skill='${skill}' files='${files}' written='${write}' foreign='${(j:,:)foreign}' concurrent='${concurrent}'"

  cat <<EOF
diff=${diff_out}
command=${command_out}
files=${files}
insertions=${insertions}
deletions=${deletions}
foreign=${(j:,:)foreign}
unmatched_edited=${(j:,:)unmatched}
concurrent=${concurrent}
claim=${claim}
dry_run=${DRY_RUN}
EOF
  report_dry_run "${SCRIPT_PATH}" "${ARGS[@]}"
}

readonly -a ARGS=("${@}")
main "${@}"
