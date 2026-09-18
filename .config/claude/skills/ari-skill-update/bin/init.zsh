#!/usr/bin/env zsh
# Set up an /ari-skill-update session: confirm the skill exists (or is brand-new),
# report where it stands in the dotfiles tiers, create the investigation folder +
# pre-filled scratchpad, and enumerate the skill's files for the model to read.
# Run: zsh $HOME/.claude/skills/ari-skill-update/bin/init.zsh --skill <name> [--new]

set -euo pipefail

# Shared libs resolve through the symlink farm, not ${0:A:h:h:h}: skills are spread
# across dotfiles tiers, so a relative hop lands in whichever tier this script sits in.
readonly SKILLS_DIR="${HOME}/.claude/skills"

# --- Logging (source the canonical lib — never re-define log::* inline) ---

readonly LIB_LOGGING="${SKILLS_DIR}/ari-skill-shellscripts/lib/logging.zsh"
if [[ ! -r "${LIB_LOGGING}" ]]; then
  print -u2 "[ERROR] missing shared logging lib | path='${LIB_LOGGING}'"
  exit 1
fi
source "${LIB_LOGGING}"

readonly LIB_INVDIR="${SKILLS_DIR}/ari-skill-shellscripts/lib/investigation_folder.zsh"
if [[ ! -r "${LIB_INVDIR}" ]]; then
  print -u2 "[ERROR] missing investigation_folder lib | path='${LIB_INVDIR}'"
  exit 1
fi
source "${LIB_INVDIR}"

readonly LIB_REGISTRY="${SKILLS_DIR}/ari-dotfiles-skill-registry/lib/registry.zsh"
if [[ ! -r "${LIB_REGISTRY}" ]]; then
  print -u2 "[ERROR] missing skill registry lib | path='${LIB_REGISTRY}'"
  exit 1
fi
source "${LIB_REGISTRY}"

# --- Prerequisites ---

