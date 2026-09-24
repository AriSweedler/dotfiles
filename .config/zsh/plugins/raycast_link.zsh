# raycast_link — the widget that names a Raycast action with its Karabiner binding; the angle
# brackets wrap the link and are not part of it:
#   <[Raycast: Clipboard History | key: '✦4'](raycast://extensions/raycast/clipboard-history/clipboard-history)>
#
# Bindings are declared once, in karabiner.ts/src/raycast_bindings.json. karabiner.ts compiles
# that file into Karabiner rules (src/raycast.ts) and this plugin renders it, so the binding a
# message shows is the binding the keyboard has. Raycast's own hotkeys sit in its encrypted store
# and cannot be read or set from a shell; the Karabiner binding is the one that is versioned.
#
# Usage: raycast_link <alias> [--plain] | --list | --check | --set <alias> <chord> [--path P --title T]
# Env (tests point these at fixtures): RAYCAST_LINK_BINDINGS, RAYCAST_LINK_KARABINER_JSON,
# RAYCAST_LINK_BAKE.

(( ${+functions[log::info]} )) || source "${${(%):-%x}:A:h}/log.zsh"

: "${RAYCAST_LINK_BINDINGS:=${XDG_CONFIG_HOME:-${HOME}/.config}/karabiner/karabiner.ts/src/raycast_bindings.json}"
: "${RAYCAST_LINK_KARABINER_JSON:=${XDG_CONFIG_HOME:-${HOME}/.config}/karabiner/karabiner.json}"
: "${RAYCAST_LINK_BAKE:=${XDG_CONFIG_HOME:-${HOME}/.config}/karabiner/bin/bake}"

# Raycast's shortcut convention, the one place to edit: the Karabiner Hyper set is ✦, any other
# modifier set is glyphs in macOS order with no separators, keys get their glyph or upper-case.
typeset -gA RAYCAST_LINK_GLYPHS=(
  control ⌃  option ⌥  shift ⇧  command ⌘  caps_lock ⇪  fn fn
  return_or_enter ⏎  delete_or_backspace ⌫  tab ⇥  spacebar Space  escape ⎋
  up_arrow ↑  down_arrow ↓  left_arrow ←  right_arrow →
  equal_sign =  hyphen -  open_bracket [  close_bracket ]  period .  comma ,
  grave_accent_and_tilde '`'  semicolon ';'  quote "'"  slash /  backslash '\'
)
# Symbol and word aliases for keys, normalized to karabiner key names before anything else
# looks at them; the same set utils/actions.ts accepts, so the JSON may use either spelling.
typeset -gA RAYCAST_LINK_KEY_ALIASES=(
  '=' equal_sign  '-' hyphen  minus hyphen
  '[' open_bracket  ']' close_bracket  '.' period  ',' comma
  '`' grave_accent_and_tilde  ';' semicolon  "'" quote  / slash  '\' backslash
  '⏎' return_or_enter  return return_or_enter
  '⌫' delete_or_backspace  delete delete_or_backspace
  space spacebar
)
typeset -ga RAYCAST_LINK_MODIFIER_ORDER=(fn control option shift command caps_lock)
typeset -gr RAYCAST_LINK_HYPER_SET="control option shift command"
typeset -gA RAYCAST_LINK_MODIFIER_ALIASES=(
  hyper "${RAYCAST_LINK_HYPER_SET}"
  cmd command  command command
  ctrl control  control control
  opt option  option option  alt option
  shift shift  fn fn
  caps caps_lock  caps_lock caps_lock
)

# Input: a chord like hyper+4 or cmd+shift+k. Output: two lines, the key and the modifiers in
# canonical order (space-joined, may be empty). Exit 1 with a log::err on a bad token.
function raycast_link::parse_chord() {
  local chord="${1}" token modifier key
  local -a tokens ordered
  local -A have
  tokens=("${(@s:+:)chord}")
  key="${tokens[-1]:-}"
  key="${key:l}"
  key="${RAYCAST_LINK_KEY_ALIASES[${key}]:-${key}}"
  if [[ ! "${key}" =~ '^[a-z0-9_]+$' ]]; then
    log::err "Invalid key | key='${key}' chord='${1}' expected='a-z, 0-9, a karabiner key name like return_or_enter, or one of ${(kj: :)RAYCAST_LINK_KEY_ALIASES}'"
    return 1
  fi
  for token in "${(@)tokens[1,-2]}"; do
    token="${token:l}"
    if [[ -z "${RAYCAST_LINK_MODIFIER_ALIASES[${token}]:-}" ]]; then
      log::err "Unknown modifier | modifier='${token}' chord='${1}' valid='${(kj:, :)RAYCAST_LINK_MODIFIER_ALIASES}'"
      return 1
    fi
    for modifier in ${=RAYCAST_LINK_MODIFIER_ALIASES[${token}]}; do have[${modifier}]=1; done
  done
  for modifier in "${RAYCAST_LINK_MODIFIER_ORDER[@]}"; do
    (( ${+have[${modifier}]} )) && ordered+=("${modifier}")
  done
  print -r -- "${key}"
  print -r -- "${(j: :)ordered}"
}

