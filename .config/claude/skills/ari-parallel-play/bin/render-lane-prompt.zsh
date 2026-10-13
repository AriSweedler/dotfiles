#!/usr/bin/env zsh
# Render one lane agent's prompt: the ask file's Ask, Context and Brief verbatim, the lane's
# coordinates, and the fast path with every slot filled from the repo profile. Read-only; the
# prompt goes to stdout.
# Run: zsh $HOME/.claude/skills/ari-parallel-play/bin/render-lane-prompt.zsh --help

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

readonly TEMPLATE_DIR="${SCRIPT_DIR:h}/templates"
readonly FAST_PATH_TEMPLATE="${TEMPLATE_DIR}/fast-path.md"
readonly LANE_PROMPT_TEMPLATE="${TEMPLATE_DIR}/lane-prompt.md"
readonly REQUIRED_PROFILE_SECTIONS=('Tooling' 'Gate' 'Code rules' 'Dependencies' 'CI' 'GitHub')
readonly REQUIRED_ASK_SECTIONS=('Ask' 'Context' 'Brief')
readonly VALID_CHAIN=(yes no)
readonly LINK_NONE="none"

help() {
  cat <<EOF
${c_green}render-lane-prompt${c_rst} — the lane agent's prompt from the repo profile, the ask file and the lane's coordinates

${c_bold}Usage:${c_rst}
  zsh $HOME/.claude/skills/ari-parallel-play/bin/render-lane-prompt.zsh --profile FILE --ask-file FILE --id ID --repo-name NAME --root DIR --worktree DIR --branch NAME --base REF --pr-base BRANCH --chain yes|no [--other-lanes TEXT] [--lane-env TEXT]

${c_bold}Options:${c_rst}
  --profile FILE      The repo profile (templates/repo-profile.md filled in; the orchestrator's profile.md copy)
  --ask-file FILE     The working doc's asks/<id>.md; its Ask, Context and Brief are copied verbatim
  --id ID             The lane id
  --repo-name NAME    The repository, e.g. OWNER/NAME
  --root DIR          The main checkout
  --worktree DIR      The lane's worktree
  --branch NAME       The lane's branch
  --base REF          The ref the branch was opened from (origin/main, or the lane below's branch)
  --pr-base BRANCH    The PR's base branch
  --chain yes|no      yes for a bottom, middle or top chain lane; no for a solo lane
  --other-lanes TEXT  The other lanes running now, as prose (default: none)
  --lane-env TEXT     This lane's rendered Lane environment (default: the profile's Lane environment section verbatim, else nothing)
  -h, --help          Show this help

${c_bold}Output:${c_rst} the prompt on stdout; logs on stderr. Fails when a required section is missing or a slot stays unrendered.
EOF
}

#######################################
# Check that required binaries are installed.
# Returns: 1 if any are missing
#######################################
check_prerequisites() {
  local missing=()
  for cmd in awk; do
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
# The body of one "## <name>" section of a markdown file, HTML comments removed, blank lines squeezed.
# Arguments:
#   $1 - file; $2 - section name (without the ##)
# Outputs: the body, possibly empty
#######################################
section_body() {
  local file="${1}" name="${2}"
  awk -v heading="## ${name}" '
    /^## / { if (in_section) exit; if ($0 == heading) { in_section = 1; next } }
    in_section { print }
  ' "${file}" | awk '
    {
      line = $0; out = ""
      while (1) {
        if (in_comment) {
          i = index(line, "-->"); if (i == 0) { line = ""; break }
          line = substr(line, i + 3); in_comment = 0
        } else {
          i = index(line, "<!--"); if (i == 0) { out = out line; break }
          out = out substr(line, 1, i - 1); line = substr(line, i + 4); in_comment = 1
        }
      }
      print out
    }
  ' | awk 'NF { blank = 0; print; next } !blank { blank = 1; print }' | awk 'NR == 1 && !NF { next } { print }'
}

#######################################
# The value after "- <key>:" in a section body.
# Arguments:
#   $1 - body; $2 - key
# Outputs: the trimmed value, possibly empty
#######################################
bullet_value() {
  local body="${1}" key="${2}"
  print -r -- "${body}" | awk -v key="- ${key}:" '
    index($0, key) == 1 { value = substr($0, length(key) + 1); gsub(/^[ \t]+|[ \t]+$/, "", value); print value; exit }
  '
}

#######################################
# The env prefix that selects the write account for gh, from the profile's GitHub section.
# Arguments:
#   $1 - the GitHub section body
# Outputs: e.g. "unset GITHUB_TOKEN; export GH_TOKEN=$(gh auth token --user NAME);" or nothing
#######################################
gh_write_prefix() {
  local body="${1}" write_account read_account unset_var prefix=""
  write_account="$(bullet_value "${body}" 'Write account')"
  read_account="$(bullet_value "${body}" 'Read account')"
  unset_var="$(bullet_value "${body}" 'Unset first')"
  [[ -n "${write_account}" ]] || write_account="${read_account}"
  if [[ -n "${unset_var}" ]]; then
    prefix="unset ${unset_var}; "
  fi
  if [[ -z "${write_account}" ]]; then
    log::info "No GitHub account in the profile; gh uses its active account"
    print -r -- "${prefix}"
    return 0
  fi
  log::info "gh writes as the profile's account | write_account='${write_account}'"
  print -r -- "${prefix}export GH_TOKEN=\$(gh auth token --user ${write_account});"
}

#######################################
# The linked dependency directory from the Dependencies section's "- Link:" line.
# Arguments:
#   $1 - the Dependencies body
# Outputs: the directory name, or nothing for none
#######################################
link_dir() {
  local body="${1}" link
  link="$(bullet_value "${body}" 'Link')"
  if [[ -z "${link}" || "${link:l}" == "${LINK_NONE}" ]]; then
    log::info "No shared dependency directory | link='${link:-${LINK_NONE}}'"
    return 0
  fi
  log::info "Shared dependency directory | link='${link}'"
  print -r -- "${link}"
}

#######################################
# The Dependencies body without its "- Link:" line.
# Arguments:
#   $1 - the Dependencies body
#######################################
deps_rule() {
  print -r -- "${1}" | awk 'index($0, "- Link:") != 1 { print }' | awk 'NR == 1 && !NF { next } { print }'
}

#######################################
# Replace every {{slot}} in a template string.
# Arguments:
#   $1 - template text; $2.. - slot=value pairs (value may be multi-line)
# Outputs: the rendered text
#######################################
render() {
  local text="${1}"; shift
  local pair slot value
  for pair in "${@}"; do
    slot="${pair%%=*}"; value="${pair#*=}"
    text="${text//\{\{${slot}\}\}/${value}}"
  done
  print -r -- "${text}"
}

main() {
  check_prerequisites || exit 1

  # === PARSE ===
  local profile="" ask_file="" id="" repo_name="" root="" worktree="" branch="" base="" pr_base="" chain="" other_lanes="none" lane_env=""
  local lane_env_given=false
  while (( $# > 0 )); do case "${1}" in
    -h|--help)      help; return 0 ;;
    --profile)      profile="${2:?--profile requires a file}"; shift 2 ;;
    --ask-file)     ask_file="${2:?--ask-file requires a file}"; shift 2 ;;
    --id)           id="${2:?--id requires a value}"; shift 2 ;;
    --repo-name)    repo_name="${2:?--repo-name requires a value}"; shift 2 ;;
    --root)         root="${2:?--root requires a dir}"; shift 2 ;;
    --worktree)     worktree="${2:?--worktree requires a dir}"; shift 2 ;;
    --branch)       branch="${2:?--branch requires a value}"; shift 2 ;;
    --base)         base="${2:?--base requires a ref}"; shift 2 ;;
    --pr-base)      pr_base="${2:?--pr-base requires a branch}"; shift 2 ;;
    --chain)        chain="${2:?--chain requires yes|no}"; shift 2 ;;
    --other-lanes)  other_lanes="${2:?--other-lanes requires text}"; shift 2 ;;
    --lane-env)     lane_env="${2:?--lane-env requires text}"; lane_env_given=true; shift 2 ;;
    -*)             log::err "Unknown flag | flag='${1}'"; help; return 1 ;;
    *)              log::err "Unexpected argument | argument='${1}'"; help; return 1 ;;
  esac; done

  # === MASSAGE ===
  chain="${chain:l}"

  # === VALIDATE ===
  local -A required=(profile "${profile}" ask-file "${ask_file}" id "${id}" repo-name "${repo_name}" root "${root}" worktree "${worktree}" branch "${branch}" base "${base}" pr-base "${pr_base}" chain "${chain}")
  for flag in profile ask-file id repo-name root worktree branch base pr-base chain; do
    [[ -n "${required[${flag}]}" ]] || { log::err "Missing flag | flag='--${flag}'"; help; return 1; }
  done
  [[ -r "${profile}" ]] || { log::err "Profile not readable | profile='${profile}'"; return 1; }
  [[ -r "${ask_file}" ]] || { log::err "Ask file not readable | ask_file='${ask_file}'"; return 1; }
  [[ -r "${FAST_PATH_TEMPLATE}" && -r "${LANE_PROMPT_TEMPLATE}" ]] || { log::err "Templates missing | dir='${TEMPLATE_DIR}'"; return 1; }
  is_valid_option "${chain}" "${VALID_CHAIN[@]}" || { log::err "Invalid --chain | chain='${chain}' valid='${(j:, :)VALID_CHAIN}'"; return 1; }

  local -A profile_section ask_section
  local name body
  for name in "${REQUIRED_PROFILE_SECTIONS[@]}"; do
    body="$(section_body "${profile}" "${name}")"
    [[ -n "${body//[[:space:]]/}" ]] || { log::err "Profile section missing or empty | section='## ${name}' profile='${profile}'"; return 1; }
    profile_section[${name}]="${body}"  # a subscript is never word-split; quotes there become part of the key
  done
  for name in 'Commit' 'Lane environment'; do
    profile_section[${name}]="$(section_body "${profile}" "${name}")"
  done
  for name in "${REQUIRED_ASK_SECTIONS[@]}"; do
    body="$(section_body "${ask_file}" "${name}")"
    [[ -n "${body//[[:space:]]/}" ]] || { log::err "Ask section missing or empty | section='## ${name}' ask_file='${ask_file}'"; return 1; }
    ask_section[${name}]="${body}"
  done

  # === LOGIC ===
  local gh_write link link_flag="" deps
  gh_write="$(gh_write_prefix "${profile_section[GitHub]}")"
  link="$(link_dir "${profile_section[Dependencies]}")"
  [[ -z "${link}" ]] || link_flag="--link ${link}"
  deps="$(deps_rule "${profile_section[Dependencies]}")"
  if [[ "${lane_env_given}" != "true" ]]; then
    lane_env="${profile_section[Lane environment]}"
  fi

  local fast_path prompt
  fast_path="$(render "$(<"${FAST_PATH_TEMPLATE}")" \
    "tooling=${profile_section[Tooling]}" "gate=${profile_section[Gate]}" "code_rules=${profile_section[Code rules]}" \
    "deps_rule=${deps}" "lane_env=${lane_env}" "gh_write=${gh_write}" "commit_extra=${profile_section[Commit]}" \
    "link_flag=${link_flag}" "worktree=${worktree}" "branch=${branch}" "base=${base}" "root=${root}" \
    "pr_base=${pr_base}" "chain_lane=${chain}" "ask_file=${ask_file}")"
  prompt="$(render "$(<"${LANE_PROMPT_TEMPLATE}")" \
    "id=${id}" "repo_name=${repo_name}" "ask_file=${ask_file}" "ask_section=${ask_section[Ask]}" \
    "context_section=${ask_section[Context]}" "brief_section=${ask_section[Brief]}" "worktree=${worktree}" \
    "branch=${branch}" "base=${base}" "pr_base=${pr_base}" "chain_lane=${chain}" "other_lanes=${other_lanes}" \
    "fast_path=${fast_path}")"

  local unrendered
  unrendered="$(print -r -- "${prompt}" | grep -o '{{[a-z_]*}}' | sort -u | tr '\n' ' ' || true)"
  [[ -z "${unrendered}" ]] || { log::err "Slots left unrendered | slots='${unrendered}'"; return 1; }
  log::info "Prompt rendered | id='${id}' chain='${chain}' lines='$(print -r -- "${prompt}" | wc -l | tr -d ' ')'"

  print -r -- "${prompt}"
}

main "$@"
