#!/usr/bin/env zsh
# Session setup for /ari-skill-update: check the skill, report its dotfiles tier
# state, make the investigation folder, list the files to read. help() has the
# flags and the output contract.

set -euo pipefail

readonly SCRIPT_DIR="${0:A:h}"
INIT_DONE=false
INIT_CLAIM_SKILL="" INIT_CLAIM_DIR=""
readonly SKILLS_DIR="${HOME}/.claude/skills"
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
# Reduce a --skill value to a bare directory name: a full path under SKILLS_DIR
# or a tab-completed trailing slash both arrive here.
# Globals: SKILLS_DIR
# Arguments:
#   $1 - raw --skill value
# Outputs: the bare name (may still hold a slash; the caller validates)
#######################################
normalize_skill_name() {
  local raw="${1}"
  raw="${raw#${SKILLS_DIR}/}"
  while [[ "${raw}" == */ ]]; do
    raw="${raw%/}"
  done
  print -- "${raw}"
}

#######################################
# Extract the `description:` value from a SKILL.md frontmatter block. A block
# scalar (`>` or `|`) spans lines the caller cannot use; it reads as absent.
# Globals: None
# Arguments:
#   $1 - path to SKILL.md
# Outputs: the description text (empty if absent, unreadable, or a block scalar)
#######################################
read_frontmatter_description() {
  local file="${1}"
  [[ -r "${file}" ]] || return 0
  awk '
    /^---[[:space:]]*$/ { fence++; next }
    fence == 1 && /^description:[[:space:]]*/ {
      sub(/^description:[[:space:]]*/, "")
      if ($0 ~ /^[>|]-?[[:space:]]*$/) exit
      print
      exit
    }
  ' "${file}"
}

#######################################
# Reject the combinations of --new and on-disk state that make no sense, and say
# where an existing skill stands relative to the dotfiles tiers.
# Globals: SKILLS_DIR
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
    log::err "--new given but the skill exists | skill='${skill}' state='${state}' tier='${tier}' hint='drop --new and re-run'"
    return 1
  fi
  if [[ "${is_new}" == "true" ]]; then
    log::info "New skill | skill='${skill}' hint='draft its adopt command in the proposal once SKILL.md exists'"
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
  if [[ "${state}" == "missing" ]]; then
    if [[ -e "${SKILLS_DIR}/${skill}" ]]; then
      log::err "Something that is not a link occupies the skill's link path | skill='${skill}' path='${SKILLS_DIR}/${skill}' hint='move it aside, then re-run'"
      return 1
    fi
    log::info "Skill is held but not linked yet; using its real directory | skill='${skill}' tier='${tier}' hint='the driver never links; link_after= names the step Ari runs after the commit'"
    return 0
  fi
  log::warn "Skill is not adopted into a dotfiles tier | skill='${skill}' state='${state}' hint='draft the adopt command in the proposal; it runs only on yes'"
}

#######################################
# Print the step that links a held skill with no link, per the registry's Link
# on a machine: a Nix machine's switch makes shared-tier and dev-repo links;
# the registry's link makes the rest.
# Globals: HOME
# Arguments:
#   $1 - tier
#######################################
link_step() {
  local tier="${1}"
  if [[ "${tier}" == "df" && -e "${HOME}/dotfiles/.git" ]]; then
    print -r -- "dotfiles switch"
    return 0
  fi
  print -r -- "zsh \$HOME/.claude/skills/ari-dotfiles-skill-registry/bin/link --execute"
}

#######################################
# EXIT trap: a run that dies after taking the claim gives it back, so its own
# retry is not blocked by it.
# Globals: INIT_DONE, INIT_CLAIM_SKILL, INIT_CLAIM_DIR
# Arguments: None
#######################################
release_unless_set_up() {
  [[ "${INIT_DONE}" == "true" ]] && return 0
  claim_release "${INIT_CLAIM_SKILL}" "${INIT_CLAIM_DIR}"
}

