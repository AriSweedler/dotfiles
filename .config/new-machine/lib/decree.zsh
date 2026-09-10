# lib/decree.zsh — `new-machine brew triage | decree | undecree`. Sourced by bin/new-machine after
# lib/common.zsh, lib/brew.zsh and lib/dotfiles.zsh; defines functions and constants only.
#
# Both tiers' Brewfile and Brewfile.ignore are edited only inside a trailing "decree block" that
# starts at DECREE_MARKER. Hand-written sections are never rewritten, and undecree can tell the
# tool's own lines from Ari's. brew::declared stays the authority for what a Brewfile declares;
# the line scanning here only locates text to report or edit.
#
# Entry points (each takes the CLI args after `new-machine brew <sub>` and returns the exit code):
#   decree::triage   [--json]
#   decree::decree   ITEM... (--global|--local|--ignore-global|--ignore-local) [--reason TEXT] [--dry-run] [--no-push]
#   decree::undecree ITEM... [--dry-run] [--no-push]
# ITEM = [formula:|cask:|tap:|vscode:]name; the kind may be omitted when exactly one kind matches.
#
# Reads: NEW_MACHINE_STATE_DIR, NEW_MACHINE_NOW, RUN_DIR, RUN_ID, LAST_RESULT_FILE, HOME, NM_DRY_RUN,
# NM_NO_PUSH; brew and the tier file paths come from brew::bin, brew::global_brewfile and friends.

(( ${+DECREE_MARKER} )) || readonly DECREE_MARKER="# ── decreed via 'new-machine brew decree'; move into a section when tidying ──"
(( ${+DECREE_KEYWORD} )) || typeset -grA DECREE_KEYWORD=([formula]=brew [cask]=cask [tap]=tap [vscode]=vscode)
(( ${+DECREE_KIND_OF_KEYWORD} )) || typeset -grA DECREE_KIND_OF_KEYWORD=([brew]=formula [cask]=cask [tap]=tap [vscode]=vscode)
(( ${+DECREE_KIND_ORDER} )) || typeset -grA DECREE_KIND_ORDER=([tap]=0 [formula]=1 [cask]=2 [vscode]=3)
(( ${+DECREE_BREWFILE_LINE_RE} )) || readonly DECREE_BREWFILE_LINE_RE="^[[:space:]]*(brew|cask|tap|vscode)[[:space:]]+[\"']([^\"']+)[\"']"
(( ${+DECREE_IGNORE_LINE_RE} )) || readonly DECREE_IGNORE_LINE_RE='^[[:space:]]*(formula|cask|tap|vscode|include-declared)[[:space:]]+([^[:space:]#]+)'
(( ${+DECREE_LOCAL_BREWFILE_HEADER} )) || typeset -gra DECREE_LOCAL_BREWFILE_HEADER=(
  "# Packages for THIS machine only (local tier, git ldf). Applied together with the shared"
  "# ~/.config/new-machine/Brewfile by \`new-machine setup\`. Add with \`new-machine brew decree <name> --local\`;"
  "# move a line into the shared file by hand when every machine should have it."
)
(( ${+DECREE_IGNORE_HEADER} )) || typeset -gra DECREE_IGNORE_HEADER=(
  "# Installed here on purpose, but dotfiles do not own it. One entry per line:"
  "#   <formula|cask|tap|vscode> <canonical name>   # reason"
  "#   include-declared <abs path to a Brewfile>     # everything it declares counts as ignored"
)

# canon($k; $n) for jq programs run with `--slurpfile m "${DECREE_ALIAS_MAP}"`: the alias map's
# single value, else the name itself; taps and include paths are identity, extension ids lowercase.
(( ${+DECREE_JQ_CANON} )) || readonly DECREE_JQ_CANON='
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
  if nm::is_dry_run; then
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

# ── help ─────────────────────────────────────────────────────────────────────────────────────

