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

readonly LIB_REGISTRY="${SKILLS_DIR}/ari-dotfiles-skill-registry/lib/registry.zsh"
if [[ ! -r "${LIB_REGISTRY}" ]]; then
  print -u2 "[ERROR] missing skill registry lib | path='${LIB_REGISTRY}'"
  exit 1
fi
source "${LIB_REGISTRY}"
source "${SCRIPT_DIR:h}/lib/blobs.zsh"

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
# Write the diff of the recorded files: per file `git diff --no-index` for an
# adoption; else the tier's `diff HEAD` plus each untracked file, which
# `diff HEAD` omits.
# Arguments:
#   $1 - tier
#   $2 - source
#   $3 - skill name
#   $4 - skill directory, repo-relative
#   $5 - adopt (true|false)
#   $6 - output file
#######################################
write_diff() {
  local tier="${1}" source="${2}" skill="${3}" skill_rel="${4}" adopt="${5}" out="${6}"
  : > "${out}"
  local file exit_code
  if [[ "${adopt}" == "true" ]]; then
    for file in "${(@f)$(adopt_entries "${tier}" "${source}" "${SKILLS_DIR}/${skill}" "${skill_rel}" false | entry_paths)}"; do
      [[ -n "${file}" ]] || continue
      exit_code=0
      git diff --no-index -- /dev/null "${SKILLS_DIR}/${skill}/${file}" >> "${out}" || exit_code=$?
      (( exit_code <= 1 )) || { log::err "git diff --no-index failed | file='${file}' exit_code='${exit_code}'"; return 1; }
    done
    return 0
  fi
  repo_git "${tier}" "${source}" diff HEAD -- "${skill_rel}" >> "${out}"
  for file in "${(@f)$(repo_git "${tier}" "${source}" ls-files --others --exclude-standard -- "${skill_rel}")}"; do
    [[ -n "${file}" ]] || continue
    exit_code=0
    repo_git "${tier}" "${source}" diff --no-index -- /dev/null "${file}" >> "${out}" || exit_code=$?
    (( exit_code <= 1 )) || { log::err "git diff --no-index failed | file='${file}' exit_code='${exit_code}'"; return 1; }
  done
}

#######################################
# Write the fenced Commit command for the recorded entries, or `none — empty
# diff` when there are none.
# Arguments:
#   $1 - output file
#   $2 - entries (newline-separated entry lines)
#   $@ - the leading commit_blobs.zsh flags, unquoted words
#######################################
write_command() {
  local out="${1}" entries="${2}"
  shift 2
  if [[ -z "${entries}" ]]; then
    log::info "No changed files; the Commit command is none | out='${out}'"
    print -r -- 'none — empty diff' > "${out}"
    return
  fi
  local line mode blob file spec
  {
    print -r -- '```zsh'
    print -rn -- "zsh \$HOME/.claude/skills/ari-skill-update/bin/commit_blobs.zsh ${(j: :)${(q-)@}}"
    for line in "${(@f)entries}"; do
      [[ -n "${line}" ]] || continue
      read -r mode blob file <<< "${line}"
      if [[ "${mode}" == "deleted" ]]; then
        print -rn -- " \\"$'\n'"  --delete ${(q-)file}"
        continue
      fi
      spec="${mode}:${blob}:${file}"
      print -rn -- " \\"$'\n'"  --blob ${(q-)spec}"
    done
    print
    print -r -- '```'
  } > "${out}"
}

# --- Help ---

help() {
  cat <<EOF
${c_green}record_blobs${c_rst} — record a proposal's blobs, write its diff and its Commit command

${c_bold}Usage:${c_rst}
  zsh \$HOME/.claude/skills/ari-skill-update/bin/record_blobs.zsh --skill <name> --tier <df|ldf> --investigation-dir <dir> --message <msg> [--source submodule:<path>] [--adopt] [--edited <path>]... [--dry-run]

${c_bold}Options:${c_rst}
  --skill NAME              Skill whose files are recorded (required)
  --tier TIER               df or ldf: init.zsh's tier, or the tier picked for an adoption (required)
  --source SOURCE           init.zsh's source= value when a submodule holds the skill
  --investigation-dir DIR   Where <skill>.diff.patch and <skill>.commit.md are written (required)
  --message MSG             Commit message for the Commit command (required)
  --adopt                   The skill is not in a tier yet (state unlinked or ignored, or new)
  --edited PATH             A file you edited: absolute, or relative to the skill dir; repeat.
                            A changed file not named is foreign (never under --adopt)
  --dry-run                 Hash without writing blobs to the object store
  -h, --help                Show this help

${c_bold}Output:${c_rst}
  key=value lines: diff, command, files, insertions, deletions, foreign, unmatched_edited
  (--edited files with no change against HEAD), concurrent.
  Refuses (exit 1) when an --edited path is not a file in the skill dir, when --tier/--source
  do not hold the skill, or when a file changes while it records (moved_files= in the log).
EOF
}

