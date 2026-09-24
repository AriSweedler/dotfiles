#!/usr/bin/env zsh
# asks.zsh — the asks table of a working doc (`/ari-hemingway--structure-working-doc`).
# asks.json is the source of truth for id, title, needs, status, owner; the prose lives in
# asks/<id>.md. `table` flattens the dependency DAG so every Needs cites an earlier row, and
# refuses to print a table that fails `check`. Writes go through jq to a temp file, then mv.

set -euo pipefail

readonly SCRIPT_DIR="${0:A:h}"
# Shared libs resolve through the symlink farm, not ${SCRIPT_DIR:h:h}: skills are spread
# across dotfiles tiers, so a relative hop lands in whichever tier this script sits in.
readonly SKILLS_DIR="${HOME}/.claude/skills"
readonly LIB_DIR="${SCRIPT_DIR:h}/lib"
readonly TEMPLATE="${SCRIPT_DIR:h}/templates/ask.md"

# --- Constants ---

readonly DEFAULT_STATUS="todo"
readonly DEFAULT_OWNER="main"

# --- Logging ---

readonly LIB_LOGGING="${SKILLS_DIR}/ari-skill-shellscripts/lib/logging.zsh"
if [[ ! -r "${LIB_LOGGING}" ]]; then
  print -u2 "[ERROR] missing shared logging lib | path='${LIB_LOGGING}'"
  exit 1
fi
source "${LIB_LOGGING}"

# --- Prerequisites ---