# Input: a chord. Output: its glyph string, e.g. ✦4, ⌃⌥⇧K, ⌘⇧⏎.
function raycast_link::render_binding() {
  local -a parsed
  parsed=("${(@f)$(raycast_link::parse_chord "${1}")}")
  (( ${#parsed} >= 1 )) && [[ -n "${parsed[1]}" ]] || return 1
  local key="${parsed[1]}" modifiers="${parsed[2]:-}" out="" modifier
  if [[ "${modifiers}" == "${RAYCAST_LINK_HYPER_SET}" ]]; then
    out="✦"
  else
    for modifier in ${=modifiers}; do out+="${RAYCAST_LINK_GLYPHS[${modifier}]}"; done
  fi
  if [[ -n "${RAYCAST_LINK_GLYPHS[${key}]:-}" ]]; then
    out+="${RAYCAST_LINK_GLYPHS[${key}]}"
  elif [[ "${key}" =~ '^[a-z]$' ]]; then
    out+="${key:u}"
  else
    out+="${key}"
  fi
  print -r -- "${out}"
}

# Input: alias. Output: its entry as one compact JSON line; exit 1 naming the file when absent.
function raycast_link::entry() {
  local alias_="${1}" entry
  if [[ ! -r "${RAYCAST_LINK_BINDINGS}" ]]; then
    log::err "Bindings file missing | file='${RAYCAST_LINK_BINDINGS}'"
    return 1
  fi
  entry="$(jq -c --arg a "${alias_}" '.[] | select(.alias == $a)' "${RAYCAST_LINK_BINDINGS}")"
  if [[ -z "${entry}" ]]; then
    log::err "Unknown alias | alias='${alias_}' file='${RAYCAST_LINK_BINDINGS}' known='$(jq -r '[.[].alias] | join(", ")' "${RAYCAST_LINK_BINDINGS}")'"
    return 1
  fi
  print -r -- "${entry}"
}

# Input: path, key, canonical modifiers. Exit 0 iff the compiled karabiner.json has a manipulator
# from that key with exactly those mandatory modifiers whose first to-event opens the deeplink.
function raycast_link::compiled_has() {
  local path_="${1}" key="${2}" modifiers="${3}" want found
  [[ -r "${RAYCAST_LINK_KARABINER_JSON}" ]] || return 1
  want="$(print -r -- "${modifiers}" | tr ' ' '\n' | sed '/^$/d' | sort | paste -sd, -)"
  found="$(jq -r --arg cmd "open raycast://${path_}" --arg key "${key}" \
    '[.profiles[].complex_modifications.rules[].manipulators[]
      | select((.to[0].shell_command? // "") == $cmd and (.from.key_code? // "") == $key)
      | ((.from.modifiers.mandatory // []) | sort | join(","))] | .[]' "${RAYCAST_LINK_KARABINER_JSON}" 2>/dev/null)"
  [[ $'\n'"${found}"$'\n' == *$'\n'"${want}"$'\n'* ]]
}

# Input: an entry JSON line. Exit 0 iff it is compiled.
function raycast_link::entry_compiled() {
  local entry="${1}"
  local -a parsed
  parsed=("${(@f)$(raycast_link::parse_chord "$(print -r -- "${entry}" | jq -r .chord)")}")
  (( ${#parsed} >= 1 )) || return 1
  raycast_link::compiled_has "$(print -r -- "${entry}" | jq -r .path)" "${parsed[1]}" "${parsed[2]:-}"
}

# Input: alias, plain flag (0/1). Output: the widget line.
function raycast_link::widget() {
  local alias_="${1}" plain="${2}" entry title path_ chord binding suffix=""
  entry="$(raycast_link::entry "${alias_}")" || return 1
  title="$(print -r -- "${entry}" | jq -r .title)"
  path_="$(print -r -- "${entry}" | jq -r .path)"
  chord="$(print -r -- "${entry}" | jq -r .chord)"
  binding="$(raycast_link::render_binding "${chord}")" || return 1
  raycast_link::entry_compiled "${entry}" || suffix=" (not compiled yet)"
  local text="Raycast: ${title} | key: '${binding}'${suffix}"
  if (( plain )); then
    print -r -- "<${text}> raycast://${path_}"
  else
    print -r -- "<[${text}](raycast://${path_})>"
  fi
}

# Output: one line per binding: alias, binding, title, deeplink.
function raycast_link::list() {
  local entry alias_ chord
  [[ -r "${RAYCAST_LINK_BINDINGS}" ]] || { log::err "Bindings file missing | file='${RAYCAST_LINK_BINDINGS}'"; return 1; }
  for entry in "${(@f)$(jq -c '.[]' "${RAYCAST_LINK_BINDINGS}")}"; do
    alias_="$(print -r -- "${entry}" | jq -r .alias)"
    chord="$(print -r -- "${entry}" | jq -r .chord)"
    print -r -- "${alias_}  $(raycast_link::render_binding "${chord}")  $(print -r -- "${entry}" | jq -r .title)  raycast://$(print -r -- "${entry}" | jq -r .path)"
  done
}

# Output: OK or MISSING per alias against the compiled karabiner.json; exit 1 if any is missing.
function raycast_link::check() {
  local entry alias_ status_word rc=0
  [[ -r "${RAYCAST_LINK_BINDINGS}" ]] || { log::err "Bindings file missing | file='${RAYCAST_LINK_BINDINGS}'"; return 1; }
  for entry in "${(@f)$(jq -c '.[]' "${RAYCAST_LINK_BINDINGS}")}"; do
    alias_="$(print -r -- "${entry}" | jq -r .alias)"
    if raycast_link::entry_compiled "${entry}"; then
      status_word=OK
    else
      status_word=MISSING; rc=1
    fi
    print -r -- "${status_word} ${alias_} $(raycast_link::render_binding "$(print -r -- "${entry}" | jq -r .chord)")"
  done
  (( rc )) && log::err "Bindings not compiled | karabiner_json='${RAYCAST_LINK_KARABINER_JSON}' fix='run bake (raycast-link --set does)'"
  return "${rc}"
}

# Input: alias, chord, optional path and title (required for a new alias). Upserts the JSON,
# runs bake so Karabiner picks the rule up, then checks.
function raycast_link::set() {
  local alias_="${1}" chord="${2}" path_="${3:-}" title="${4:-}" tmp existing
  raycast_link::parse_chord "${chord}" >/dev/null || return 1
  [[ -r "${RAYCAST_LINK_BINDINGS}" ]] || { log::err "Bindings file missing | file='${RAYCAST_LINK_BINDINGS}'"; return 1; }
  existing="$(jq -c --arg a "${alias_}" '.[] | select(.alias == $a)' "${RAYCAST_LINK_BINDINGS}")"
  if [[ -z "${existing}" && ( -z "${path_}" || -z "${title}" ) ]]; then
    log::err "New alias needs --path and --title | alias='${alias_}' path='${path_}' title='${title}'"
    return 1
  fi
  tmp="${RAYCAST_LINK_BINDINGS}.tmp.$$"
  jq --arg a "${alias_}" --arg c "${chord}" --arg p "${path_}" --arg t "${title}" '
    if any(.[]; .alias == $a) then
      map(if .alias == $a then .chord = $c | (if $p != "" then .path = $p else . end) | (if $t != "" then .title = $t else . end) else . end)
    else
      . + [{alias: $a, title: $t, path: $p, chord: $c}]
    end' "${RAYCAST_LINK_BINDINGS}" > "${tmp}" && mv "${tmp}" "${RAYCAST_LINK_BINDINGS}"
  log::info "Binding written | alias='${alias_}' chord='${chord}' file='${RAYCAST_LINK_BINDINGS}'"
  if [[ ! -x "${RAYCAST_LINK_BAKE}" ]]; then
    log::err "bake not found | bake='${RAYCAST_LINK_BAKE}'"
    return 1
  fi
  XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-${HOME}/.config}" "${RAYCAST_LINK_BAKE}" >&2 || { log::err "bake failed | bake='${RAYCAST_LINK_BAKE}'"; return 1; }
  raycast_link::check
}

function raycast_link::help() {
  cat >&2 <<EOF
raycast-link — a Raycast action as a link with its Karabiner binding

  raycast-link <alias>            markdown: <[Raycast: Title | key: '✦4'](raycast://path)>
  raycast-link <alias> --plain    <Raycast: Title | key: '✦4'> raycast://path
  raycast-link --list             one line per binding
  raycast-link --check            OK/MISSING per binding against the compiled karabiner.json
  raycast-link --set <alias> <chord> [--path P --title T]   upsert, bake, check

Bindings: ${RAYCAST_LINK_BINDINGS}
EOF
}

function raycast_link() {
  local mode="" alias_="" chord="" path_="" title="" plain=0
  while (( $# > 0 )); do case "${1}" in
    -h|--help) raycast_link::help; return 0 ;;
    --plain)   plain=1; shift ;;
    --list)    mode=list; shift ;;
    --check)   mode=check; shift ;;
    --set)     mode=set; alias_="${2:?--set needs <alias> <chord>}"; chord="${3:?--set needs <alias> <chord>}"; shift 3 ;;
    --path)    path_="${2:?--path needs a value}"; shift 2 ;;
    --title)   title="${2:?--title needs a value}"; shift 2 ;;
    -*)        log::err "Unknown flag | flag='${1}'"; raycast_link::help; return 1 ;;
    *)         [[ -z "${mode}" ]] && mode=widget; alias_="${1}"; shift ;;
  esac; done
  case "${mode}" in
    widget) raycast_link::widget "${alias_}" "${plain}" ;;
    list)   raycast_link::list ;;
    check)  raycast_link::check ;;
    set)    raycast_link::set "${alias_}" "${chord}" "${path_}" "${title}" ;;
    *)      raycast_link::help; return 1 ;;
  esac
}
