#!/usr/bin/env zsh
# Print the effective Claude Code permission rules (allow / ask / deny) merged
# across every settings file, so Claude can classify a command before running it.
# Fails safe: a missing/unreadable/malformed file is skipped and reported via
# status=partial|failed, never a silent empty result.
# Run: zsh $HOME/.claude/skills/ari-use-config/bin/effective-permissions.zsh --help

set -euo pipefail

readonly SCRIPT_DIR="${0:A:h}"
readonly SKILLS_DIR="${SCRIPT_DIR:h:h}"  # <skill>/bin → skills root

# --- Logging (source the canonical lib — never re-define log::* inline) ---

readonly LIB_LOGGING="${SKILLS_DIR}/ari-skill-shellscripts/lib/logging.zsh"
if [[ ! -r "${LIB_LOGGING}" ]]; then
  print -u2 "[ERROR] missing shared logging lib | path='${LIB_LOGGING}'"
  exit 1
fi
source "${LIB_LOGGING}"

# --- Prerequisites ---

#######################################
# Check that required binaries are installed.
# Globals: None
# Arguments: None
# Returns: 1 if any are missing
#######################################
check_prerequisites() {
  local missing=()
  for cmd in jq sort wc tr; do
    command -v "${cmd}" >/dev/null 2>&1 || missing+=("${cmd}")
  done
  if (( ${#missing} > 0 )); then
    log::err "Missing required commands | missing='${(j:, :)missing}'"
    return 1
  fi
}

# --- Platform ---

#######################################
# Absolute path to the enterprise-managed settings file for this OS.
# Globals: OSTYPE
# Arguments: None
# Outputs: the path on stdout
#######################################
managed_settings_path() {
  if [[ "${OSTYPE}" == darwin* ]]; then
    echo "/Library/Application Support/ClaudeCode/managed-settings.json"
    return
  fi
  echo "/etc/claude-code/managed-settings.json"
}

# --- Discovery ---

#######################################
# Nearest ancestor of a dir that contains a .claude directory.
# Globals: None
# Arguments: $1 - starting directory
# Outputs: the project root on stdout
# Returns: 1 if no .claude ancestor is found
#######################################
find_project_root() {
  local d="${1}"
  while [[ "${d}" != "/" ]]; do
    if [[ -d "${d}/.claude" ]]; then
      echo "${d}"
      return 0
    fi
    d="${d:h}"
  done
  return 1
}

# --- Validation ---

#######################################
# Classify one settings file. A missing file is fine; an unreadable or
# malformed one is a degraded source the caller must report, not ignore.
# Globals: None
# Arguments: $1 - file path
# Outputs: one of absent|unreadable|invalid|ok on stdout
#######################################
classify_source() {
  local f="${1}"
  if [[ ! -e "${f}" ]]; then
    echo "absent"
    return
  fi
  if [[ ! -r "${f}" ]]; then
    echo "unreadable"
    return
  fi
  if ! jq -e . "${f}" >/dev/null 2>&1; then
    echo "invalid"
    return
  fi
  echo "ok"
}

# --- Extraction ---

#######################################
# Emit every rule under one permission key, across the valid source files.
# Globals: VALID_FILES (array of paths that parsed cleanly)
# Arguments: $1 - permission key (allow|ask|deny)
# Outputs: one rule per line on stdout
#######################################
extract_rules() {
  local key="${1}" f
  for f in "${VALID_FILES[@]}"; do
    jq -r --arg k "${key}" '.permissions[$k] // [] | .[]' "${f}" 2>/dev/null
  done
}

#######################################
# Count non-empty lines in a captured string.
# Arguments: $1 - string (possibly empty)
# Outputs: the count on stdout
#######################################
line_count() {
  [[ -z "${1}" ]] && { echo 0; return; }
  echo "${1}" | wc -l | tr -d ' '
}

# --- Help ---

help() {
  cat <<EOF
${c_green}effective-permissions${c_rst} — print merged Claude Code permission rules (read-only)

${c_bold}Usage:${c_rst}
  zsh $HOME/.claude/skills/ari-use-config/bin/effective-permissions.zsh [OPTIONS]

${c_bold}Options:${c_rst}
  --dir DIR     Project directory to resolve project settings from (default: \$PWD)
  --verbose     Enable debug logging
  -h, --help    Show this help

${c_bold}Output:${c_rst}
  status=ok|partial|failed   degraded if any present file was unreadable/malformed
  managed_only=true|false    enterprise allowManagedPermissionRulesOnly is set
  SOURCES / ALLOW / ASK / DENY sections (deny wins everywhere)

${c_bold}Sources merged:${c_rst}
  enterprise-managed  $(managed_settings_path)
  user                \$HOME/.claude/settings.json
  project             <root>/.claude/settings.json (+ .local.json)

${c_bold}Examples:${c_rst}
  zsh $HOME/.claude/skills/ari-use-config/bin/effective-permissions.zsh
  zsh $HOME/.claude/skills/ari-use-config/bin/effective-permissions.zsh --dir /path/to/repo
EOF
}

# --- Main ---

main() {
  check_prerequisites || exit 1

  # === PARSE ===
  local verbose=false dir=""
  while (( $# > 0 )); do case "${1}" in
    -h|--help)  help; return 0 ;;
    --verbose)  verbose=true; shift ;;
    --dir)      dir="${2:?--dir requires a value}"; shift 2 ;;
    -*)         log::err "Unknown flag | flag='${1}'"; help; return 1 ;;
    *)          log::err "Unexpected argument | argument='${1}'"; help; return 1 ;;
  esac; done

  export VERBOSE="${verbose}"

  # === MASSAGE ===
  [[ -n "${dir}" ]] || dir="${PWD}"
  dir="${dir:A}"

  local project_root=""
  project_root="$(find_project_root "${dir}")" || project_root="${dir}"

  local managed user project project_local
  managed="$(managed_settings_path)"
  user="${HOME}/.claude/settings.json"
  project="${project_root}/.claude/settings.json"
  project_local="${project_root}/.claude/settings.local.json"

  typeset -gA SOURCE_LABELS SOURCE_STATE
  SOURCE_LABELS=(
    "${managed}"       "enterprise-managed"
    "${user}"          "user"
    "${project}"       "project"
    "${project_local}" "project-local"
  )
  typeset -ga SOURCE_FILES VALID_FILES
  SOURCE_FILES=("${managed}" "${user}" "${project}" "${project_local}")

  log::debug "Resolved | dir='${dir}' project_root='${project_root}'"

  # === VALIDATE ===
  [[ -d "${project_root}" ]] || { log::err "Project root is not a directory | project_root='${project_root}'"; return 1; }

  local f state degraded=false
  VALID_FILES=()
  for f in "${SOURCE_FILES[@]}"; do
    state="$(classify_source "${f}")"
    SOURCE_STATE[${f}]="${state}"
    if [[ "${state}" == "ok" ]]; then
      VALID_FILES+=("${f}")
      continue
    fi
    if [[ "${state}" == "unreadable" || "${state}" == "invalid" ]]; then
      log::warn "Source ${state} — skipped | path='${f}'"
      degraded=true
    fi
  done

  # Enterprise lockdown: when set, ONLY the managed file's rules apply.
  local managed_only=false
  if [[ "${SOURCE_STATE[${managed}]}" == "ok" ]] && \
     [[ "$(jq -r '.allowManagedPermissionRulesOnly // false' "${managed}")" == "true" ]]; then
    managed_only=true
    VALID_FILES=("${managed}")
    log::warn "Managed lockdown — only enterprise rules apply | flag='allowManagedPermissionRulesOnly'"
  fi

  local load_status="ok"
  if [[ "${managed_only}" == "true" ]]; then
    load_status="ok"
  elif (( ${#VALID_FILES} == 0 )); then
    load_status="failed"
  elif [[ "${degraded}" == "true" ]]; then
    load_status="partial"
  fi

  # === LOGIC ===
  local allow_rules ask_rules deny_rules
  allow_rules="$(extract_rules allow | sort -u)"
  ask_rules="$(extract_rules ask | sort -u)"
  deny_rules="$(extract_rules deny | sort -u)"

  log::info "Merged permissions | status='${load_status}' managed_only='${managed_only}' allow='$(line_count "${allow_rules}")' ask='$(line_count "${ask_rules}")' deny='$(line_count "${deny_rules}")'"

  cat <<EOF
status=${load_status}
managed_only=${managed_only}
project_root=${project_root}
allow_count=$(line_count "${allow_rules}")
ask_count=$(line_count "${ask_rules}")
deny_count=$(line_count "${deny_rules}")
EOF

  echo "=== start SOURCES ==="
  for f in "${SOURCE_FILES[@]}"; do
    printf '%s\t%s\t%s\n' "${SOURCE_LABELS[${f}]}" "${SOURCE_STATE[${f}]}" "${f}"
  done
  echo "=== end SOURCES ==="

  echo "=== start ALLOW ==="
  [[ -n "${allow_rules}" ]] && echo "${allow_rules}"
  echo "=== end ALLOW ==="

  echo "=== start ASK ==="
  [[ -n "${ask_rules}" ]] && echo "${ask_rules}"
  echo "=== end ASK ==="

  echo "=== start DENY ==="
  [[ -n "${deny_rules}" ]] && echo "${deny_rules}"
  echo "=== end DENY ==="

  log::info "Done | status='${load_status}'"
}

main "${@}"