#######################################
# Refuse, before anything is created, when another live driver holds the skill.
# Globals: None
# Arguments:
#   $1 - skill name
#   $2 - takeover (true|false)
# Returns: 1 when a live driver holds the claim and takeover is false
#######################################
require_unclaimed() {
  local skill="${1}" takeover="${2}" blocker
  blocker="$(claim_blocker "${skill}" "")"
  if [[ -z "${blocker}" ]]; then
    return 0
  fi
  if [[ "${takeover}" == "true" ]]; then
    log::warn "Taking the skill over from a live driver | skill='${skill}' owner='${blocker}'"
    return 0
  fi
  log::err "Another driver holds this skill | skill='${skill}' owner='${blocker}' hint='SendMessage the change to that driver; --takeover only when Ari says it is dead; a claim goes stale after ${CLAIM_STALE_SECONDS}s idle'"
  return 1
}

# --- Help ---

help() {
  cat <<EOF
${c_green}init${c_rst} — set up an /ari-skill-update session (check the skill, make investigation folder, list files)

${c_bold}Usage:${c_rst}
  zsh \$HOME/.claude/skills/ari-skill-update/bin/init.zsh --skill <name> [--new] [--takeover]

${c_bold}Options:${c_rst}
  --skill NAME   Skill to edit (required); a path under \$HOME/.claude/skills/ or a trailing slash is accepted
  --new          Brand-new skill — it must not exist yet
  --takeover     Take the skill's claim from a live driver (only when Ari says that driver is dead)
  -h, --help     Show this help

${c_bold}Output:${c_rst}
  key=value lines (skill, is_new, state, tier, source, skill_dir, link_after, investigation_dir,
  scratchpad, proposal, claim, concurrent) plus a FILES section listing the skill's files to read.
  Creates the investigation folder and a pre-filled scratchpad; proposal is the
  path the driver writes the proposal to (not created here).
  claim is taken, renewed, taken-stale or taken-over: this folder now owns the skill. Another live
  driver's claim refuses (exit 1, nothing created) and names its folder: send it the change by
  SendMessage, or pass --takeover. A claim is stale after ${CLAIM_STALE_SECONDS}s with no change in its
  owner's folder; commit_blobs.zsh releases it.
  concurrent lists, comma-separated, this skill's other investigation folders with a
  file newer than its last commit and the last 24 hours.
  state/tier per /ari-dotfiles-skill-registry; source is submodule:<path> when a submodule's
  skills/ holds the skill, else empty. skill_dir is \$HOME/.claude/skills/<name>, or for
  state=missing (held, not linked yet) the skill's own real directory (<tier or dev-repo
  skills root>/<name>). link_after is empty unless state=missing: then the step that links
  the skill after its commit (dotfiles switch, or the registry's link --execute), Ari's to run.
EOF
}

# --- Main ---