decree::help_triage() {
  cat <<'EOF'
new-machine brew triage [--json]

Lists every installed brew item (formula, cask, tap, VS Code extension) that neither Brewfile
declares, with the three commands that settle it, then orphaned kegs, duplicates, declared
orphans, the ignore list and classifier notes. Describes; never recommends a tier.

  --json   print drift.json instead
  -h       this help

Exit 0 when nothing is undeclared, orphaned or duplicated; 1 otherwise; 2 when brew is busy.
EOF
}

decree::help_decree() {
  cat <<'EOF'
new-machine brew decree ITEM... (--global|--local|--ignore-global|--ignore-local) [--reason TEXT] [--dry-run] [--no-push]

Copies the installed item's declaration (the verbatim `brew bundle dump` line) into the tier's
Brewfile decree block and commits it; --ignore-* records the item in the tier's Brewfile.ignore
instead. A third-party tap the item needs is declared alongside, trusted. Refuses items that are
already declared, orphaned or not installed. Never installs, uninstalls or calls brew bundle add.

  ITEM             [formula:|cask:|tap:|vscode:]name; the kind may be omitted when unambiguous
  --global         ~/.config/new-machine/Brewfile        (git df; committed, never pushed)
  --local          ~/.local/share/new-machine/Brewfile   (git ldf; committed and pushed)
  --ignore-global  ~/.config/new-machine/Brewfile.ignore  (requires --reason)
  --ignore-local   ~/.local/share/new-machine/Brewfile.ignore (requires --reason)
  --reason TEXT    trailing `# TEXT` comment on the line
  --dry-run        print the lines, paths and git commands; touch nothing
  --no-push        skip the local tier's push
  -h               this help

Exit 0 done; 1 refused or did not take; 2 brew busy; 64 usage.
EOF
}

decree::help_undecree() {
  cat <<'EOF'
new-machine brew undecree ITEM... [--dry-run] [--no-push]

Removes the line(s) decree wrote for the item from whichever tier holds them (Brewfile or
Brewfile.ignore, decree block only; hand-placed lines are reported and left alone), drops the
tap line when nothing else in that tier uses the tap, and commits.

  ITEM       [formula:|cask:|tap:|vscode:]name
  --dry-run  print the lines, paths and git commands; touch nothing
  --no-push  skip the local tier's push
  -h         this help

Exit 0 done; 1 nothing decreed for the item; 2 brew busy; 64 usage.
EOF
}

# ── triage ───────────────────────────────────────────────────────────────────────────────────