check_prerequisites() {
  local missing=()
  command -v jq >/dev/null 2>&1 || missing+=("jq")
  [[ -f "${LIB_DIR}/asks.jq" ]] || missing+=("${LIB_DIR}/asks.jq")
  [[ -f "${TEMPLATE}" ]] || missing+=("${TEMPLATE}")
  if (( ${#missing} > 0 )); then
    log::err "Missing required commands or files | missing='${(j:, :)missing}'"
    return 1
  fi
}

# --- Help ---

help() {
  cat <<EOH
${c_green}asks${c_rst} — add, update, check and render the asks table of a working doc

${c_bold}Usage:${c_rst}
  zsh $HOME/.claude/skills/ari-hemingway--structure-working-doc/bin/asks.zsh <command> --file ASKS.json [OPTIONS]

${c_bold}Commands:${c_rst}
  add     --id SLUG --title "..." [--needs a,b] [--status S] [--owner O]   append a row; create asks/SLUG.md from the template
  set     --id SLUG [--title "..."] [--needs a,b] [--status S] [--owner O] [--dispatch VEHICLE:REF]
  check                                                                    violations + missing ask files; prints "OK: N rows, ready: ..."
  table   [--links] [--open]                                               the ordered markdown table (--open hides done/dropped rows; refuses on violations)
  graph                                                                    the same DAG as a Mermaid flowchart

${c_bold}Options:${c_rst}
  --file ASKS.json   the table (required; created by add when missing). asks/ sits beside it.
  --needs a,b        comma-separated ids this ask cannot finish before; "" clears
  --status S         todo | running | review | done | dropped
  --owner O          main | user | agent:<name> | fork:<name> | wf:<id>
  -h, --help         Show this help

${c_bold}Exit:${c_rst} 1 on any violation or bad argument.
EOH
}

# --- Helpers ---

jq_lib() { jq -L "${LIB_DIR}" "$@"; }

now_iso() { date '+%Y-%m-%dT%H:%M:%S%z'; }

# "a,b" → JSON array of trimmed non-empty strings; "" → [].
needs_json() {
  local raw="${1}"
  if [[ -z "${raw}" ]]; then print -r -- '[]'; return; fi
  print -r -- "${raw}" | jq -R 'split(",") | map(gsub("^ +| +$"; "")) | map(select(length > 0))'
}

# Overwrite $file with $filter applied to it; extra args are jq args.
rewrite() {
  local file="${1}" filter="${2}"; shift 2
  local tmp
  tmp="$(mktemp "${file}.XXXXXX")"
  if ! jq_lib "$@" "${filter}" "${file}" > "${tmp}"; then
    rm -f "${tmp}"; return 1
  fi
  mv "${tmp}" "${file}"
}

ensure_file() {
  local file="${1}"
  [[ -f "${file}" ]] && return 0
  print -r -- '{"asks": []}' > "${file}"
  log::info "Created asks file | file='${file}'"
}

row_exists() {
  local file="${1}" id="${2}"
  jq_lib -e --arg id "${id}" 'include "asks"; by_id | has($id)' "${file}" >/dev/null 2>&1
}

# Run check quietly; on failure print its output and the caller's message.
check_or_refuse() {
  local file="${1}" what="${2}" out
  if ! out="$(cmd_check "${file}" 2>&1)"; then
    print -u2 -r -- "${out}"
    log::err "Refusing to render a ${what} that fails check"
    return 1
  fi
}

# --- Commands ---

cmd_add() {
  local file="${1}" id="${2}" title="${3}" needs="${4}" ask_status="${5}" owner="${6}"
  [[ -n "${id}" && -n "${title}" ]] || { log::err "add needs --id and --title"; return 1; }
  ensure_file "${file}"
  if row_exists "${file}" "${id}"; then log::err "Ask already exists | id='${id}'"; return 1; fi
  local needs_arr
  needs_arr="$(needs_json "${needs}")"
  rewrite "${file}" '.asks += [{id: $id, title: $title, needs: $needs, status: $status, owner: $owner, updated: $now}]' \
    --arg id "${id}" --arg title "${title}" --argjson needs "${needs_arr}" \
    --arg status "${ask_status}" --arg owner "${owner}" --arg now "$(now_iso)"
  local dir="${file:h}/asks" ask_file
  ask_file="${dir}/${id}.md"
  mkdir -p "${dir}"
  if [[ ! -f "${ask_file}" ]]; then
    local body
    body="$(<"${TEMPLATE}")"
    print -r -- "${body//\{\{title\}\}/${title}}" > "${ask_file}"
  fi
  log::ok "Added ask | id='${id}' file='${ask_file}'"
}

cmd_set() {
  local file="${1}" id="${2}" title="${3}" needs="${4}" needs_given="${5}" ask_status="${6}" owner="${7}" dispatch="${8}"
  [[ -n "${id}" ]] || { log::err "set needs --id"; return 1; }
  [[ -f "${file}" ]] || { log::err "Asks file not found | file='${file}'"; return 1; }
  if ! row_exists "${file}" "${id}"; then log::err "Unknown ask | id='${id}'"; return 1; fi
  local patch='{}'
  [[ -n "${title}" ]]      && patch="$(jq -cn --argjson p "${patch}" --arg v "${title}"      '$p + {title: $v}')"
  [[ -n "${ask_status}" ]] && patch="$(jq -cn --argjson p "${patch}" --arg v "${ask_status}" '$p + {status: $v}')"
  [[ -n "${owner}" ]]      && patch="$(jq -cn --argjson p "${patch}" --arg v "${owner}"      '$p + {owner: $v}')"
  if (( needs_given )); then
    patch="$(jq -cn --argjson p "${patch}" --argjson v "$(needs_json "${needs}")" '$p + {needs: $v}')"
  fi
  if [[ -n "${dispatch}" ]]; then
    local vehicle="${dispatch%%:*}" ref="${dispatch#*:}"
    patch="$(jq -cn --argjson p "${patch}" --arg v "${vehicle}" --arg r "${ref}" '$p + {dispatch: {vehicle: $v, ref: $r}}')"
  fi
  rewrite "${file}" '.asks |= map(if .id == $id then . + $patch + {updated: $now} else . end)' \
    --arg id "${id}" --argjson patch "${patch}" --arg now "$(now_iso)"
  log::ok "Updated ask | id='${id}' patch='${patch}'"
}

cmd_check() {
  local file="${1}"
  [[ -f "${file}" ]] || { log::err "Asks file not found | file='${file}'"; return 1; }
  local violations n_rows ready id missing=()
  violations="$(jq_lib -r 'include "asks"; violations[]' "${file}")"
  n_rows="$(jq_lib 'include "asks"; rows | length' "${file}")"
  for id in "${(@f)$(jq_lib -r 'include "asks"; rows[].id' "${file}")}"; do
    [[ -n "${id}" && ! -f "${file:h}/asks/${id}.md" ]] && missing+=("${id}: no asks/${id}.md")
  done
  if [[ -n "${violations}" || ${#missing} -gt 0 ]]; then
    log::err "Asks table has violations | rows='${n_rows}'"
    [[ -n "${violations}" ]] && print -r -- "${violations}"
    (( ${#missing} > 0 )) && print -l -- "${missing[@]}"
    return 1
  fi
  ready="$(jq_lib -r 'include "asks"; ready | join(", ")' "${file}")"
  log::ok "Asks table is linear | rows='${n_rows}' ready='${ready:-none}'"
  echo "OK: ${n_rows} rows, ready: ${ready:-none}"
}

cmd_table() {
  local file="${1}" links="${2}" open="${3}"
  check_or_refuse "${file}" "table" || return 1
  jq_lib -r --argjson links "${links}" --argjson open "${open}" 'include "asks"; table_md($links; $open)' "${file}"
  if [[ "${open}" == true ]]; then
    local hidden
    hidden="$(jq_lib 'include "asks"; hidden_count' "${file}")"
    if (( hidden > 0 )); then
      echo ""
      echo "${hidden} settled rows hidden (full table in draft.md)"
    fi
  fi
}

cmd_graph() {
  local file="${1}"
  check_or_refuse "${file}" "graph" || return 1
  jq_lib -r 'include "asks"; mermaid' "${file}"
}

# --- Main ---

main() {
  check_prerequisites || exit 1

  # === PARSE ===
  local cmd="" file="" id="" title="" needs="" needs_given=0 ask_status="" owner="" dispatch="" links=false open=false
  (( $# > 0 )) || { help; return 1; }
  case "${1}" in
    -h|--help) help; return 0 ;;
    add|set|check|table|graph) cmd="${1}"; shift ;;
    *) log::err "Unknown command | command='${1}'"; help; return 1 ;;
  esac
  while (( $# > 0 )); do case "${1}" in
    -h|--help)   help; return 0 ;;
    --file)      file="${2:?--file requires a value}"; shift 2 ;;
    --id)        id="${2:?--id requires a value}"; shift 2 ;;
    --title)     title="${2:?--title requires a value}"; shift 2 ;;
    --needs)     needs="${2-}"; needs_given=1; shift 2 ;;
    --status)    ask_status="${2:?--status requires a value}"; shift 2 ;;
    --owner)     owner="${2:?--owner requires a value}"; shift 2 ;;
    --dispatch)  dispatch="${2:?--dispatch requires a value}"; shift 2 ;;
    --links)     links=true; shift ;;
    --open)      open=true; shift ;;
    -*)          log::err "Unknown flag | flag='${1}'"; help; return 1 ;;
    *)           log::err "Unexpected argument | argument='${1}'"; help; return 1 ;;
  esac; done

  # === VALIDATE ===
  [[ -n "${file}" ]] || { log::err "Missing --file"; help; return 1; }
  if [[ -n "${ask_status}" ]]; then
    case "${ask_status}" in todo|running|review|done|dropped) ;; *) log::err "Invalid status | status='${ask_status}'"; return 1 ;; esac
  fi

  # === LOGIC ===
  case "${cmd}" in
    add)   cmd_add "${file}" "${id}" "${title}" "${needs}" "${ask_status:-${DEFAULT_STATUS}}" "${owner:-${DEFAULT_OWNER}}" ;;
    set)   cmd_set "${file}" "${id}" "${title}" "${needs}" "${needs_given}" "${ask_status}" "${owner}" "${dispatch}" ;;
    check) cmd_check "${file}" ;;
    table) cmd_table "${file}" "${links}" "${open}" ;;
    graph) cmd_graph "${file}" ;;
  esac
}

main "${@}"
