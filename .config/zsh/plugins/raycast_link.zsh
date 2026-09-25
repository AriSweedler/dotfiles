# raycast_link — the `link` subsystem of `dotfiles raycast` (router: plugin raycast.zsh): the
# widget that names a Raycast action with its Karabiner binding; the angle brackets wrap the
# link and are not part of it:
#   <[Raycast: Clipboard History | key: '✦4'](raycast://extensions/raycast/clipboard-history/clipboard-history)>
#
# The bindings live in karabiner.ts's TypeScript tables (src/modes/*.ts, src/raycast_shortcuts.ts),
# which bake compiles into Karabiner rules. This plugin asks the same toolchain for them
# (`tsx src/generate_bindings.ts --stdout`, the module `npm run build` also uses to write
# src/raycast_bindings.json), so what a message shows is what the keyboard has; that JSON file
# is bake's artifact for reading and diffing (canonicalised by json-sort, like every generated
# JSON in the dotfiles), not an input here. To change a binding: edit the table, run bake.
# Raycast's own hotkey settings stay empty for anything bound here; its encrypted store cannot
# be read or set from a shell anyway.
#
# An entry is addressed by its command slug, the last segment of the deeplink path
# (clipboard-history, left-half, my-schedule), or by the full path. Chords: a direct chord is
# "ctrl+opt+h" (rendered ⌃⌥H); a layer chord is "hyper+k d" (space = then, rendered ✦K D).
# --check verifies direct chords against the compiled karabiner.json exactly (`open -g` iff
# keepFocus); layer chords are reported as `layer`, not verified.
#
# Raycast asks "Always allow" once per command launched by deeplink and keeps the answers in the
# plain plist com.raycast.macos (alwaysAllowCommandDeeplinking, <id> = 1); each binding's allowId
# names its key, and --allow writes the missing ones so the prompt never shows. bake and the
# raycast_sync step run --allow.
#
# Usage: raycast_link <slug|path> [--plain] | --list | --check | --allow [--dry-run]
# Env: ARI_DOTFILES_RAYCAST_LINK_KARABINER_TS (the karabiner.ts checkout), ARI_DOTFILES_RAYCAST_LINK_KARABINER_JSON,
# ARI_DOTFILES_RAYCAST_LINK_DEFAULTS_DOMAIN (a domain name or a plist path), ARI_DOTFILES_RAYCAST_LINK_BINDINGS_CMD (test
# seam: a command whose stdout is the bindings JSON, e.g. `cat fixture.json`).

(( ${+functions[log::info]} )) || source "${${(%):-%x}:A:h}/log.zsh"

: "${ARI_DOTFILES_RAYCAST_LINK_KARABINER_TS:=${XDG_CONFIG_HOME:-${HOME}/.config}/karabiner/karabiner.ts}"
: "${ARI_DOTFILES_RAYCAST_LINK_KARABINER_JSON:=${XDG_CONFIG_HOME:-${HOME}/.config}/karabiner/karabiner.json}"
: "${ARI_DOTFILES_RAYCAST_LINK_DEFAULTS_DOMAIN:=com.raycast.macos}"
: "${ARI_DOTFILES_RAYCAST_LINK_BINDINGS_CMD:=}"
# Guarded so re-sourcing (plugin loader plus the dispatcher) never trips "read-only variable".
(( ${+ARI_DOTFILES_RAYCAST_LINK_ALLOW_KEY} )) || typeset -gr ARI_DOTFILES_RAYCAST_LINK_ALLOW_KEY="alwaysAllowCommandDeeplinking"
# One generator run per invocation; keyed by the seam so a test that swaps fixtures reloads.
typeset -g ARI_DOTFILES_RAYCAST_LINK_BINDINGS_CACHE="" ARI_DOTFILES_RAYCAST_LINK_BINDINGS_CACHE_KEY=""

