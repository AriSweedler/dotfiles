# cmd/brew/decree.zsh — `dotfiles brew triage | decree | undecree`. Loaded by cmd/brew.zsh after
# lib/common.zsh, lib/brew.zsh and lib/dotfiles.zsh; defines functions and constants only.
#
# Both tiers' Brewfile and Brewfile.ignore are edited only inside a trailing "decree block" that
# starts at DECREE_MARKER. Hand-written sections are never rewritten, and undecree can tell the
# tool's own lines from Ari's. brew::declared stays the authority for what a Brewfile declares;
# the line scanning here only locates text to report or edit.
#
# Entry points (each takes the CLI args after `dotfiles brew <sub>`, parses them with
# `verb::parse brew` against cmd/brew.zsh's declaration, and returns the exit code):
#   decree::triage   [--json | --interactive | --edit [FILE]] [--dry-run] [--no-push]
#   decree::decree   ITEM... (--global|--local|--ignore-global|--ignore-local) --reason TEXT [--dry-run] [--no-push]
#   decree::undecree ITEM... [--dry-run] [--no-push]
# ITEM = [formula:|cask:|tap:|vscode:]name; the kind may be omitted when exactly one kind matches.
#
# Reads: ARI_DOTFILES_STATE_DIR, ARI_DOTFILES_NOW, RUN_DIR, RUN_ID, LAST_RESULT_FILE, HOME, ARI_DOTFILES_DRY_RUN,
# ARI_DOTFILES_NO_PUSH; brew and the tier file paths come from brew::bin, brew::global_brewfile and friends.

(( ${+DECREE_MARKER} )) || typeset -gr DECREE_MARKER="# ── decreed via 'new-machine brew decree'; move into a section when tidying ──"
(( ${+DECREE_KEYWORD} )) || typeset -grA DECREE_KEYWORD=([formula]=brew [cask]=cask [tap]=tap [vscode]=vscode)
(( ${+DECREE_KIND_OF_KEYWORD} )) || typeset -grA DECREE_KIND_OF_KEYWORD=([brew]=formula [cask]=cask [tap]=tap [vscode]=vscode)
(( ${+DECREE_KIND_ORDER} )) || typeset -grA DECREE_KIND_ORDER=([tap]=0 [formula]=1 [cask]=2 [vscode]=3)
(( ${+DECREE_BREWFILE_LINE_RE} )) || typeset -gr DECREE_BREWFILE_LINE_RE="^[[:space:]]*(brew|cask|tap|vscode)[[:space:]]+[\"']([^\"']+)[\"']"
(( ${+DECREE_IGNORE_LINE_RE} )) || typeset -gr DECREE_IGNORE_LINE_RE='^[[:space:]]*(formula|cask|tap|vscode|include-declared)[[:space:]]+([^[:space:]#]+)'
(( ${+DECREE_LOCAL_BREWFILE_HEADER} )) || typeset -gra DECREE_LOCAL_BREWFILE_HEADER=(
  "# Packages for THIS machine only (local tier, git ldf). Applied together with the shared"
  "# ~/.config/new-machine/Brewfile by \`${CLI_NAME} setup\`. Add with \`${CLI_NAME} brew decree <name> --local --reason why\`;"
  "# move a line into the shared file by hand when every machine should have it. Every entry says"
  "# why it is here: a trailing comment, or a heading comment opening its paragraph."
)
(( ${+DECREE_IGNORE_HEADER} )) || typeset -gra DECREE_IGNORE_HEADER=(
  "# Installed here on purpose, but dotfiles do not own it. One entry per line:"
  "#   <formula|cask|tap|vscode> <canonical name>   # reason"
  "#   include-declared <abs path to a Brewfile>     # everything it declares counts as ignored"
)

# canon($k; $n) for jq programs run with `--slurpfile m "${DECREE_ALIAS_MAP}"`: the alias map's
# single value, else the name itself; taps and include paths are identity, extension ids lowercase.
(( ${+DECREE_JQ_CANON} )) || typeset -gr DECREE_JQ_CANON='
  def canon($k; $n):
    if $k == "tap" or $k == "include-declared" then $n
    elif $k == "vscode" then ($n | ascii_downcase)
    else ((($m[0][$k] // {})[$n]) // []) as $v | if ($v | length) == 1 then $v[0] else $n end end;'

# ── environment ──────────────────────────────────────────────────────────────────────────────

# The tier files brew.zsh resolves (common.zsh's GLOBAL_BREWFILE and friends).
decree::tier_file() {  # <global|local> <Brewfile|Brewfile.ignore>
  case "${1}/${2}" in
    global/Brewfile) brew::global_brewfile ;;
    global/Brewfile.ignore) brew::global_ignore ;;
    local/Brewfile) brew::local_brewfile ;;
    local/Brewfile.ignore) brew::local_ignore ;;
    *) print -u2 "decree::tier_file: bad arguments '${1}' '${2}'"; return 64 ;;
  esac
}