main() {
  check_prerequisites || exit 1

  # === PARSE ===
  local raw_skill="" is_new=false takeover=false
  while (( $# > 0 )); do case "${1}" in
    -h|--help) help; return 0 ;;
    --skill)   raw_skill="${2:?--skill requires a value}"; shift 2 ;;
    --new)     is_new=true; shift ;;
    --takeover) takeover=true; shift ;;
    -*)        log::err "Unknown flag | flag='${1}'"; help; return 1 ;;
    *)         log::err "Unexpected argument | argument='${1}'"; help; return 1 ;;
  esac; done

  # === MASSAGE ===
  local skill
  skill="$(normalize_skill_name "${raw_skill}")"

  # === VALIDATE ===
  if [[ -z "${skill}" ]]; then
    log::err "Missing --skill | hint='pass the skill directory name under \$HOME/.claude/skills/'"
    help
    return 1
  fi
  if [[ "${skill}" == */* || "${skill}" == "." || "${skill}" == ".." ]]; then
    log::err "Invalid skill name | skill='${raw_skill}' expected='a directory name under ${SKILLS_DIR}'"
    return 1
  fi

  local state tier source=""
  read -r state tier <<< "$(skill_state "${skill}")"
  if [[ -z "${state}" ]]; then
    log::err "skill_state returned nothing | skill='${skill}' lib='${LIB_REGISTRY}'"
    return 1
  fi
  check_skill_state "${skill}" "${is_new}" "${state}" "${tier}" || return 1
  # A skill held by a submodule's skills/ is committed in that repo, not the tier.
  local skill_dir="${SKILLS_DIR}/${skill}" holder=""
  if [[ "${state}" == "linked" || "${state}" == "missing" ]]; then
    holder="$(skill_holder_root "${tier}" "${skill}")"
    source="$(root_source "${tier}" "${holder}")"
  fi
  # A held skill with no link yet is read where it lives; who links it is the registry's rule (§ Link on a machine).
  local link_after=""
  if [[ "${state}" == "missing" ]]; then
    if [[ -z "${holder}" ]]; then
      log::err "Skill state is missing but no root holds it | skill='${skill}' tier='${tier}' hint='re-run the registry status'"
      return 1
    fi
    skill_dir="${holder}/${skill}"
    link_after="$(link_step "${tier}")"
  fi

  # === LOGIC ===
  local skill_md="${skill_dir}/SKILL.md"

  local purpose
  purpose="$(read_frontmatter_description "${skill_md}")"
  [[ -n "${purpose}" ]] || purpose="<no single-line description field in the frontmatter — synthesize from the heading>"

  require_unclaimed "${skill}" "${takeover}" || return 1

  local inv_dir scratchpad proposal
  inv_dir="$(mk_investigation_dir "${INVESTIGATION_ROOT}" "${skill}")"
  local claim
  claim="$(claim_take "${skill}" "${inv_dir}" "${takeover}")" || {
    rmdir "${inv_dir}" 2>/dev/null || true
    log::err "Another driver took the skill first | skill='${skill}' claim='${claim}'"
    return 1
  }
  if [[ "${claim}" == "renewed" ]]; then
    log::err "Another driver started this second and shares the investigation folder | skill='${skill}' investigation_dir='${inv_dir}' hint='re-run'"
    return 1
  fi
  INIT_CLAIM_SKILL="${skill}" INIT_CLAIM_DIR="${inv_dir}"
  trap release_unless_set_up EXIT
  log::info "Claimed the skill | skill='${skill}' claim='${claim}' investigation_dir='${inv_dir}'"
  scratchpad="${inv_dir}/scratchpad.md"
  proposal="${inv_dir}/proposal.md"

  local skill_md_shown="\$HOME/.claude/skills/${skill}/SKILL.md"
  [[ "${state}" == "missing" ]] && skill_md_shown="${skill_md}"
  cat > "${scratchpad}" <<EOF
- **Skill**: ${skill} — ${skill_md_shown} — ${purpose}
- **Purpose**: <one sentence from the # heading + opening paragraph>
- **Goal**: <the brief's Change line (inline: the user's request)> — <intent | implementation | both> (<why>)
- **Changes made**:
  - [1] SECTION — change
- **Files edited**: <one per edit, absolute or skill-dir-relative; each becomes an --edited>
- **Own read**: clean | <n> fixed | n/a (private)
- **Open questions**:
  - <question> assumed: <answer>
EOF
  log::info "Investigation folder ready | scratchpad='${scratchpad}'"

  local committed=0 concurrent
  if is_valid_tier "${tier}"; then
    committed="$(last_commit_epoch "${tier}" "${source}" "$(repo_skill_rel "${tier}" "${source}" "${skill}")")"
  fi
  concurrent="$(live_sibling_dirs "${skill}" "${inv_dir}" "${committed}")"
  if [[ -n "${concurrent}" ]]; then
    log::warn "Another driver of this skill may be live | concurrent='${concurrent}'"
  fi

  local files=""
  if [[ -d "${skill_dir}" ]]; then
    files="$(find "${skill_dir}/" \( -name .git -o -name __pycache__ -o -name node_modules -o -name .DS_Store \) -prune -o -type f -print | sort)"
  fi
  local file_count=0
  [[ -n "${files}" ]] && file_count="$(echo "${files}" | wc -l | tr -d ' ')"
  if (( file_count == 0 )); then
    log::warn "No files found | skill='${skill}' skill_dir='${skill_dir}' is_new='${is_new}'"
  fi
  log::info "Enumerated files | skill='${skill}' count='${file_count}'"

  INIT_DONE=true
  cat <<EOF
skill=${skill}
is_new=${is_new}
state=${state}
tier=${tier}
source=${source}
skill_dir=${skill_dir}
link_after=${link_after}
investigation_dir=${inv_dir}
scratchpad=${scratchpad}
proposal=${proposal}
claim=${claim}
concurrent=${concurrent}
EOF
  echo "=== start FILES ==="
  [[ -n "${files}" ]] && echo "${files}"
  echo "=== end FILES ==="
}

main "${@}"