#######################################
# Check that required binaries are installed.
# Globals: None
# Arguments: None
# Returns: 1 if any are missing
#######################################
check_prerequisites() {
  local missing=()
  for cmd in awk find git; do
    command -v "${cmd}" >/dev/null 2>&1 || missing+=("${cmd}")
  done
  if (( ${#missing} > 0 )); then
    log::err "Missing required commands | missing='${(j:, :)missing}'"
    return 1
  fi
}

# --- Helpers ---

#######################################
# Extract the `description:` value from a SKILL.md frontmatter block.
# Arguments:
#   $1 - path to SKILL.md
# Outputs: the description text (empty if absent or unreadable)
#######################################
read_frontmatter_description() {
  local file="${1}"
  [[ -r "${file}" ]] || return 0
  awk '
    /^---[[:space:]]*$/ { fence++; next }
    fence == 1 && /^description:[[:space:]]*/ {
      sub(/^description:[[:space:]]*/, "")
      print
      exit
    }
  ' "${file}"
}

#######################################
# Reject the combinations of --new and on-disk state that make no sense, and say
# where an existing skill stands relative to the dotfiles tiers.
# Arguments:
#   $1 - skill name
#   $2 - is_new (true|false)
#   $3 - state from skill_state
#   $4 - tier from skill_state
# Returns: 1 when the session must not continue
#######################################
check_skill_state() {
  local skill="${1}" is_new="${2}" state="${3}" tier="${4}"
  if [[ "${is_new}" == "true" && "${state}" != "absent" ]]; then
    log::err "--new given but the skill exists | skill='${skill}' state='${state}' tier='${tier}'"
    return 1
  fi
  if [[ "${is_new}" == "true" ]]; then
    log::info "New skill | skill='${skill}' hint='adopt it into a tier once it works'"
    return 0
  fi
  if [[ "${state}" == "absent" ]]; then
    log::err "No such skill | skill='${skill}' skills_dir='${SKILLS_DIR}' hint='re-run with --new if this is a brand-new skill'"
    return 1
  fi
  if [[ "${state}" == "linked" ]]; then
    log::info "Skill is versioned in the dotfiles | skill='${skill}' tier='${tier}'"
    return 0
  fi
  log::warn "Skill is not adopted into a dotfiles tier | skill='${skill}' state='${state}' hint='adopt after editing, see /ari-dotfiles-skill-registry'"
}

# --- Help ---

help() {
  cat <<EOF
${c_green}init${c_rst} — set up an /ari-skill-update session (check the skill, make investigation folder, list files)

${c_bold}Usage:${c_rst}
  zsh \$HOME/.claude/skills/ari-skill-update/bin/init.zsh --skill <name> [--new]

${c_bold}Options:${c_rst}
  --skill NAME   Skill to edit (required)
  --new          Brand-new skill — it must not exist yet
  -h, --help     Show this help

${c_bold}Output:${c_rst}
  key=value lines (skill, is_new, state, tier, source, skill_dir, investigation_dir,
  scratchpad) plus a FILES section listing the skill's files to read. Creates the
  investigation folder and a pre-filled scratchpad. state/tier come from
  /ari-dotfiles-skill-registry (linked, unlinked, ignored, ...); source is
  submodule:<path> when a submodule's skills/ holds the skill, else empty.
EOF
}

# --- Main ---

main() {
  check_prerequisites || exit 1

  # === PARSE ===
  local skill="" is_new=false
  while (( $# > 0 )); do case "${1}" in
    -h|--help) help; return 0 ;;
    --skill)   skill="${2:?--skill requires a value}"; shift 2 ;;
    --new)     is_new=true; shift ;;
    -*)        log::err "Unknown flag | flag='${1}'"; help; return 1 ;;
    *)         log::err "Unexpected argument | argument='${1}'"; help; return 1 ;;
  esac; done

  # === VALIDATE ===
  if [[ -z "${skill}" ]]; then
    log::err "Missing --skill | hint='pass the skill directory name under \$HOME/.claude/skills/'"
    help
    return 1
  fi

  local state tier source=""
  read -r state tier <<< "$(skill_state "${skill}")"
  check_skill_state "${skill}" "${is_new}" "${state}" "${tier}" || return 1
  # A skill held by a submodule's skills/ is committed in that repo, not the tier.
  if [[ "${state}" == "linked" || "${state}" == "missing" ]]; then
    source="$(root_source "${tier}" "$(skill_holder_root "${tier}" "${skill}")")"
  fi

  # === LOGIC ===
  local skill_dir="${SKILLS_DIR}/${skill}"
  local skill_md="${skill_dir}/SKILL.md"

  local purpose
  purpose="$(read_frontmatter_description "${skill_md}")"
  [[ -n "${purpose}" ]] || purpose="<no description: in frontmatter — synthesize from the heading>"

  local inv_dir scratchpad
  inv_dir="$(mk_investigation_dir /tmp/skill-update "${skill}")"
  scratchpad="${inv_dir}/scratchpad.md"

  cat > "${scratchpad}" <<EOF
- **Skill**: ${skill} — \$HOME/.claude/skills/${skill}/SKILL.md — ${purpose}
- **Goal**: <fill from the user's request>
- **Changes made**:
- **Open questions**:
EOF
  log::info "Investigation folder ready | scratchpad='${scratchpad}'"

  local files=""
  if [[ -d "${skill_dir}" ]]; then
    files="$(find "${skill_dir}/" -type f | sort)"
  fi
  local file_count=0
  [[ -n "${files}" ]] && file_count="$(echo "${files}" | wc -l | tr -d ' ')"
  if (( file_count == 0 )); then
    log::warn "No files found | skill='${skill}' skill_dir='${skill_dir}' is_new='${is_new}'"
  fi
  log::info "Enumerated files | skill='${skill}' count='${file_count}'"

  cat <<EOF
skill=${skill}
is_new=${is_new}
state=${state}
tier=${tier}
source=${source}
skill_dir=${skill_dir}
investigation_dir=${inv_dir}
scratchpad=${scratchpad}
EOF
  echo "=== start FILES ==="
  [[ -n "${files}" ]] && echo "${files}"
  echo "=== end FILES ==="
}

main "${@}"