decree::is_third_party_tap() {
  [[ -n "${1}" && "${1}" != null && "${1}" != homebrew/* ]]
}

# RUN_DIR is common.zsh's (the runner's own when a step already made one); decree only creates it.
decree::run_dir() {
  mkdir -p "${RUN_DIR}"
}

# Fresh filesystem truth for this invocation under RUN_DIR: inventory, brew's JSON, the alias
# map and (unless --no-classify) drift.json. Sets DECREE_INVENTORY/DECREE_INFO/DECREE_ALIAS_MAP/
# DECREE_DRIFT. Returns 2 when brew is busy or a producer fails.
decree::snapshot() {  # [--no-classify]
  decree::run_dir || return 2
  if brew::is_busy; then
    log::err "brew is busy; retry when it finishes | pids='$(brew::busy_pids)'"
    return 2
  fi
  typeset -g DECREE_INVENTORY="${RUN_DIR}/inventory.json" DECREE_INFO="${RUN_DIR}/info_installed.json"
  typeset -g DECREE_ALIAS_MAP="${RUN_DIR}/alias_map.json" DECREE_DRIFT="${RUN_DIR}/drift.json"
  # brew's JSON does not change between the snapshot and the re-classification of one invocation.
  if [[ -s "${DECREE_INFO}" ]]; then
    brew::inventory > "${DECREE_INVENTORY}" || { log::err "brew::inventory failed"; return 2; }
  else
    local snapshot_rc=0
    brew::snapshot "${DECREE_INVENTORY}" "${DECREE_INFO}" || snapshot_rc=$?
    if (( snapshot_rc == 2 )); then log::err "brew::inventory failed"; return 2; fi
    if (( snapshot_rc != 0 )); then log::err "brew info --json=v2 --installed failed"; return 2; fi
  fi
  brew::alias_map "${DECREE_INFO}" "${DECREE_INVENTORY}" > "${DECREE_ALIAS_MAP}" || { log::err "brew::alias_map failed"; return 2; }
  if [[ "${1:-}" == --no-classify ]]; then
    return 0
  fi
  local previous="${RUN_DIR}/previous_undeclared.json"
  brew::previous_undeclared > "${previous}"
  brew::classify "${DECREE_INVENTORY}" "${DECREE_INFO}" "$(brew::global_brewfile)" "$(brew::local_brewfile)" \
                 "$(brew::global_ignore)" "$(brew::local_ignore)" "${previous}" > "${DECREE_DRIFT}" \
    || { log::err "brew::classify failed"; return 2; }
  return 0
}

# ── brew bundle dump: the source of verbatim declaration lines ───────────────────────────────

# Loads the dump once per invocation into _decree_dump. The trust gate hides untrusted-tap kegs
# from the dump, so a missing line is expected and the caller synthesizes one.
decree::dump_load() {
  local brew out
  brew="$(brew::bin)" || brew=brew
  if ! out="$("${brew}" bundle dump --file=- --formula --cask --tap --vscode --no-describe 2>>"${RUN_DIR}/decree.log")"; then
    log::warn "brew bundle dump failed; declaration lines will be synthesized | log='${RUN_DIR}/decree.log'"
    out=""
  fi
  print -r -- "${out}" > "${RUN_DIR}/bundle_dump.out"
  typeset -ga _decree_dump=()
  [[ -n "${out}" ]] && _decree_dump=("${(@f)out}")
  return 0
}

# Prints the first dump line `<keyword> "<name>"…` for any of the names (case-insensitive).
decree::dump_line() {  # <brew|cask|tap|vscode> <name>...
  local keyword="${1}"; shift
  (( ${+_decree_dump} )) || return 1
  local line name
  for line in "${_decree_dump[@]}"; do
    [[ "${line}" =~ "${DECREE_BREWFILE_LINE_RE}" ]] || continue
    [[ "${match[1]}" == "${keyword}" ]] || continue
    for name in "$@"; do
      if [[ "${(L)match[2]}" == "${(L)name}" ]]; then
        print -r -- "${line}"
        return 0
      fi
    done
  done
  return 1
}

# A line in one's own Brewfile is an explicit trust decision, and an unattended
# `brew bundle install` must not stop on a trust prompt, so third-party taps are always trusted.
decree::tap_line() {  # <tap>
  local tap="${1}" line
  line="$(decree::dump_line tap "${tap}")" || line="tap \"${tap}\""
  if decree::is_third_party_tap "${tap}" && [[ "${line}" != *"trusted: true"* ]]; then
    line="${line}, trusted: true"
  fi
  print -r -- "${line}"
}

# The quoted name of a Brewfile line, or nothing.
decree::line_name() {  # <line>
  [[ "${1}" =~ "${DECREE_BREWFILE_LINE_RE}" ]] || return 1
  print -r -- "${match[2]}"
}

# ── ITEM parsing and resolution ──────────────────────────────────────────────────────────────

# Splits ITEM into _decree_kind ("" when omitted) and _decree_name. Returns 64 on a bad form.
decree::parse_item() {  # <item>
  local item="${1}"
  typeset -g _decree_kind="" _decree_name=""
  case "${item}" in
    formula:*|cask:*|tap:*|vscode:*) _decree_kind="${item%%:*}"; _decree_name="${item#*:}" ;;
    *:*) log::err "unknown item kind; use formula:|cask:|tap:|vscode: | item='${item}'"; return 64 ;;
    *) _decree_name="${item}" ;;
  esac
  if [[ -z "${_decree_name}" ]]; then
    log::err "empty item name | item='${item}'"
    return 64
  fi
  return 0
}

# Resolves one ITEM against the inventory through the alias map and prints it as JSON
# {kind, name, line_name, keg, tap, dump_names}: name is the canonical identity (formula
# full_name, cask token, tap, lowercase extension id), line_name what a declaration should say.
# Returns 1 when nothing installed matches, 64 when the kind or alias is ambiguous.
decree::resolve() {  # <kind or ""> <name>
  local kind="${1}" name="${2}" candidates
  candidates="$(jq -c -n --slurpfile inv "${DECREE_INVENTORY}" --slurpfile m "${DECREE_ALIAS_MAP}" \
                   --arg kind "${kind}" --arg name "${name}" '
    def canon($k; $n): ((($m[0][$k] // {})[$n]) // []) as $v
      | if ($v | length) > 1 then {ambiguous: $v} elif ($v | length) == 1 then {name: $v[0]} else {name: $n} end;
    def formula_candidates: canon("formula"; $name) as $c
      | if $c.ambiguous then [{kind: "formula", ambiguous: $c.ambiguous}]
        else [ ($inv[0].formulae // [])[] | select(.full_name == $c.name or .keg == $c.name)
               | {kind: "formula", name: .full_name, line_name: .full_name, keg: .keg, tap: .tap,
                  dump_names: [.full_name, .keg]} ] end;
    def cask_candidates: canon("cask"; $name) as $c
      | if $c.ambiguous then [{kind: "cask", ambiguous: $c.ambiguous}]
        else [ ($inv[0].casks // [])[] | select(.token == $c.name or .full_token == $c.name)
               | {kind: "cask", name: .token, line_name: .full_token, keg: null, tap: .tap,
                  dump_names: [.full_token, .token]} ] end;
    def tap_candidates:
        [ ($inv[0].taps // [])[] | select(.name == $name)
          | {kind: "tap", name: .name, line_name: .name, keg: null, tap: null, dump_names: [.name]} ];
    def vscode_candidates: ($name | ascii_downcase) as $n
      | [ ($inv[0].vscode // [])[] | select((.id | ascii_downcase) == $n)
          | {kind: "vscode", name: (.id | ascii_downcase), line_name: .id, keg: null, tap: null, dump_names: [.id]} ];
    (if $kind == "" then formula_candidates + cask_candidates + tap_candidates + vscode_candidates
     elif $kind == "formula" then formula_candidates
     elif $kind == "cask" then cask_candidates
     elif $kind == "tap" then tap_candidates
     else vscode_candidates end)
    | unique_by(.kind + "/" + (.name // "?"))')" || return 2
  local ambiguous
  ambiguous="$(jq -r '[.[] | select(has("ambiguous")) | .kind + ": " + (.ambiguous | join(", "))] | join("; ")' <<< "${candidates}")"
  if [[ -n "${ambiguous}" ]]; then
    log::err "ambiguous alias; use the full name (formula:<tap>/<name>) | item='${name}' candidates='${ambiguous}'"
    return 64
  fi
  local count
  count="$(jq -r 'length' <<< "${candidates}")"
  if (( count == 0 )); then
    return 1
  fi
  if (( count > 1 )); then
    log::err "ambiguous kind; prefix the item | item='${name}' candidates='$(jq -r 'map(.kind + ":" + .name) | join(" ")' <<< "${candidates}")'"
    return 64
  fi
  jq -c '.[0]' <<< "${candidates}"
}

decree::field() {  # <json> <field>
  jq -r --arg f "${2}" '.[$f] // ""' <<< "${1}"
}

# Canonical name of <name> as a <kind>: alias map for formula/cask, identity for taps,
# lowercase for extensions.
decree::canon() {  # <kind> <name>
  jq -r -n --slurpfile m "${DECREE_ALIAS_MAP}" --arg k "${1}" --arg n "${2}" "${DECREE_JQ_CANON}"'canon($k; $n)'
}

# ── declared and ignored sets ────────────────────────────────────────────────────────────────

# {formula: [{raw, canon}], cask: […], tap: […], vscode: […]} for one Brewfile via brew::declared;
# empty sets when the file is absent.
decree::declared_canon() {  # <brewfile>
  local file="${1}" declared
  if [[ ! -f "${file}" ]]; then
    print -r -- '{"formula":[],"cask":[],"tap":[],"vscode":[]}'
    return 0
  fi
  declared="$(brew::declared "${file}")" || return 2
  jq -c -n --slurpfile m "${DECREE_ALIAS_MAP}" --argjson d "${declared}" "${DECREE_JQ_CANON}"'
    { formula: [ ($d.formula // [])[] | {raw: ., canon: canon("formula"; .)} ],
      cask:    [ ($d.cask // [])[]    | {raw: ., canon: canon("cask"; .)} ],
      tap:     [ ($d.tap // [])[]     | {raw: ., canon: canon("tap"; .)} ],
      vscode:  [ ($d.vscode // [])[]  | {raw: ., canon: canon("vscode"; .)} ] }'
}

# Rows "kind \t raw \t in_block \t line \t reason" → JSON [{kind, raw, canon, in_block, line, reason}].
decree::_rows_json() {
  if (( $# == 0 )); then
    print -r -- '[]'
    return 0
  fi
  print -rl -- "$@" | jq -R -s -c --slurpfile m "${DECREE_ALIAS_MAP}" "${DECREE_JQ_CANON}"'
    [ split("\n")[] | select(length > 0) | split("\t")
      | {kind: .[0], raw: .[1], in_block: (.[2] == "true"), line: .[3], reason: (.[4] // "")}
      | .canon = canon(.kind; .raw) ]'
}

# Line-level view of a Brewfile: [{kind, raw, canon, in_block, line}].
decree::brewfile_entries() {  # <file>
  decree::block_read "${1}"
  local -a rows=()
  local line in_block
  for in_block in false true; do
    local -a lines=()
    if [[ "${in_block}" == false ]]; then lines=("${_decree_head[@]}"); else lines=("${_decree_block[@]}"); fi
    for line in "${lines[@]}"; do
      [[ "${line}" =~ "${DECREE_BREWFILE_LINE_RE}" ]] || continue
      rows+=("${DECREE_KIND_OF_KEYWORD[${match[1]}]}"$'\t'"${match[2]}"$'\t'"${in_block}"$'\t'"${line//$'\t'/ }")
    done
  done
  decree::_rows_json "${rows[@]}"
}

# Line-level view of a Brewfile.ignore: [{kind, raw, canon, in_block, line, reason}] where kind
# may be include-declared (raw is then the path).
decree::ignore_entries() {  # <file>
  setopt local_options extended_glob
  decree::block_read "${1}"
  local -a rows=()
  local line in_block reason
  for in_block in false true; do
    local -a lines=()
    if [[ "${in_block}" == false ]]; then lines=("${_decree_head[@]}"); else lines=("${_decree_block[@]}"); fi
    for line in "${lines[@]}"; do
      [[ "${line}" =~ "${DECREE_IGNORE_LINE_RE}" ]] || continue
      reason=""
      if [[ "${line}" == *'#'* ]]; then
        reason="${line#*\#}"
        reason="${reason##[[:space:]]#}"
        reason="${reason%%[[:space:]]#}"
      fi
      rows+=("${match[1]}"$'\t'"${match[2]}"$'\t'"${in_block}"$'\t'"${line//$'\t'/ }"$'\t'"${reason//$'\t'/ }")
    done
  done
  decree::_rows_json "${rows[@]}"
}

# ── the documentation rule (pure zsh; no brew call) ──────────────────────────────────────────

# REPLY = the text of <line>'s trailing Ruby comment, trimmed, leading #s dropped: what follows
# the first `#` outside a quoted string; empty when there is none. Sets REPLY, so no subshell.
decree::trailing_comment() {  # <line>
  setopt local_options extended_glob
  local line="${1}" q="" c rest=""
  local -i i
  if [[ "${line}" == *'#'* ]]; then
    for (( i = 1; i <= ${#line}; i++ )); do
      c="${line[i]}"
      if [[ -n "${q}" ]]; then
        if [[ "${c}" == '\' ]]; then (( i++ )); elif [[ "${c}" == "${q}" ]]; then q=""; fi
      elif [[ "${c}" == '"' || "${c}" == "'" ]]; then
        q="${c}"
      elif [[ "${c}" == '#' ]]; then
        rest="${line[i,-1]}"
        break
      fi
    done
  fi
  REPLY="${${rest##[#[:space:]]#}%%[[:space:]]#}"
}

# decree::undocumented <Brewfile|Brewfile.ignore> <file>: reply = one `<line number>\t<kind>:<name>`
# per entry that lacks its documentation (a reply, not output: the healthcheck step scans four
# files without a subshell each). A Brewfile entry is documented by a trailing `# why`, or by
# sitting in a paragraph (lines between blank lines) whose first line is a heading comment: a
# comment that is neither a commented-out entry (`# brew "x"`) nor the decree marker. Every decree
# re-sorts its block, so inside the decree block only a trailing comment counts. A Brewfile.ignore
# entry needs a non-empty `# reason`. A missing file has no gaps.
decree::undocumented() {
  setopt local_options extended_glob
  local kind="${1}" file="${2}" line body reason entry REPLY
  typeset -ga reply=()
  [[ -r "${file}" ]] || return 0
  zmodload zsh/mapfile
  local -a lines=("${(@f)mapfile[${file}]}")
  local -i n=0 headed=0 in_block=0 opens=1
  for line in "${lines[@]}"; do
    n+=1
    if [[ "${kind}" == Brewfile.ignore ]]; then
      [[ "${line}" =~ "${DECREE_IGNORE_LINE_RE}" ]] || continue
      reason="${line#*\#}"
      [[ "${line}" == *'#'* && -n "${reason//[#[:space:]]/}" ]] || reply+=("${n}"$'\t'"${match[1]}:${match[2]}")
      continue
    fi
    if [[ "${line}" == "${DECREE_MARKER}" ]]; then
      in_block=1 headed=0 opens=0
      continue
    fi
    body="${line##[[:space:]]#}"
    if [[ -z "${body}" ]]; then
      opens=1 headed=0
      continue
    fi
    if (( opens )); then
      opens=0 headed=0
      if (( ! in_block )) && [[ "${body}" == '#'* ]]; then
        body="${body##[#[:space:]]#}"
        [[ -n "${body}" && ! "${body}" =~ "${DECREE_BREWFILE_LINE_RE}" ]] && headed=1
      fi
    fi
    [[ "${line}" =~ "${DECREE_BREWFILE_LINE_RE}" ]] || continue
    (( headed )) && continue
    entry="${DECREE_KIND_OF_KEYWORD[${match[1]}]}:${match[2]}"
    decree::trailing_comment "${line}"
    [[ -n "${REPLY}" ]] || reply+=("${n}"$'\t'"${entry}")
  done
  return 0
}

# Taps declared by every readable `include-declared` Brewfile named in either tier's ignore file.
decree::include_declared_taps() {
  # Not `path`: that is zsh's array tied to PATH, and a local one empties it.
  local tier file include_path
  for tier in global local; do
    file="$(decree::tier_file "${tier}" Brewfile.ignore)"
    [[ -f "${file}" ]] || continue
    for include_path in ${(f)"$(decree::ignore_entries "${file}" | jq -r '.[] | select(.kind == "include-declared") | .raw')"}; do
      [[ -r "${include_path}" ]] || continue
      brew::declared "${include_path}" | jq -r '(.tap // [])[]'
    done
  done
  return 0
}

# ── decree block editing (pure zsh) ──────────────────────────────────────────────────────────

# Reads <file> into _decree_head (up to the marker) and _decree_block (after it); a file without
# the marker is all head, a missing file is empty.
decree::block_read() {  # <file>
  local file="${1}"
  typeset -ga _decree_head=() _decree_block=()
  typeset -g _decree_has_marker=0
  [[ -f "${file}" ]] || return 0
  local -a lines
  lines=("${(@f)$(<"${file}")}")
  # $(<file) leaves an empty file as one empty element.
  if (( ${#lines} == 1 )) && [[ -z "${lines[1]}" ]]; then lines=(); fi
  local line
  for line in "${lines[@]}"; do
    if (( _decree_has_marker )); then
      _decree_block+=("${line}")
    elif [[ "${line}" == "${DECREE_MARKER}" ]]; then
      _decree_has_marker=1
    else
      _decree_head+=("${line}")
    fi
  done
  return 0
}

decree::block_remove_line() {  # <exact line>
  local -a kept=()
  local line
  for line in "${_decree_block[@]}"; do
    [[ "${line}" == "${1}" ]] || kept+=("${line}")
  done
  _decree_block=("${kept[@]}")
}

# Only decree's ignore removal reaches into the hand-written head (§3.4 step 2: a declaration
# supersedes an ignore wherever it sits); undecree never does.
decree::head_remove_line() {  # <exact line>
  local -a kept=()
  local line
  for line in "${_decree_head[@]}"; do
    [[ "${line}" == "${1}" ]] || kept+=("${line}")
  done
  _decree_head=("${kept[@]}")
}

# The newline-joined plan bucket <bucket> as the caller's array <out>. Buckets live in the
# caller's `plan` associative array, one per tier; lines never contain newlines.
decree::plan_lines() {  # <out array name> <bucket>
  local joined="${plan[${2}]-}"
  local -a lines=("${(@f)joined}")
  set -A "${1}" "${(@)lines:#}"
}

# "<kind order>\t<name>\t<line>": taps first, then brew, cask, vscode, then ignore-file kinds in
# the same order, include-declared and unparseable lines last.
decree::sort_key() {  # <line>
  local line="${1}" name order=9
  if [[ "${line}" =~ "${DECREE_BREWFILE_LINE_RE}" ]]; then
    name="${match[2]}"
    order="${DECREE_KIND_ORDER[${DECREE_KIND_OF_KEYWORD[${match[1]}]}]}"
  elif [[ "${line}" =~ "${DECREE_IGNORE_LINE_RE}" ]]; then
    name="${match[2]}"
    order="${DECREE_KIND_ORDER[${match[1]}]:-8}"
  else
    name="${line}"
  fi
  print -r -- "${order}"$'\t'"${name//$'\t'/ }"$'\t'"${line}"
}

# The block sorted by kind then name, blank lines dropped, exact duplicates collapsed.
decree::block_sorted() {
  local -a keys=()
  local line
  for line in "${_decree_block[@]}"; do
    [[ -z "${line//[[:space:]]/}" ]] && continue
    keys+=("$(decree::sort_key "${line}")")
  done
  (( ${#keys} )) || return 0
  local -a sorted=("${(@ou)keys}")
  for line in "${sorted[@]}"; do
    print -r -- "${line#*$'\t'*$'\t'}"
  done
}

# Writes head + marker + sorted block back to <file> through a temp file. Header lines are used
# only when the file is being created. Under --dry-run prints the target and writes nothing.
decree::block_write() {  # <file> [header line]...
  local file="${1}"; shift
  local -a out=("${_decree_head[@]}")
  if (( ! _decree_has_marker )); then
    if (( ${#out} == 0 )) && (( $# > 0 )); then out+=("$@"); fi
    if (( ${#out} > 0 )) && [[ -n "${out[-1]}" ]]; then out+=(""); fi
  fi
  out+=("${DECREE_MARKER}")
  local sorted
  sorted="$(decree::block_sorted)"
  [[ -n "${sorted}" ]] && out+=("${(@f)sorted}")
  if is_dry_run; then
    print -r -- "would write: ${file}"
    return 0
  fi
  mkdir -p "${file:h}"
  local tmp="${file}.tmp.$$"
  print -rl -- "${out[@]}" > "${tmp}"
  mv -f "${tmp}" "${file}"
  log::info "wrote | file='${file}'"
}

# Taps referenced by the brew/cask lines in _decree_head + _decree_block: a tap-qualified name
# carries its tap; a bare name is looked up in the inventory.
decree::taps_in_use() {
  local -a names=()
  local line
  for line in "${_decree_head[@]}" "${_decree_block[@]}"; do
    [[ "${line}" =~ "${DECREE_BREWFILE_LINE_RE}" ]] || continue
    [[ "${match[1]}" == brew || "${match[1]}" == cask ]] || continue
    names+=("${match[1]}/${match[2]}")
  done
  (( ${#names} )) || return 0
  print -rl -- "${names[@]}" | jq -R -s -r --slurpfile inv "${DECREE_INVENTORY}" --slurpfile m "${DECREE_ALIAS_MAP}" "${DECREE_JQ_CANON}"'
    [ split("\n")[] | select(length > 0) | index("/") as $i | {kw: .[:$i], name: .[$i+1:]} ]
    | map(
        if (.name | split("/") | length) >= 3 then (.name | split("/") | .[0] + "/" + .[1])
        elif .kw == "brew" then (canon("formula"; .name) as $c
          | [ ($inv[0].formulae // [])[] | select(.full_name == $c or .keg == $c) | .tap ] | .[0])
        else (canon("cask"; .name) as $c
          | [ ($inv[0].casks // [])[] | select(.token == $c or .full_token == $c) | .tap ] | .[0])
        end)
    | map(select(. != null)) | unique | .[]'
}

# Block lines declaring <tap>.
decree::block_tap_lines() {  # <tap>
  local line
  for line in "${_decree_block[@]}"; do
    [[ "${line}" =~ "${DECREE_BREWFILE_LINE_RE}" ]] || continue
    [[ "${match[1]}" == tap && "${match[2]}" == "${1}" ]] && print -r -- "${line}"
  done
  return 0
}

# ── triage ───────────────────────────────────────────────────────────────────────────────────

decree::triage() {
  local -A opts; local -a args
  verb::parse brew "$@"
  brew::only triage --json --interactive --edit --dry-run --no-push
  local -i json=${+opts[--json]} interactive=${+opts[--interactive]} edit=${+opts[--edit]}
  local -a pass=()
  (( ${+opts[--dry-run]} )) && pass+=(--dry-run)
  (( ${+opts[--no-push]} )) && pass+=(--no-push)
  (( ${#args} <= edit )) || usage_error "brew triage takes one FILE, after --edit, and nothing else | args='${args[*]}'"
  (( ! (json && interactive) )) || usage_error "--json and --interactive do not mix | json='${CLI_NAME} brew triage --json' interactive='${CLI_NAME} brew triage --interactive'"
  (( ! (edit && (json || interactive)) )) || usage_error "--edit does not mix with --json or --interactive | edit='${CLI_NAME} brew triage --edit'"
  if (( ${#pass} && ! interactive && ! edit )); then
    usage_error "--dry-run and --no-push go with --interactive or --edit; plain triage writes nothing | flags='${pass[*]}'"
  fi
  if (( edit )); then
    decree::triage_edit "${pass[@]}" -- "${args[@]}"
    return
  fi
  if (( interactive )); then
    decree::triage_interactive "${pass[@]}"
    return
  fi
  decree::snapshot || return $?
  local problems
  problems="$(jq -r '(.undeclared | length) + (.orphan_keg | length) + (.duplicate | length) + (.declared_orphan | length)' "${DECREE_DRIFT}")"
  if (( json )); then
    cat "${DECREE_DRIFT}"
  else
    decree::triage_render "${DECREE_DRIFT}"
  fi
  (( problems == 0 )) && return 0
  return 1
}

# The manual recipe for an orphaned keg; the tool never uninstalls or reinstalls.
decree::orphan_recipe() {  # <full name> <hint>
  local name="${1}" hint="${2}" keg="${1:t}" tap="${1:h}"
  if [[ "${hint}" == *"ships cask"* && "${name}" == */*/* ]]; then
    print -r -- "  brew uninstall ${keg} && brew tap ${tap} && brew install --cask ${name}"
    print -r -- "  then: ${CLI_NAME} brew decree cask:${name} --local --reason \"…\""
  elif [[ "${hint}" == "tap not tapped" && "${name}" == */*/* ]]; then
    print -r -- "  brew tap ${tap}   # ${hint}; then re-run ${CLI_NAME} brew triage"
  else
    print -r -- "  brew uninstall ${keg}   # ${hint}"
  fi
}

decree::triage_render() {  # <drift.json>
  decree::triage_render_undeclared "${1}"
  decree::triage_render_rest "${1}"
}

# The undeclared section: one row per item and the three decree commands that settle it.
decree::triage_render_undeclared() {  # <drift.json>
  local drift="${1}" since="" kind name tap new tag count=0
  [[ -f "${LAST_RESULT_FILE}" ]] && since="$(jq -r '(.ts // "") | .[0:10]' "${LAST_RESULT_FILE}")"

  print -r -- "undeclared (installed here, declared in no Brewfile)"
  for kind in formula cask tap vscode; do
    while IFS=$'\t' read -r name tap new; do
      count=$(( count + 1 ))
      tag=""
      if [[ "${new}" == true ]]; then
        tag="new"
        [[ -n "${since}" ]] && tag="new since ${since}"
      fi
      printf '%-8s %-34s (%s)   %s\n' "${kind}" "${name}" "${tap}" "${tag}"
      print -r -- "  every machine : ${CLI_NAME} brew decree ${kind}:${name} --global --reason \"…\""
      print -r -- "  this machine  : ${CLI_NAME} brew decree ${kind}:${name} --local --reason \"…\""
      print -r -- "  never declare : ${CLI_NAME} brew decree ${kind}:${name} --ignore-local --reason \"…\""
    done < <(jq -r --arg k "${kind}" '.undeclared[] | select(.kind == $k)
               | [.name, (.tap // "-"), ((.new // false) | tostring)] | @tsv' "${drift}")
  done
  (( count == 0 )) && print -r -- "  (none)"
  return 0
}

# Every section after undeclared: orphaned kegs with their recipes, duplicates, declared
# orphans, the ignore list and classifier notes. Nothing here is prompted for.
decree::triage_render_rest() {  # <drift.json>
  local drift="${1}" kind name hint
  if jq -e '.orphan_keg | length > 0' "${drift}" >/dev/null; then
    print -r -- ""
    print -r -- "orphaned kegs (needs a human; the tool never uninstalls or reinstalls)"
    while IFS=$'\t' read -r kind name hint; do
      print -r -- "${kind} ${name}: ${hint}"
      decree::orphan_recipe "${name}" "${hint}"
    done < <(jq -r '.orphan_keg[] | [.kind, .name, (.hint // "orphaned")] | @tsv' "${drift}")
  fi

  if jq -e '.duplicate | length > 0' "${drift}" >/dev/null; then
    print -r -- ""
    print -r -- "duplicates (declared twice; brew may print 'needs to be unlinked')"
    jq -r '.duplicate[] | "  \(.kind) \(.name): \(.problem) (tiers: \((.tiers // []) | join(", ")))"' "${drift}"
  fi

  if jq -e '.declared_orphan | length > 0' "${drift}" >/dev/null; then
    print -r -- ""
    print -r -- "declared orphans (a fresh machine cannot install these)"
    jq -r '.declared_orphan[] | "  \(.kind) \(.raw // .name) (\(.tier // "?"))"' "${drift}"
  fi

  print -r -- ""
  print -r -- "ignored (installed on purpose; dotfiles do not own it)"
  if jq -e '.ignored | length > 0' "${drift}" >/dev/null; then
    jq -r '.ignored[] | "  \(.kind) \(.name) (\(.tier // "?")) — \(if (.via // "line") == "line" then (.reason // "no reason given") else .via end)"' "${drift}"
  else
    print -r -- "  (none)"
  fi

  local notes
  notes="$(jq -r '
    [ (.unresolvable_ignore // [])[] | "  unresolvable ignore: \(.kind) \(.name) (\(.tier // "?")) matches nothing installed" ]
    + [ (.include_declared_missing // [])[] | "  include-declared missing: \(.path) (\(.tier // "?")); its items are back in undeclared" ]
    + [ (.untrusted_taps // [])[] | "  declared tap \(.) lacks `trusted: true`" ]
    + [ (.ambiguous_alias // [])[] | "  ambiguous alias: \(.kind) \(.name) → \((.candidates // []) | join(", "))" ]
    + (if .inventory_note then ["  \(.inventory_note)"] else [] end)
    + (if .vscode_skipped then ["  VS Code extensions not inventoried (code not found)"] else [] end)
    | .[]' "${drift}")"
  if [[ -n "${notes}" ]]; then
    print -r -- ""
    print -r -- "notes"
    print -r -- "${notes}"
  fi
}

# ── triage --interactive ─────────────────────────────────────────────────────────────────────

(( ${+DECREE_TRIAGE_ACTIONS} )) || typeset -gra DECREE_TRIAGE_ACTIONS=(global local ignore-global ignore-local)
(( ${+DECREE_TRIAGE_LABEL} )) || typeset -grA DECREE_TRIAGE_LABEL=(
  [global]="shared Brewfile" [local]="local Brewfile"
  [ignore-global]="ignore (shared)" [ignore-local]="ignore (local)" [skip]="skip"
)
(( ${+DECREE_TRIAGE_WHERE} )) || typeset -grA DECREE_TRIAGE_WHERE=([global]="every machine" [local]="this machine")

# Choices in, decree argument lists out. A CHOICE is "<action>\t<kind:name>\t<reason>", action one
# of global, local, ignore-global, ignore-local, skip; every action but skip needs its reason.
# Prints one line per group, its words quoted for ${(Q)${(z)line}}: the items in choice order, the
# tier flag, --reason, then the pass-through flags. Groups come in tier-flag order, split by
# reason, since one decree takes one --reason. Skips are dropped. Pure.
decree::triage_plan() {  # [--dry-run] [--no-push] [--] CHOICE...
  local -a pass=()
  while (( $# )) && [[ "${1}" == --?* ]]; do pass+=("${1}"); shift; done
  [[ "${1:-}" != -- ]] || shift
  local -a keys=() fields words
  local -A members=()
  local choice action item reason key
  for choice in "$@"; do
    fields=("${(@ps:\t:)choice}")
    action="${fields[1]:-}" item="${fields[2]:-}" reason="${fields[3]:-}"
    case "${action}" in
      skip) continue ;;
      global|local|ignore-global|ignore-local)
        if [[ -z "${reason}" ]]; then
          print -u2 -r -- "decree::triage_plan: a ${action} needs a reason | item='${item}'"
          return 64
        fi
        key="${action}"$'\t'"${reason}" ;;
      *) print -u2 -r -- "decree::triage_plan: bad action | choice='${choice}'"; return 64 ;;
    esac
    if [[ -z "${item}" ]]; then
      print -u2 -r -- "decree::triage_plan: no item | choice='${choice}'"
      return 64
    fi
    (( ${+members[${key}]} )) || keys+=("${key}")
    members[${key}]+="${item}"$'\n'
  done
  local a
  for a in "${DECREE_TRIAGE_ACTIONS[@]}"; do
    for key in "${keys[@]}"; do
      [[ "${key%%$'\t'*}" == "${a}" ]] || continue
      words=(${(f)members[${key}]} "--${a}" --reason "${key#*$'\t'}")
      words+=("${pass[@]}")
      print -r -- "${(j: :)${(@q-)words}}"
    done
  done
  return 0
}

# The flag a plan line carries (global, local, ignore-global, ignore-local).
decree::triage_plan_action() {  # <plan line>
  local -a words=("${(@Q)${(z)1}}")
  local a
  for a in "${DECREE_TRIAGE_ACTIONS[@]}"; do
    if (( ${words[(Ie)--${a}]} )); then print -r -- "${a}"; return 0; fi
  done
  return 1
}

# `triage --interactive`: the sections that need a human are listed as plain triage lists them,
# then one chooser per undeclared item, the plan grouped by action, one confirmation, and one
# decree::decree per group. Nothing is written before the confirmation.
decree::triage_interactive() {  # [--dry-run] [--no-push]
  local -a pass=("$@")
  if ! [[ -t 0 && -t 1 ]]; then
    usage_error "--interactive needs a terminal on stdin and stdout; run '${CLI_NAME} brew triage' and paste the decree commands it prints"
  fi
  if ! ui::is_fancy; then
    usage_error "--interactive needs gum, a terminal on stderr too, NO_COLOR unset and ARI_DOTFILES_UI not plain; run '${CLI_NAME} brew triage' instead | gum='${ARI_DOTFILES_GUM}'"
  fi
  decree::snapshot || return $?
  local drift="${DECREE_DRIFT}"
  local rest
  rest="$(decree::triage_render_rest "${drift}")"
  if [[ -n "${rest}" ]]; then
    print -r -- "${rest#$'\n'}"
    print -r -- ""
  fi

  local -a rows=()
  local kind
  for kind in formula cask tap vscode; do
    rows+=(${(f)"$(jq -r --arg k "${kind}" '.undeclared[] | select(.kind == $k)
                     | [.kind, .name, (.tap // "-"), ((.new // false) | tostring)] | @tsv' "${drift}")"})
  done
  if (( ${#rows} == 0 )); then
    print -r -- "undeclared: none; nothing to decree"
    return 0
  fi

  print -r -- "$(ui::paint bold "undeclared: ${#rows} item(s)") — pick where each belongs"
  local -a choices=() fields
  local row name tap new header pick action reason key ask
  local -i n=0
  for row in "${rows[@]}"; do
    n=$(( n + 1 ))
    fields=("${(@ps:\t:)row}")
    kind="${fields[1]}" name="${fields[2]}" tap="${fields[3]}" new="${fields[4]}"
    header="(${n}/${#rows}) ${kind}:${name}  (${tap})"
    [[ "${new}" != true ]] || header+="  new"
    pick=""
    if ! pick="$(ui::choose --header "${header}" "${DECREE_TRIAGE_LABEL[global]}" "${DECREE_TRIAGE_LABEL[local]}" \
                   "${DECREE_TRIAGE_LABEL[ignore-global]}" "${DECREE_TRIAGE_LABEL[ignore-local]}" "${DECREE_TRIAGE_LABEL[skip]}")" \
       || [[ -z "${pick}" ]]; then
      log::warn "cancelled; nothing decreed"
      return 130
    fi
    action=skip
    for key in "${(@k)DECREE_TRIAGE_LABEL}"; do
      [[ "${DECREE_TRIAGE_LABEL[${key}]}" != "${pick}" ]] || action="${key}"
    done
    reason=""
    if [[ "${action}" != skip ]]; then
      ask="why does ${DECREE_TRIAGE_WHERE[${action}]} need ${kind}:${name}? (one line, kept as the Brewfile comment)"
      [[ "${action}" != ignore-* ]] || ask="why does ${kind}:${name} stay undeclared? (one line, kept as the ignore comment)"
      while [[ -z "${reason}" ]]; do
        if ! reason="$(ui::input --header "${ask}" --placeholder reason)"; then
          log::warn "cancelled; nothing decreed"
          return 130
        fi
        reason="${${reason##[[:space:]]#}%%[[:space:]]#}"
      done
    fi
    print -r -- "  ${kind}:${name} → ${pick}${reason:+ — ${reason}}"
    choices+=("${action}"$'\t'"${kind}:${name}"$'\t'"${reason}")
  done

  decree::triage_apply "${pass[@]}" -- "${choices[@]}"
}

# The grouped plan for CHOICEs (as decree::triage_plan takes them), one confirmation, then one
# decree::decree per group. Shared by --interactive and --edit. DECREE_CONFIRM=0 skips the confirmation
# (--edit off a terminal: the saved file is the go-ahead).
decree::triage_apply() {  # [--dry-run] [--no-push] -- CHOICE...
  local -a pass=()
  while (( $# )) && [[ "${1}" != -- ]]; do pass+=("${1}"); shift; done
  [[ "${1:-}" != -- ]] || shift
  local -a choices=() deletes=() groups=()
  local c
  # A delete is no decree: it uninstalls, after the decrees, so it is kept apart from the plan.
  for c in "$@"; do
    if [[ "${c%%$'\t'*}" == delete ]]; then deletes+=("${${c#*$'\t'}%%$'\t'*}"); else choices+=("${c}"); fi
  done
  groups=(${(f)"$(decree::triage_plan "${pass[@]}" -- "${choices[@]}")"})
  print -r -- ""
  if (( ${#groups} == 0 && ${#deletes} == 0 )); then
    print -r -- "every item skipped; nothing to decree"
    return 0
  fi
  # One heading per group, then its items; short lines, so the box never wraps.
  local -a lines=() words
  local g a w head
  local -i width=$(( $(ui::cols) - 4 ))
  for a in "${DECREE_TRIAGE_ACTIONS[@]}"; do
    for g in "${groups[@]}"; do
      [[ "$(decree::triage_plan_action "${g}")" == "${a}" ]] || continue
      words=("${(@Q)${(z)g}}")
      head="${DECREE_TRIAGE_LABEL[${a}]} (--${a}"
      (( ${words[(Ie)--reason]} )) && head+=", reason: ${words[${words[(Ie)--reason]} + 1]}"
      lines+=("$(ui::paint bold "$(ui::clip "${width}" "${head})")")")
      for w in "${words[@]}"; do  # the items come before the first flag
        [[ "${w}" != --* ]] || break
        lines+=("$(ui::clip "${width}" "  ${w}")")
      done
    done
  done
  if (( ${#deletes} )); then
    lines+=("$(ui::paint bold "uninstall from this machine (delete)")")
    for w in "${deletes[@]}"; do lines+=("$(ui::clip "${width}" "  ${w}")"); done
  fi
  local title="plan: ${#groups} decree(s), one commit each" ask="Run ${#groups} decree(s)?"
  if (( ${#deletes} )); then
    title+=", then ${#deletes} uninstall(s)"
    ask="Run ${#groups} decree(s) and uninstall ${#deletes} item(s)?"
  fi
  (( ${pass[(Ie)--dry-run]} )) && title+=" (dry run)"
  ui::box --title "${title}" -- "${lines[@]}"

  local rc=0
  (( ${DECREE_CONFIRM:-1} == 0 )) || ui::confirm "${ask}" || rc=$?
  if (( rc != 0 )); then
    log::warn "declined; nothing decreed"
    (( rc == 130 )) && return 130
    return 1
  fi

  local -i i=0 failed=0
  local -a words
  for g in "${groups[@]}"; do
    i=$(( i + 1 ))
    words=("${(@Q)${(z)g}}")
    print -r -- ""
    print -r -- "$(ui::paint bold "[${i}/${#groups}] ${CLI_NAME} brew decree ${g}")"
    rc=0
    decree::decree "${words[@]}" || rc=$?
    if (( rc != 0 )); then
      failed=$(( failed + 1 ))
      log::err "decree failed; the other groups still ran | rc=${rc} args='${g}'"
    fi
  done
  if (( ${#deletes} )); then
    decree::triage_delete "${pass[@]}" -- "${deletes[@]}" || failed=$(( failed + 1 ))
  fi
  (( failed == 0 )) || return 1
  return 0
}

# Uninstalls each kind:name from this machine, extensions, casks and formulae before taps (a tap
# goes last: untapping one whose items are still installed fails). One command per item, named
# before it runs; a failure is reported and the rest still run. --dry-run prints the commands.
decree::triage_delete() {  # [--dry-run] [--no-push] -- KIND:NAME...
  local -a pass=() items=() cmd
  while (( $# )) && [[ "${1}" != -- ]]; do pass+=("${1}"); shift; done
  [[ "${1:-}" != -- ]] || shift
  local kind item brew
  for kind in vscode cask formula tap; do
    for item in "$@"; do [[ "${item%%:*}" == "${kind}" ]] && items+=("${item}"); done
  done
  local -i i=0 failed=0
  for item in "${items[@]}"; do
    i=$(( i + 1 ))
    case "${item%%:*}" in
      formula) brew="$(brew::bin)" || return 1; cmd=("${brew}" uninstall --formula "${item#*:}") ;;
      cask)    brew="$(brew::bin)" || return 1; cmd=("${brew}" uninstall --cask "${item#*:}") ;;
      tap)     brew="$(brew::bin)" || return 1; cmd=("${brew}" untap "${item#*:}") ;;
      vscode)
        if [[ -z "${ARI_DOTFILES_CODE:-}" ]]; then
          log::err "code not found; extension not uninstalled | item='${item}'"
          failed=$(( failed + 1 )); continue
        fi
        cmd=("${ARI_DOTFILES_CODE}" --uninstall-extension "${item#*:}") ;;
      *) log::err "cannot delete this kind | item='${item}'"; failed=$(( failed + 1 )); continue ;;
    esac
    print -r -- ""
    if (( ${pass[(Ie)--dry-run]} )); then
      print -r -- "would run: ${cmd[*]}"
      continue
    fi
    print -r -- "$(ui::paint bold "[delete ${i}/${#items}] ${cmd[1]:t} ${cmd[2,-1]}")"
    if ! "${cmd[@]}"; then
      failed=$(( failed + 1 ))
      log::err "uninstall failed; the other items still ran | item='${item}'"
    fi
  done
  (( failed == 0 )) || return 1
  return 0
}

# ── triage --edit ────────────────────────────────────────────────────────────────────────────

# The plan's actions; an add's or an ignore's note is its reason, and a delete uninstalls.
plan::define brew-triage --actions 'global add|local add|global ignore|local ignore|delete|skip' \
  --default skip --note 'global add|local add|global ignore|local ignore' --danger delete --item kind:name

# The plan file for <drift.json>: the header with the action key, one `skip kind:name` line per
# undeclared item (its tap and newness on a comment line above it), then every other section of
# plain triage as comments, for reference.
decree::triage_edit_file() {  # <drift.json>
  local drift="${1}" since="" kind name tap new info rest ref
  [[ -f "${LAST_RESULT_FILE}" ]] && since="$(jq -r '(.ts // "") | .[0:10]' "${LAST_RESULT_FILE}")"
  plan::header brew-triage \
    "${CLI_NAME} brew triage --edit: the undeclared items. Change each 'skip' to one of:" \
    "  global add      declare it in the shared Brewfile (every machine; git df, never pushed)" \
    "  local add       declare it in the local Brewfile (this machine; git ldf, pushed)" \
    "  global ignore   record it in the shared Brewfile.ignore" \
    "  local ignore    record it in the local Brewfile.ignore" \
    "  delete          uninstall it from this machine (brew uninstall, brew untap, or" \
    "                  code --uninstall-extension); declares nothing" \
    "  skip            leave it undeclared" \
    "An add's or an ignore's '# note' is its reason, kept as the line's comment in the file it" \
    "lands in. Save and quit to see the plan: one decree, one commit, per action and reason," \
    "then the uninstalls. Leaving every line 'skip' decrees nothing."
  for kind in formula cask tap vscode; do
    while IFS=$'\t' read -r name tap new; do
      info=""
      [[ "${tap}" == - ]] || info="${tap}"
      [[ "${new}" != true ]] || info+="${info:+, }new${since:+ since ${since}}"
      plan::comment "${kind} ${name}${info:+ (${info})}"
      plan::line skip "${kind}:${name}"
    done < <(jq -r --arg k "${kind}" '.undeclared[] | select(.kind == $k)
               | [.name, (.tap // "-"), ((.new // false) | tostring)] | @tsv' "${drift}")
  done
  rest="$(decree::triage_render_rest "${drift}")"
  [[ -n "${rest}" ]] || return 0
  print -r -- ""
  plan::comment "── for reference; not actionable here ──" "${(@f)${rest#$'\n'}}"
}

# plan::parse's item check: the item must be undeclared here (DECREE_UNDECLARED, from drift.json).
decree::triage_edit_item() {  # <kind:name> <action>
  (( ${DECREE_UNDECLARED[(Ie)${1}]} )) && return 0
  print -r -- "not an undeclared item here"
  return 1
}

# `triage --edit [FILE]`: the plan file (written under RUN_DIR, or FILE to resume one) through
# plan::edit, every line checked; a good plan runs as --interactive's does, confirmed once on a
# terminal (off one, the saved file is the go-ahead).
decree::triage_edit() {  # [--dry-run] [--no-push] [--] [FILE]
  local -a pass=()
  while (( $# )) && [[ "${1}" != -- ]]; do pass+=("${1}"); shift; done
  [[ "${1:-}" != -- ]] || shift
  local resume="${1:-}" file row action reason
  local -a reply choices=() fields
  local -i tty=0 rc=0
  [[ -t 0 && -t 1 ]] && tty=1
  decree::snapshot || return $?
  local drift="${DECREE_DRIFT}"
  if [[ -n "${resume}" ]]; then
    [[ -f "${resume}" ]] || { log::err "no such plan file | file='${resume}'"; return 64; }
    file="${resume}"
  else
    if jq -e '.undeclared | length == 0' "${drift}" >/dev/null; then
      print -r -- "undeclared: none; nothing to decree"
      return 0
    fi
    # Line 1 makes it a dotfilesplan buffer in Neovim; the extension does too, before it is read.
    file="${RUN_DIR}/triage-plan.brewtriage"
    decree::triage_edit_file "${drift}" > "${file}" || return 1
  fi
  typeset -ga DECREE_UNDECLARED=(${(f)"$(jq -r '.undeclared[] | "\(.kind):\(.name)"' "${drift}")"})
  # The resume line is logged here: plan::edit hands its --resume to edit::session as one word.
  plan::edit brew-triage "${file}" decree::triage_edit_item ${resume:+--changed} || rc=$?
  if (( rc == 2 )); then
    print -r -- "no change; nothing to decree"
    return 0
  fi
  if (( rc != 0 )); then
    log::err "nothing decreed; the plan is kept | fix='${CLI_NAME} brew triage --edit ${file}'"
    return 1
  fi
  # `global add` → global, `local ignore` → ignore-local: decree::triage_plan's actions.
  for row in "${reply[@]}"; do
    fields=("${(@ps:\t:)row}")
    action="${fields[1]% add}" reason="${fields[3]}"
    [[ "${action}" != *' ignore' ]] || action="ignore-${action% ignore}"
    [[ "${action}" != (skip|delete) ]] || reason=""
    choices+=("${action}"$'\t'"${fields[2]}"$'\t'"${reason}")
  done
  DECREE_CONFIRM=${tty} decree::triage_apply "${pass[@]}" -- "${choices[@]}"
}

# ── decree ───────────────────────────────────────────────────────────────────────────────────

# Message subject + body for one tier's commit.
decree::commit_message() {  # <verb> <tier> <suffix> <item line>... ; suffix is appended to the subject
  local verb="${1}" tier="${2}" suffix="${3}"; shift 3
  local -a items=("$@")
  if (( ${#items} == 1 )); then
    print -r -- "${CLI_NAME}: ${verb} ${items[1]} (${tier})${suffix}"
    return 0
  fi
  print -r -- "${CLI_NAME}: ${verb} ${#items} items (${tier})${suffix}"
  print -r -- ""
  local item
  for item in "${items[@]}"; do print -r -- "- ${item}"; done
}

decree::decree() {  # ITEM.. TIER --reason TEXT [--dry-run] [--no-push]
  local -A opts; local -a args
  verb::parse brew "$@"
  brew::only decree --global --local --ignore-global --ignore-local --reason --dry-run --no-push
  local -a items=("${args[@]}") tiers=(${(k)opts[(I)--global|--local|--ignore-global|--ignore-local]})
  (( ${#tiers} == 1 )) || usage_error "exactly one of --global, --local, --ignore-global, --ignore-local is required"
  (( ${#items} )) || usage_error "at least one ITEM is required"
  local reason="${opts[--reason]:-}" action=declare tier="${tiers[1]##*-}"
  [[ "${tiers[1]}" != --ignore-* ]] || action=ignore
  [[ -n "${reason//[[:space:]]/}" ]] || usage_error "--reason is required: it is the line's '# why' comment, and brew_drift fails an entry without one"
  (( ${+opts[--dry-run]} )) && export ARI_DOTFILES_DRY_RUN=1
  (( ${+opts[--no-push]} )) && export ARI_DOTFILES_NO_PUSH=1
  is_dry_run && log::warn "dry-run: no file is written, nothing is committed"

  decree::snapshot || return $?

  # Resolve everything first so a bad item refuses the whole invocation before any write.
  local -a resolved=()
  local item json rc
  for item in "${items[@]}"; do
    decree::parse_item "${item}" || return 64
    rc=0
    json="$(decree::resolve "${_decree_kind}" "${_decree_name}")" || rc=$?
    if (( rc == 1 )); then
      log::err "refused: not installed, nothing to copy | item='${item}'"
      return 1
    fi
    (( rc != 0 )) && return "${rc}"
    resolved+=("${json}")
  done

  local -A declared_by_tier
  local t
  for t in global local; do
    declared_by_tier[${t}]="$(decree::declared_canon "$(decree::tier_file "${t}" Brewfile)")" || return 2
  done
  local -A ignore_by_tier
  for t in global local; do
    ignore_by_tier[${t}]="$(decree::ignore_entries "$(decree::tier_file "${t}" Brewfile.ignore)")"
  done
  local -a declared_taps
  declared_taps=(${(f)"$(jq -r '.tap[].raw' <<< "${declared_by_tier[global]}")"}
                 ${(f)"$(jq -r '.tap[].raw' <<< "${declared_by_tier[local]}")"}
                 ${(f)"$(decree::include_declared_taps)"})

  local refused=0 kind name line line_name tap raw hit
  for json in "${resolved[@]}"; do
    kind="$(decree::field "${json}" kind)"; name="$(decree::field "${json}" name)"
    for t in global local; do
      raw="$(jq -r --arg k "${kind}" --arg c "${name}" '.[$k][] | select(.canon == $c) | .raw' <<< "${declared_by_tier[${t}]}" | head -n 1)"
      [[ -n "${raw}" ]] || continue
      hit="$(decree::brewfile_entries "$(decree::tier_file "${t}" Brewfile)" \
               | jq -r --arg k "${kind}" --arg r "${raw}" '[.[] | select(.kind == $k and .raw == $r)] | .[0].line // ""')"
      if [[ "${action}" == declare ]]; then
        log::err "refused: already declared in ${t} as ${hit:-${DECREE_KEYWORD[${kind}]} \"${raw}\"} | item='${kind}:${name}'"
      else
        log::err "refused: declared in ${t} as ${hit:-${DECREE_KEYWORD[${kind}]} \"${raw}\"}; declared wins over ignore | item='${kind}:${name}'"
      fi
      refused=1
    done
    if [[ "${action}" == ignore ]]; then
      for t in global local; do
        hit="$(jq -r --arg k "${kind}" --arg c "${name}" '[.[] | select(.kind == $k and .canon == $c)] | .[0].line // ""' <<< "${ignore_by_tier[${t}]}")"
        if [[ -n "${hit}" ]]; then
          log::err "refused: already ignored in ${t} as ${hit} | item='${kind}:${name}'"
          refused=1
        fi
      done
    fi
    if [[ "${kind}" == formula ]]; then
      hit="$(jq -r --arg n "${name}" '[.orphan_keg[] | select(.name == $n)] | .[0].hint // ""' "${DECREE_DRIFT}")"
      if [[ -n "${hit}" ]]; then
        log::err "refused: orphaned keg (${hit}); a fresh machine cannot install it | item='${kind}:${name}'"
        log::ERR "$(decree::orphan_recipe "${name}" "${hit}")"
        refused=1
      fi
    fi
  done
  (( refused )) && return 1

  # Plan buckets per tier: add / ign_add / ign_del (Brewfile and Brewfile.ignore lines), subj and
  # body (commit message parts); read back with decree::plan_lines.
  local -A plan=()
  local -a pending_taps=()
  [[ "${action}" == declare ]] && decree::dump_load
  local written_name
  for json in "${resolved[@]}"; do
    kind="$(decree::field "${json}" kind)"; name="$(decree::field "${json}" name)"
    line_name="$(decree::field "${json}" line_name)"; tap="$(decree::field "${json}" tap)"
    if [[ "${action}" == ignore ]]; then
      plan[ign_add_${tier}]+="${kind} ${name}  # ${reason}"$'\n'
      plan[subj_${tier}]+="${kind} ${name}"$'\n'
      continue
    fi
    local -a dump_names
    dump_names=(${(f)"$(jq -r '.dump_names[]' <<< "${json}")"})
    if [[ "${kind}" == tap ]]; then
      line="$(decree::tap_line "${name}")"
      pending_taps+=("${name}")
    elif ! line="$(decree::dump_line "${DECREE_KEYWORD[${kind}]}" "${dump_names[@]}")"; then
      line="${DECREE_KEYWORD[${kind}]} \"${line_name}\""
      log::info "dump omits the item (trust gate); synthesized | line='${line}'"
    fi
    [[ -n "${reason}" ]] && line="${line}  # ${reason}"
    written_name="$(decree::line_name "${line}")"
    plan[add_${tier}]+="${line}"$'\n'
    plan[subj_${tier}]+="${kind} ${written_name}"$'\n'
    if [[ "${kind}" == formula || "${kind}" == cask ]] && decree::is_third_party_tap "${tap}" \
       && (( ${declared_taps[(Ie)${tap}]} == 0 )) && (( ${pending_taps[(Ie)${tap}]} == 0 )); then
      line="$(decree::tap_line "${tap}")  # feeds ${written_name}"
      plan[add_${tier}]+="${line}"$'\n'
      plan[body_${tier}]+="tap ${tap} declared alongside: third-party tap declared nowhere"$'\n'
      pending_taps+=("${tap}")
      log::info "third-party tap declared in neither tier; adding it | tap='${tap}' tier='${tier}'"
    fi
    # A declaration supersedes an ignore (§3.4 step 2), so every ignore line for the item goes in
    # the same commit, hand-placed ones included; the commit body records each removal.
    for t in global local; do
      for hit in ${(f)"$(jq -r --arg k "${kind}" --arg c "${name}" '.[] | select(.kind == $k and .canon == $c) | .line' <<< "${ignore_by_tier[${t}]}")"}; do
        plan[ign_del_${t}]+="${hit}"$'\n'
        plan[body_${t}]+="drop ignore line: ${hit}"$'\n'
        log::info "ignore line removed; declared wins | tier='${t}' line='${hit}'"
      done
    done
  done

  local committed=0 failed=0 file
  local -a paths add ign_add ign_del subj body
  # Every tier about to be edited must be able to take the commit, or the refusal would leave
  # an edited, uncommitted tier file behind.
  if ! is_dry_run; then
    for t in global local; do
      decree::plan_lines add "add_${t}"; decree::plan_lines ign_add "ign_add_${t}"; decree::plan_lines ign_del "ign_del_${t}"
      (( ${#add} + ${#ign_add} + ${#ign_del} )) || continue
      tier::index_clean "${t}" || return 1
    done
  fi
  for t in global local; do
    paths=()
    decree::plan_lines add "add_${t}"; decree::plan_lines ign_add "ign_add_${t}"; decree::plan_lines ign_del "ign_del_${t}"
    decree::plan_lines subj "subj_${t}"; decree::plan_lines body "body_${t}"
    if (( ${#add} )); then
      file="$(decree::tier_file "${t}" Brewfile)"
      decree::block_read "${file}"
      for line in "${add[@]}"; do
        print -r -- "+ ${file}: ${line}"
        _decree_block+=("${line}")
      done
      if [[ "${t}" == local ]]; then
        decree::block_write "${file}" "${DECREE_LOCAL_BREWFILE_HEADER[@]}"
      else
        decree::block_write "${file}"
      fi
      paths+=("${file}")
    fi
    if (( ${#ign_add} + ${#ign_del} )); then
      file="$(decree::tier_file "${t}" Brewfile.ignore)"
      decree::block_read "${file}"
      for line in "${ign_del[@]}"; do
        print -r -- "- ${file}: ${line}"
        decree::block_remove_line "${line}"
        decree::head_remove_line "${line}"
      done
      for line in "${ign_add[@]}"; do
        print -r -- "+ ${file}: ${line}"
        _decree_block+=("${line}")
      done
      decree::block_write "${file}" "${DECREE_IGNORE_HEADER[@]}"
      paths+=("${file}")
    fi
    (( ${#paths} )) || continue

    local message
    if [[ "${action}" == ignore ]]; then
      message="$(decree::commit_message ignore "${t}" ": ${reason}" "${subj[@]}")"
    elif [[ "${t}" == "${tier}" ]]; then
      message="$(decree::commit_message declare "${t}" "" "${subj[@]}")"
    else
      # Only ignore lines changed here: the declaration landed in the other tier.
      local -a unignored=()
      for line in "${ign_del[@]}"; do
        [[ "${line}" =~ "${DECREE_IGNORE_LINE_RE}" ]] && unignored+=("${match[1]} ${match[2]}")
      done
      message="$(decree::commit_message unignore "${t}" ": declared in ${tier}" "${unignored[@]}")"
    fi
    if (( ${#body} )); then
      [[ "${message}" == *$'\n'* ]] || message="${message}"$'\n'
      message="${message}"$'\n'"${(F)${(@)body/#/- }}"
    fi
    if tier::commit "${t}" "${message}" "${paths[@]}"; then
      committed=$(( committed + 1 ))
    else
      failed=1
    fi
  done

  if is_dry_run; then
    log::info "dry-run: re-classification skipped"
    return 0
  fi
  (( failed )) && return 1
  (( committed )) || return 1

  # The classifier is the judge: every item must have left `undeclared`.
  decree::snapshot || return $?
  local took=0
  for json in "${resolved[@]}"; do
    kind="$(decree::field "${json}" kind)"; name="$(decree::field "${json}" name)"
    line_name="$(decree::field "${json}" line_name)"
    if jq -e --arg k "${kind}" --arg a "${name}" --arg b "${line_name}" \
         'any(.undeclared[]; .kind == $k and (.name == $a or .name == $b))' "${DECREE_DRIFT}" >/dev/null; then
      log::err "decree did not take; still undeclared after the commit | item='${kind}:${name}' drift='${DECREE_DRIFT}'"
      took=1
    fi
  done
  return "${took}"
}

# ── undecree ─────────────────────────────────────────────────────────────────────────────────

decree::undecree() {  # ITEM.. [--dry-run] [--no-push]
  local -A opts; local -a args
  verb::parse brew "$@"
  brew::only undecree --dry-run --no-push
  local -a items=("${args[@]}")
  (( ${#items} )) || usage_error "at least one ITEM is required"
  (( ${+opts[--dry-run]} )) && export ARI_DOTFILES_DRY_RUN=1
  (( ${+opts[--no-push]} )) && export ARI_DOTFILES_NO_PUSH=1
  is_dry_run && log::warn "dry-run: no file is written, nothing is committed"

  decree::snapshot --no-classify || return $?

  # Every decree-able line in the four files, tagged with tier and file kind.
  local t file entries all='[]'
  for t in global local; do
    file="$(decree::tier_file "${t}" Brewfile)"
    entries="$(decree::brewfile_entries "${file}" | jq -c --arg t "${t}" --arg f "${file}" 'map(. + {tier: $t, file: $f, source: "brewfile"})')"
    all="$(jq -c -n --argjson a "${all}" --argjson b "${entries}" '$a + $b')"
    file="$(decree::tier_file "${t}" Brewfile.ignore)"
    entries="$(decree::ignore_entries "${file}" | jq -c --arg t "${t}" --arg f "${file}" 'map(select(.kind != "include-declared") + {tier: $t, file: $f, source: "ignore"})')"
    all="$(jq -c -n --argjson a "${all}" --argjson b "${entries}" '$a + $b')"
  done

  # Plan buckets per tier: del_brew / del_ign (lines to remove), subj, body, taps.
  local -A plan=()
  local item kind wanted matches kinds block row rc=0
  for item in "${items[@]}"; do
    decree::parse_item "${item}" || return 64
    local -a kinds_to_try=(formula cask tap vscode)
    [[ -n "${_decree_kind}" ]] && kinds_to_try=("${_decree_kind}")
    wanted='[]'
    for kind in "${kinds_to_try[@]}"; do
      wanted="$(jq -c -n --argjson w "${wanted}" --arg k "${kind}" --arg c "$(decree::canon "${kind}" "${_decree_name}")" '$w + [{kind: $k, canon: $c}]')"
    done
    matches="$(jq -c --argjson w "${wanted}" --arg raw "${_decree_name}" \
                 '[ .[] | . as $e | select(any($w[]; .kind == $e.kind and (.canon == $e.canon or $e.raw == $raw))) ]' <<< "${all}")"
    kinds="$(jq -r 'map(.kind) | unique | join(" ")' <<< "${matches}")"
    if [[ -z "${_decree_kind}" && "${kinds}" == *" "* ]]; then
      log::err "ambiguous kind; prefix the item | item='${item}' candidates='$(jq -r 'map(.kind + ":" + .raw) | unique | join(" ")' <<< "${matches}")'"
      return 64
    fi
    while IFS=$'\t' read -r file row; do
      log::warn "hand-placed line left alone | file='${file}' line='${row}'"
    done < <(jq -r '.[] | select(.in_block | not) | [.file, .line] | @tsv' <<< "${matches}")
    block="$(jq -c '[.[] | select(.in_block)]' <<< "${matches}")"
    if [[ "$(jq -r 'length' <<< "${block}")" == 0 ]]; then
      log::err "nothing decreed for the item; only decree-block lines are removed | item='${item}'"
      rc=1
      continue
    fi
    local tier source line raw canon tap
    while IFS=$'\t' read -r tier source line kind raw canon; do
      if [[ "${source}" == brewfile ]]; then
        plan[del_brew_${tier}]+="${line}"$'\n'
        if [[ "${kind}" == formula || "${kind}" == cask ]]; then
          tap="$(jq -r -n --slurpfile inv "${DECREE_INVENTORY}" --arg k "${kind}" --arg c "${canon}" --arg raw "${raw}" '
            if ($raw | split("/") | length) >= 3 then ($raw | split("/") | .[0] + "/" + .[1])
            elif $k == "formula" then ([ ($inv[0].formulae // [])[] | select(.full_name == $c or .keg == $c) | .tap ] | .[0] // "")
            else ([ ($inv[0].casks // [])[] | select(.token == $c or .full_token == $c) | .tap ] | .[0] // "") end')"
          [[ -n "${tap}" ]] && plan[taps_${tier}]+="${tap}"$'\n'
        fi
      else
        plan[del_ign_${tier}]+="${line}"$'\n'
      fi
      plan[subj_${tier}]+="${kind} ${raw}"$'\n'
    done < <(jq -r '.[] | [.tier, .source, .line, .kind, .raw, .canon] | @tsv' <<< "${block}")
  done
  (( rc )) && return 1

  local committed=0 failed=0
  local -a paths del_brew del_ign subj body taps
  if ! is_dry_run; then
    for t in global local; do
      decree::plan_lines del_brew "del_brew_${t}"; decree::plan_lines del_ign "del_ign_${t}"
      (( ${#del_brew} + ${#del_ign} )) || continue
      tier::index_clean "${t}" || return 1
    done
  fi
  for t in global local; do
    paths=()
    decree::plan_lines del_brew "del_brew_${t}"; decree::plan_lines del_ign "del_ign_${t}"
    decree::plan_lines subj "subj_${t}"; decree::plan_lines body "body_${t}"; decree::plan_lines taps "taps_${t}"
    if (( ${#del_brew} )); then
      file="$(decree::tier_file "${t}" Brewfile)"
      decree::block_read "${file}"
      for line in "${del_brew[@]}"; do
        print -r -- "- ${file}: ${line}"
        decree::block_remove_line "${line}"
      done
      # A tap the tool declared for the item leaves with it unless another line still needs it.
      if (( ${#taps} )); then
        local -a in_use
        in_use=(${(f)"$(decree::taps_in_use)"})
        for tap in "${(@u)taps}"; do
          decree::is_third_party_tap "${tap}" || continue
          (( ${in_use[(Ie)${tap}]} )) && continue
          for line in ${(f)"$(decree::block_tap_lines "${tap}")"}; do
            print -r -- "- ${file}: ${line}"
            decree::block_remove_line "${line}"
            body+=("drop tap ${tap}: nothing else in this tier uses it")
          done
        done
      fi
      decree::block_write "${file}"
      paths+=("${file}")
    fi
    if (( ${#del_ign} )); then
      file="$(decree::tier_file "${t}" Brewfile.ignore)"
      decree::block_read "${file}"
      for line in "${del_ign[@]}"; do
        print -r -- "- ${file}: ${line}"
        decree::block_remove_line "${line}"
      done
      decree::block_write "${file}"
      paths+=("${file}")
    fi
    (( ${#paths} )) || continue
    local message
    message="$(decree::commit_message undeclare "${t}" "" "${(@u)subj}")"
    if (( ${#body} )); then
      [[ "${message}" == *$'\n'* ]] || message="${message}"$'\n'
      message="${message}"$'\n'"${(F)${(@)body/#/- }}"
    fi
    if tier::commit "${t}" "${message}" "${paths[@]}"; then
      committed=$(( committed + 1 ))
    else
      failed=1
    fi
  done
  (( failed )) && return 1
  (( committed )) || return 1
  return 0
}