# Raycast's shortcut convention, the one place to edit: the Karabiner Hyper set is ✦, any other
# modifier set is glyphs in macOS order with no separators, keys get their glyph or upper-case.
typeset -gA ARI_DOTFILES_RAYCAST_LINK_GLYPHS=(
  control ⌃  option ⌥  shift ⇧  command ⌘  caps_lock ⇪  fn fn
  return_or_enter ⏎  delete_or_backspace ⌫  tab ⇥  spacebar Space  escape ⎋
  up_arrow ↑  down_arrow ↓  left_arrow ←  right_arrow →
  equal_sign =  hyphen -  open_bracket [  close_bracket ]  period .  comma ,
  grave_accent_and_tilde '`'  semicolon ';'  quote "'"  slash /  backslash '\'
)
# Symbol and word aliases for keys, normalized to karabiner key names before anything else
# looks at them; the same set utils/actions.ts accepts, so a table may use either spelling.
typeset -gA ARI_DOTFILES_RAYCAST_LINK_KEY_ALIASES=(
  '=' equal_sign  '-' hyphen  minus hyphen
  '[' open_bracket  ']' close_bracket  '.' period  ',' comma
  '`' grave_accent_and_tilde  ';' semicolon  "'" quote  / slash  '\' backslash
  '⏎' return_or_enter  return return_or_enter
  '⌫' delete_or_backspace  delete delete_or_backspace
  space spacebar
)
typeset -ga ARI_DOTFILES_RAYCAST_LINK_MODIFIER_ORDER=(fn control option shift command caps_lock)
(( ${+ARI_DOTFILES_RAYCAST_LINK_HYPER_SET} )) || typeset -gr ARI_DOTFILES_RAYCAST_LINK_HYPER_SET="control option shift command"
typeset -gA ARI_DOTFILES_RAYCAST_LINK_MODIFIER_ALIASES=(
  hyper "${ARI_DOTFILES_RAYCAST_LINK_HYPER_SET}"
  cmd command  command command
  ctrl control  control control
  opt option  option option  alt option
  shift shift  fn fn
  caps caps_lock  caps_lock caps_lock
)

# --- bindings source ---

# Loads the bindings document into ARI_DOTFILES_RAYCAST_LINK_BINDINGS_CACHE (current shell, so callers may
# read the global after this returns). Runs the seam command when set, else the karabiner.ts
# generator through its own tsx.
function raycast_link::load_bindings() {
  local key="${ARI_DOTFILES_RAYCAST_LINK_BINDINGS_CMD}|${ARI_DOTFILES_RAYCAST_LINK_KARABINER_TS}" out
  if [[ -n "${ARI_DOTFILES_RAYCAST_LINK_BINDINGS_CACHE}" && "${ARI_DOTFILES_RAYCAST_LINK_BINDINGS_CACHE_KEY}" == "${key}" ]]; then
    return 0
  fi
  if [[ -n "${ARI_DOTFILES_RAYCAST_LINK_BINDINGS_CMD}" ]]; then
    if ! out="$(eval "${ARI_DOTFILES_RAYCAST_LINK_BINDINGS_CMD}")"; then
      log::err "Bindings command failed | cmd='${ARI_DOTFILES_RAYCAST_LINK_BINDINGS_CMD}'"
      return 1
    fi
  else
    local tsx="${ARI_DOTFILES_RAYCAST_LINK_KARABINER_TS}/node_modules/.bin/tsx"
    if [[ ! -x "${tsx}" ]]; then
      log::err "karabiner.ts not built | fix='run bake' tsx='${tsx}'"
      return 1
    fi
    if ! out="$(cd "${ARI_DOTFILES_RAYCAST_LINK_KARABINER_TS}" && "${tsx}" src/generate_bindings.ts --stdout 2>/dev/null)"; then
      log::err "Bindings generator failed | fix='run bake' dir='${ARI_DOTFILES_RAYCAST_LINK_KARABINER_TS}'"
      return 1
    fi
    # Modules the generator imports log their setup on stdout (karabiner_script prints the repo
    # and npm paths); the document is the one line that is a JSON object.
    out="$(print -r -- "${out}" | awk '/^\{/ { line = $0 } END { print line }')"
  fi
  if ! print -r -- "${out}" | jq -e '.bindings | type == "array"' >/dev/null 2>&1; then
    log::err "Bindings output is not the expected JSON | expected='{\"bindings\": [...]}' head='${${out//$'\n'/ }[1,80]}'"
    return 1
  fi
  ARI_DOTFILES_RAYCAST_LINK_BINDINGS_CACHE="${out}"
  ARI_DOTFILES_RAYCAST_LINK_BINDINGS_CACHE_KEY="${key}"
}