decree::triage() {
  local json=0
  while (( $# )); do
    case "${1}" in
      -h|--help) decree::help_triage; return 0 ;;
      --json) json=1 ;;
      *) log::err "unknown argument | arg='${1}'"; decree::help_triage >&2; return 64 ;;
    esac
    shift
  done
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
    print -r -- "  then: new-machine brew decree cask:${name} --local"
  elif [[ "${hint}" == "tap not tapped" && "${name}" == */*/* ]]; then
    print -r -- "  brew tap ${tap}   # ${hint}; then re-run new-machine brew triage"
  else
    print -r -- "  brew uninstall ${keg}   # ${hint}"
  fi
}

decree::triage_render() {  # <drift.json>
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
      print -r -- "  every machine : new-machine brew decree ${kind}:${name} --global"
      print -r -- "  this machine  : new-machine brew decree ${kind}:${name} --local"
      print -r -- "  never declare : new-machine brew decree ${kind}:${name} --ignore-local --reason \"…\""
    done < <(jq -r --arg k "${kind}" '.undeclared[] | select(.kind == $k)
               | [.name, (.tap // "-"), ((.new // false) | tostring)] | @tsv' "${drift}")
  done
  (( count == 0 )) && print -r -- "  (none)"

  local hint
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

# ── decree ───────────────────────────────────────────────────────────────────────────────────

# Message subject + body for one tier's commit.
decree::commit_message() {  # <verb> <tier> <suffix> <item line>... ; suffix is appended to the subject
  local verb="${1}" tier="${2}" suffix="${3}"; shift 3
  local -a items=("$@")
  if (( ${#items} == 1 )); then
    print -r -- "new-machine: ${verb} ${items[1]} (${tier})${suffix}"
    return 0
  fi
  print -r -- "new-machine: ${verb} ${#items} items (${tier})${suffix}"
  print -r -- ""
  local item
  for item in "${items[@]}"; do print -r -- "- ${item}"; done
}

decree::decree() {
  local action="" tier="" reason="" tier_flags=0
  local -a items=()
  while (( $# )); do
    case "${1}" in
      -h|--help) decree::help_decree; return 0 ;;
      --global) action=declare; tier=global; tier_flags=$(( tier_flags + 1 )) ;;
      --local) action=declare; tier=local; tier_flags=$(( tier_flags + 1 )) ;;
      --ignore-global) action=ignore; tier=global; tier_flags=$(( tier_flags + 1 )) ;;
      --ignore-local) action=ignore; tier=local; tier_flags=$(( tier_flags + 1 )) ;;
      --reason)
        if (( $# < 2 )); then log::err "--reason needs a value"; decree::help_decree >&2; return 64; fi
        reason="${2}"; shift ;;
      --reason=*) reason="${1#--reason=}" ;;
      --dry-run) export NM_DRY_RUN=1 ;;
      --no-push) export NM_NO_PUSH=1 ;;
      --) shift; items+=("$@"); break ;;
      -*) log::err "unknown flag | flag='${1}'"; decree::help_decree >&2; return 64 ;;
      *) items+=("${1}") ;;
    esac
    shift
  done
  if (( tier_flags != 1 )); then
    log::err "exactly one of --global, --local, --ignore-global, --ignore-local is required"
    decree::help_decree >&2
    return 64
  fi
  if (( ${#items} == 0 )); then
    log::err "at least one ITEM is required"
    decree::help_decree >&2
    return 64
  fi
  if [[ "${action}" == ignore && -z "${reason}" ]]; then
    log::err "--reason is required with --ignore-global/--ignore-local"
    decree::help_decree >&2
    return 64
  fi
  nm::is_dry_run && log::warn "dry-run: no file is written, nothing is committed"

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
      line="$(decree::tap_line "${tap}")"
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
  if ! nm::is_dry_run; then
    for t in global local; do
      decree::plan_lines add "add_${t}"; decree::plan_lines ign_add "ign_add_${t}"; decree::plan_lines ign_del "ign_del_${t}"
      (( ${#add} + ${#ign_add} + ${#ign_del} )) || continue
      dotfiles::index_clean "${t}" || return 1
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
    if dotfiles::commit "${t}" "${message}" "${paths[@]}"; then
      committed=$(( committed + 1 ))
    else
      failed=1
    fi
  done

  if nm::is_dry_run; then
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

decree::undecree() {
  local -a items=()
  while (( $# )); do
    case "${1}" in
      -h|--help) decree::help_undecree; return 0 ;;
      --dry-run) export NM_DRY_RUN=1 ;;
      --no-push) export NM_NO_PUSH=1 ;;
      --) shift; items+=("$@"); break ;;
      -*) log::err "unknown flag | flag='${1}'"; decree::help_undecree >&2; return 64 ;;
      *) items+=("${1}") ;;
    esac
    shift
  done
  if (( ${#items} == 0 )); then
    log::err "at least one ITEM is required"
    decree::help_undecree >&2
    return 64
  fi
  nm::is_dry_run && log::warn "dry-run: no file is written, nothing is committed"

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
  if ! nm::is_dry_run; then
    for t in global local; do
      decree::plan_lines del_brew "del_brew_${t}"; decree::plan_lines del_ign "del_ign_${t}"
      (( ${#del_brew} + ${#del_ign} )) || continue
      dotfiles::index_clean "${t}" || return 1
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
    if dotfiles::commit "${t}" "${message}" "${paths[@]}"; then
      committed=$(( committed + 1 ))
    else
      failed=1
    fi
  done
  (( failed )) && return 1
  (( committed )) || return 1
  return 0
}