# --- Main ---

main() {
  check_prerequisites || exit 1

  # === PARSE ===
  local skill="" tier="" source="" investigation_dir="" message="" adopt=false dry_run=false
  local -a edited=()
  while (( $# > 0 )); do case "${1}" in
    -h|--help)           help; return 0 ;;
    --skill)             skill="${2:?--skill requires a value}"; shift 2 ;;
    --tier)              tier="${2:?--tier requires a value}"; shift 2 ;;
    --source)            source="${2?--source requires a value}"; shift 2 ;;
    --investigation-dir) investigation_dir="${2:?--investigation-dir requires a value}"; shift 2 ;;
    --message)           message="${2:?--message requires a value}"; shift 2 ;;
    --edited)            edited+=("${2:?--edited requires a value}"); shift 2 ;;
    --adopt)             adopt=true; shift ;;
    --dry-run)           dry_run=true; shift ;;
    -*)                  log::err "Unknown flag | flag='${1}'"; help; return 1 ;;
    *)                   log::err "Unexpected argument | argument='${1}'"; help; return 1 ;;
  esac; done

  # === MASSAGE ===
  tier="${tier:l}"
  investigation_dir="${investigation_dir%/}"
  local write=true
  [[ "${dry_run}" == "true" ]] && write=false
  local skill_dir="${SKILLS_DIR}/${skill}"
  local file
  local -a edited_rel=()
  for file in "${edited[@]}"; do
    edited_rel+=("$(skill_relative_path "${skill_dir}" "${file}")")
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
  local i
  for (( i = 1; i <= ${#edited}; i += 1 )); do
    if [[ -z "${edited_rel[i]}" || ( -d "${skill_dir}/${edited_rel[i]}" && ! -L "${skill_dir}/${edited_rel[i]}" ) ]]; then
      log::err "--edited must name a file in the skill directory | edited='${edited[i]}' skill_dir='${skill_dir:A}'"
      return 1
    fi
  done
  if [[ "${adopt}" == "true" && ( -L "${skill_dir}" || ! -d "${skill_dir}" ) ]]; then
    log::err "--adopt needs the skill as a real directory | skill_dir='${skill_dir}'"
    return 1
  fi
  if [[ "${adopt}" == "false" ]]; then
    local held_dir
    held_dir="$(repo_root "${tier}" "${source}")/$(repo_skill_rel "${tier}" "${source}" "${skill}")"
    if [[ "${skill_dir:A}" != "${held_dir:A}" ]]; then
      log::err "--tier and --source do not hold the skill | skill_dir='${skill_dir:A}' held_dir='${held_dir:A}' tier='${tier}' source='${source}' hint='pass tier= and source= as init.zsh printed them'"
      return 1
    fi
  fi

  # === LOGIC ===
  local skill_rel
  skill_rel="$(repo_skill_rel "${tier}" "${source}" "${skill}")"
  local diff_out="${investigation_dir}/${skill}.diff.patch" command_out="${investigation_dir}/${skill}.commit.md"

  local before after
  before="$(entries_for "${tier}" "${source}" "${skill}" "${skill_rel}" "${adopt}" "${write}")"
  write_diff "${tier}" "${source}" "${skill}" "${skill_rel}" "${adopt}" "${diff_out}"
  after="$(entries_for "${tier}" "${source}" "${skill}" "${skill_rel}" "${adopt}" false)"
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
  leading+=(--base-tree "${base}" --message "${message}")
  write_command "${command_out}" "${before}" "${leading[@]}"

  local -a changed
  changed=("${(@f)$(print -r -- "${before}" | entry_paths)}")
  changed=("${(@)changed:#}")
  local -a foreign unmatched
  foreign=("${(@f)$(foreign_paths "${adopt}" "${(F)changed}" "${(F)edited_rel}")}")
  foreign=("${(@)foreign:#}")
  unmatched=("${(@)edited_rel:|changed}")

  local files insertions deletions
  files="$(awk '/^diff --git / { n += 1 } END { print n + 0 }' "${diff_out}")"
  insertions="$(awk '/^\+\+\+ / { next } /^\+/ { n += 1 } END { print n + 0 }' "${diff_out}")"
  deletions="$(awk '/^--- / { next } /^-/ { n += 1 } END { print n + 0 }' "${diff_out}")"

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
EOF
}

main "${@}"