# Output: one compact JSON line per binding, in generator order (sorted by path).
function raycast_link::entries() {
  print -r -- "${ARI_DOTFILES_RAYCAST_LINK_BINDINGS_CACHE}" | jq -c '.bindings[]'
}

# Input: an entry. Output: its command slug, the last segment of the path.
function raycast_link::slug() {
  print -r -- "${1}" | jq -r '.path | split("/") | last'
}

# Input: a slug or a full path. Output: the entry; exit 1 naming the known slugs when absent.
function raycast_link::entry() {
  local selector="${1}" entry
  entry="$(print -r -- "${ARI_DOTFILES_RAYCAST_LINK_BINDINGS_CACHE}" | jq -c --arg s "${selector}" '.bindings[] | select(.path == $s or (.path | split("/") | last) == $s)')"
  if [[ -z "${entry}" ]]; then
    log::err "Unknown command | selector='${selector}' known='$(print -r -- "${ARI_DOTFILES_RAYCAST_LINK_BINDINGS_CACHE}" | jq -r '[.bindings[].path | split("/") | last] | join(", ")')' source='karabiner.ts/src (modes/*.ts, raycast_shortcuts.ts)'"
    return 1
  fi
  print -r -- "${entry}"
}

# --- chords ---

# Input: one combo like hyper+4 or cmd+shift+k. Output: two lines, the key and the modifiers in
# canonical order (space-joined, may be empty). Exit 1 with a log::err on a bad token.
function raycast_link::parse_chord() {
  local chord="${1}" token modifier key
  local -a tokens ordered
  local -A have
  tokens=("${(@s:+:)chord}")
  key="${tokens[-1]:-}"
  key="${key:l}"
  key="${ARI_DOTFILES_RAYCAST_LINK_KEY_ALIASES[${key}]:-${key}}"
  if [[ ! "${key}" =~ '^[a-z0-9_]+$' ]]; then
    log::err "Invalid key | key='${key}' chord='${1}' expected='a-z, 0-9, a karabiner key name like return_or_enter, or one of ${(kj: :)ARI_DOTFILES_RAYCAST_LINK_KEY_ALIASES}'"
    return 1
  fi
  for token in "${(@)tokens[1,-2]}"; do
    token="${token:l}"
    if [[ -z "${ARI_DOTFILES_RAYCAST_LINK_MODIFIER_ALIASES[${token}]:-}" ]]; then
      log::err "Unknown modifier | modifier='${token}' chord='${1}' valid='${(kj:, :)ARI_DOTFILES_RAYCAST_LINK_MODIFIER_ALIASES}'"
      return 1
    fi
    for modifier in ${=ARI_DOTFILES_RAYCAST_LINK_MODIFIER_ALIASES[${token}]}; do have[${modifier}]=1; done
  done
  for modifier in "${ARI_DOTFILES_RAYCAST_LINK_MODIFIER_ORDER[@]}"; do
    (( ${+have[${modifier}]} )) && ordered+=("${modifier}")
  done
  print -r -- "${key}"
  print -r -- "${(j: :)ordered}"
}

# Input: one combo. Output: its glyph string, e.g. ✦4, ⌃⌥⇧K, ⇧⌘⏎.
function raycast_link::render_binding() {
  local -a parsed
  parsed=("${(@f)$(raycast_link::parse_chord "${1}")}")
  (( ${#parsed} >= 1 )) && [[ -n "${parsed[1]}" ]] || return 1
  local key="${parsed[1]}" modifiers="${parsed[2]:-}" out="" modifier
  if [[ "${modifiers}" == "${ARI_DOTFILES_RAYCAST_LINK_HYPER_SET}" ]]; then
    out="✦"
  else
    for modifier in ${=modifiers}; do out+="${ARI_DOTFILES_RAYCAST_LINK_GLYPHS[${modifier}]}"; done
  fi
  if [[ -n "${ARI_DOTFILES_RAYCAST_LINK_GLYPHS[${key}]:-}" ]]; then
    out+="${ARI_DOTFILES_RAYCAST_LINK_GLYPHS[${key}]}"
  elif [[ "${key}" =~ '^[a-z]$' ]]; then
    out+="${key:u}"
  else
    out+="${key}"
  fi
  print -r -- "${out}"
}

# Input: a chord, direct ("ctrl+opt+h") or layer ("hyper+k d", space = then). Output: glyphs per
# step, space-joined: ⌃⌥H, ✦K D.
function raycast_link::render_chord() {
  local step rendered
  local -a out
  for step in "${(@s: :)1}"; do
    rendered="$(raycast_link::render_binding "${step}")" || return 1
    out+=("${rendered}")
  done
  print -r -- "${(j: :)out}"
}

# Input: an entry. Output: every chord rendered, space-joined.
function raycast_link::render_entry_chords() {
  local chord
  local -a out
  for chord in "${(@f)$(print -r -- "${1}" | jq -r '.chords[]')}"; do
    out+=("$(raycast_link::render_chord "${chord}")")
  done
  print -r -- "${(j: :)out}"
}

# --- compiled state ---

# Input: path, key, canonical modifiers, keepFocus (true/false). Exit 0 iff the compiled
# karabiner.json has a manipulator from that key with exactly those mandatory modifiers whose
# first to-event opens the deeplink in the form the entry asks for: `open -g` iff keepFocus.
function raycast_link::compiled_has() {
  local path_="${1}" key="${2}" modifiers="${3}" keep_focus="${4:-false}" want found cmd
  [[ -r "${ARI_DOTFILES_RAYCAST_LINK_KARABINER_JSON}" ]] || return 1
  want="$(print -r -- "${modifiers}" | tr ' ' '\n' | sed '/^$/d' | sort | paste -sd, -)"
  cmd="open raycast://${path_}"
  [[ "${keep_focus}" == true ]] && cmd="open -g raycast://${path_}"
  found="$(jq -r --arg cmd "${cmd}" --arg key "${key}" \
    '[.profiles[].complex_modifications.rules[].manipulators[]
      | select((.to[0].shell_command? // "") == $cmd and (.from.key_code? // "") == $key)
      | ((.from.modifiers.mandatory // []) | sort | join(","))] | .[]' "${ARI_DOTFILES_RAYCAST_LINK_KARABINER_JSON}" 2>/dev/null)"
  [[ $'\n'"${found}"$'\n' == *$'\n'"${want}"$'\n'* ]]
}

# Input: an entry. Output: OK when every direct chord is compiled, MISSING when any is not,
# layer when the entry has only layer chords (not verified).
function raycast_link::entry_status() {
  local entry="${1}" chord path_ keep_focus status_word=layer
  local -a parsed
  path_="$(print -r -- "${entry}" | jq -r .path)"
  keep_focus="$(print -r -- "${entry}" | jq -r '.keepFocus // false')"
  for chord in "${(@f)$(print -r -- "${entry}" | jq -r '.chords[]')}"; do
    [[ "${chord}" == *" "* ]] && continue
    parsed=("${(@f)$(raycast_link::parse_chord "${chord}")}")
    if (( ${#parsed} == 0 )) || ! raycast_link::compiled_has "${path_}" "${parsed[1]}" "${parsed[2]:-}" "${keep_focus}"; then
      status_word=MISSING
    elif [[ "${status_word}" == layer ]]; then
      status_word=OK
    fi
  done
  print -r -- "${status_word}"
}

# --- Raycast allow-list ---

# Output: the ids Raycast already allows, one per line. `defaults read` prints the dict in the
# old plist syntax (`"id" = 1;`), the same for a domain name and for a plist path, so it is
# parsed rather than exported; a domain without the key reads as empty.
function raycast_link::allowed_ids() {
  defaults read "${ARI_DOTFILES_RAYCAST_LINK_DEFAULTS_DOMAIN}" "${ARI_DOTFILES_RAYCAST_LINK_ALLOW_KEY}" 2>/dev/null \
    | awk '$0 ~ /= 1;[[:space:]]*$/ { key = $1; gsub(/"/, "", key); print key }'
  return 0
}

# Input: an entry, the allowed ids (newline-joined). Output: allowed | NOT-ALLOWED | no-allow-id.
function raycast_link::entry_allow_state() {
  local entry="${1}" allowed="${2}" id
  id="$(print -r -- "${entry}" | jq -r '.allowId // empty')"
  if [[ -z "${id}" ]]; then
    print -r -- "no-allow-id"
  elif [[ $'\n'"${allowed}"$'\n' == *$'\n'"${id}"$'\n'* ]]; then
    print -r -- "allowed"
  else
    print -r -- "NOT-ALLOWED"
  fi
}

# Write the allowIds Raycast does not yet allow, and only those, so the deeplink confirmation
# never shows for a bound command. Idempotent; exit 0 when nothing is missing. With dry_run=1
# nothing is written and the would-be additions are reported.
function raycast_link::allow() {
  local dry_run="${1:-0}" entry alias_ id allowed state
  local -a added already no_id would_ids
  if ! command -v defaults >/dev/null 2>&1; then
    log::err "defaults not found; cannot sync Raycast's allow-list | domain='${ARI_DOTFILES_RAYCAST_LINK_DEFAULTS_DOMAIN}'"
    return 1
  fi
  allowed="$(raycast_link::allowed_ids)"
  for entry in "${(@f)$(raycast_link::entries)}"; do
    alias_="$(raycast_link::slug "${entry}")"
    state="$(raycast_link::entry_allow_state "${entry}" "${allowed}")"
    case "${state}" in
      allowed)     already+=("${alias_}") ;;
      no-allow-id) no_id+=("${alias_}") ;;
      NOT-ALLOWED)
        id="$(print -r -- "${entry}" | jq -r .allowId)"
        would_ids+=("${id}")
        if (( dry_run )); then
          added+=("${alias_}")
        elif defaults write "${ARI_DOTFILES_RAYCAST_LINK_DEFAULTS_DOMAIN}" "${ARI_DOTFILES_RAYCAST_LINK_ALLOW_KEY}" -dict-add "${id}" -bool true; then
          added+=("${alias_}")
        else
          log::err "defaults write failed | domain='${ARI_DOTFILES_RAYCAST_LINK_DEFAULTS_DOMAIN}' id='${id}' alias='${alias_}'"
          return 1
        fi ;;
    esac
  done
  if (( dry_run )); then
    log::info "Raycast allow-list dry run | would_add='${#added}' already='${#already}' no_allow_id='${#no_id}' domain='${ARI_DOTFILES_RAYCAST_LINK_DEFAULTS_DOMAIN}' would_add_aliases='${(j:, :)added}'"
    cat <<EOF
dry_run=1
would_add=${#added}
already=${#already}
no_allow_id=${#no_id}
would_add_aliases=${(j:,:)added}
would_add_ids=${(j:,:)would_ids}
no_allow_id_aliases=${(j:,:)no_id}
EOF
    return 0
  fi
  log::info "Raycast allow-list synced | added='${#added}' already='${#already}' no_allow_id='${#no_id}' domain='${ARI_DOTFILES_RAYCAST_LINK_DEFAULTS_DOMAIN}' added_aliases='${(j:, :)added}' no_allow_id_aliases='${(j:, :)no_id}'"
  cat <<EOF
added=${#added}
already=${#already}
no_allow_id=${#no_id}
added_aliases=${(j:,:)added}
no_allow_id_aliases=${(j:,:)no_id}
EOF
}

# --- modes ---

# Input: slug or path, plain flag (0/1). Output: the widget line; the key shown is the first chord.
function raycast_link::widget() {
  local selector="${1}" plain="${2}" entry title path_ first binding suffix=""
  entry="$(raycast_link::entry "${selector}")" || return 1
  title="$(print -r -- "${entry}" | jq -r .title)"
  path_="$(print -r -- "${entry}" | jq -r .path)"
  first="$(print -r -- "${entry}" | jq -r '.chords[0]')"
  binding="$(raycast_link::render_chord "${first}")" || return 1
  [[ "$(raycast_link::entry_status "${entry}")" == MISSING ]] && suffix=" (not compiled yet)"
  local text="Raycast: ${title} | key: '${binding}'${suffix}"
  if (( plain )); then
    print -r -- "<${text}> raycast://${path_}"
  else
    print -r -- "<[${text}](raycast://${path_})>"
  fi
}

# Output: one line per binding: slug, every chord rendered, title, deeplink.
function raycast_link::list() {
  local entry
  for entry in "${(@f)$(raycast_link::entries)}"; do
    print -r -- "$(raycast_link::slug "${entry}")  $(raycast_link::render_entry_chords "${entry}")  $(print -r -- "${entry}" | jq -r .title)  raycast://$(print -r -- "${entry}" | jq -r .path)"
  done
}

# Output: per slug, OK / MISSING (direct chords against the compiled karabiner.json) or layer
# (only layer chords, not verified), the chords, then the Raycast allow state. Exit 1 only on a
# MISSING; the allow state is advisory, --allow fixes it.
function raycast_link::check() {
  local entry alias_ status_word allowed rc=0
  allowed="$(raycast_link::allowed_ids)"
  for entry in "${(@f)$(raycast_link::entries)}"; do
    alias_="$(raycast_link::slug "${entry}")"
    status_word="$(raycast_link::entry_status "${entry}")"
    [[ "${status_word}" == MISSING ]] && rc=1
    print -r -- "${status_word} ${alias_} $(raycast_link::render_entry_chords "${entry}") $(raycast_link::entry_allow_state "${entry}" "${allowed}")"
  done
  (( rc )) && log::err "Bindings not compiled | karabiner_json='${ARI_DOTFILES_RAYCAST_LINK_KARABINER_JSON}' fix='run bake'"
  return "${rc}"
}

function raycast_link::help() {
  cat >&2 <<EOF
dotfiles raycast link — a Raycast action as a link with its Karabiner binding

  dotfiles raycast link <slug|path>          markdown: <[Raycast: Title | key: '✦4'](raycast://path)>
  dotfiles raycast link <slug|path> --plain  <Raycast: Title | key: '✦4'> raycast://path
                                  slug = the deeplink path's last segment: clipboard-history, left-half, my-schedule
  dotfiles raycast link list             one line per binding: slug, every chord (✦K D = Hyper+K then D), title, deeplink
  dotfiles raycast link check            OK/MISSING per binding (direct chords, against the compiled karabiner.json;
                                  layer chords show as 'layer' and are not verified), plus allowed/NOT-ALLOWED/no-allow-id
  dotfiles raycast link allow [--dry-run]   write the missing allowIds to Raycast's plist so no deeplink asks "Always allow"

Bindings come from karabiner.ts's tables: ${ARI_DOTFILES_RAYCAST_LINK_KARABINER_TS}/src/modes/*.ts and
src/raycast_shortcuts.ts, read through its generator. To change one, edit the table and run bake
(which also regenerates src/raycast_bindings.json, an artifact for reading, and runs --allow).
EOF
}

function raycast_link() {
  local mode="" selector="" plain=0 dry_run=0
  while (( $# > 0 )); do case "${1}" in
    -h|--help)  raycast_link::help; return 0 ;;
    --plain)    plain=1; shift ;;
    --dry-run)  dry_run=1; shift ;;
    --list)     mode=list; shift ;;
    --check)    mode=check; shift ;;
    --allow)    mode=allow; shift ;;
    -*)         log::err "Unknown flag | flag='${1}' hint='to change a binding, edit karabiner.ts/src/modes/*.ts or raycast_shortcuts.ts and run bake'"; raycast_link::help; return 1 ;;
    *)          [[ -z "${mode}" ]] && mode=widget; selector="${1}"; shift ;;
  esac; done
  [[ -n "${mode}" ]] || { raycast_link::help; return 1; }
  raycast_link::load_bindings || return 1
  case "${mode}" in
    widget) raycast_link::widget "${selector}" "${plain}" ;;
    list)   raycast_link::list ;;
    check)  raycast_link::check ;;
    allow)  raycast_link::allow "${dry_run}" ;;
  esac
}
