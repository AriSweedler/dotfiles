# Brew model for new-machine: receipts-based inventory, alias map, declared sets, the
# `brew bundle check` parser, the merged two-tier Brewfile, the drift classifier driver
# (lib/brew_classify.jq), the busy guard, and the verdict helpers the brew steps call.
#
# Requires common.zsh to be sourced first for the NEW_MACHINE_* contract, the tier file paths,
# log::* and nm::plural. Side-effect-free at source time. stdout is data (JSON or text), stderr
# is logs. Every brew call here is read-only except brew::apply_pkgs, which goes through
# run_cmd_mutating. Functions that need the step context (verdict, RUN_DIR, STEP) say so.

if (( ! ${+BREW_LIB_DIR} )); then
  readonly BREW_LIB_DIR="${${(%):-%x}:A:h}"
fi
if (( ! ${+BREW_KINDS} )); then
  readonly -a BREW_KINDS=(formula cask tap vscode)
fi

# stdin lines → JSON array of non-empty strings.
brew::_lines_json() {
  jq -R -s -c 'split("\n") | map(select(length > 0))'
}

# stdin TSV rows → JSON array of objects keyed by the given field names.
brew::_tsv_json() {
  jq -R -s -c --args '
    split("\n") | map(select(length > 0) | split("\t") | . as $fields
      | [$ARGS.positional, $fields] | transpose | map({key: .[0], value: (.[1] // "")}) | from_entries)' "$@"
}

# Prints the brew executable common.zsh resolved (PATH, then the probe prefixes launchd needs).
# Returns 1 when there is none.
brew::bin() {
  [[ -n "${NEW_MACHINE_BREW}" && -x "${NEW_MACHINE_BREW}" ]] || return 1
  print -r -- "${NEW_MACHINE_BREW}"
}

# Pids of every running brew (space-separated), empty when idle.
brew::busy_pids() {
  local pids
  pids="$(pgrep -f "${NEW_MACHINE_BREW_BUSY_PATTERN}" 2>/dev/null || true)"
  print -r -- "${pids//$'\n'/ }"
}

# Silent predicate: 0 when another brew is running. Silent because checks call it as
# `if brew::is_busy` and their stdout must stay exactly one verdict; brew::busy_pids has the pids.
# A concurrent brew holds its own locks, so the brew steps report `error brew_busy`, never fail.
brew::is_busy() {
  [[ -n "$(brew::busy_pids)" ]]
}

# Homebrew's repository root, resolved once per process: every `brew --repository` is a ~150 ms
# shell start and the tap layout beneath it is fixed.
brew::_repo_root() {
  if [[ -z "${_BREW_REPO_ROOT:-}" ]]; then
    local brew
    brew="$(brew::bin)" || return 1
    typeset -g _BREW_REPO_ROOT
    _BREW_REPO_ROOT="$("${brew}" --repository)" || return 1
  fi
  print -r -- "${_BREW_REPO_ROOT}"
}

# Checkout directory of a tapped third-party tap; 1 when it is not on disk.
brew::_tap_repo_dir() {
  local tap="${1:?brew::_tap_repo_dir: tap required}" root
  root="$(brew::_repo_root)" || return 1
  local dir="${root}/Library/Taps/${tap%%/*}/homebrew-${tap#*/}"
  [[ -d "${dir}" ]] || return 1
  print -r -- "${dir}"
}

# brew::snapshot <inventory.json> <info_installed.json>: both producers at once; they are
# independent one-second brew calls. Returns 2 when the inventory failed, 3 when brew's JSON did.
brew::snapshot() {
  local inventory="${1:?brew::snapshot: inventory path required}" info="${2:?brew::snapshot: info path required}"
  local rc_dir
  rc_dir="$(mktemp -d)" || return 1
  ( brew::inventory > "${inventory}"; print -r -- $? > "${rc_dir}/inventory" ) &
  ( brew::info_installed > "${info}"; print -r -- $? > "${rc_dir}/info" ) &
  wait
  local inventory_rc info_rc
  inventory_rc="$(<"${rc_dir}/inventory")"
  info_rc="$(<"${rc_dir}/info")"
  rm -rf "${rc_dir}"
  (( inventory_rc == 0 )) || return 2
  (( info_rc == 0 )) || return 3
  return 0
}

# Tier files as common.zsh resolved them: under HOME once it is checked out, else beside the script.
brew::global_brewfile() { print -r -- "${GLOBAL_BREWFILE}"; }
brew::global_ignore()   { print -r -- "${GLOBAL_BREWFILE_IGNORE}"; }
brew::local_brewfile()  { print -r -- "${LOCAL_BREWFILE}"; }
brew::local_ignore()    { print -r -- "${LOCAL_BREWFILE_IGNORE}"; }

# Installed universe from INSTALL_RECEIPT.json files, printed as JSON. Receipts rather than brew's
# listing commands because Homebrew 6 hides untrusted-tap kegs from `brew leaves`/`info`.
#   {cellar, caskroom,
#    formulae: [{kind:"formula", keg, tap, full_name, on_request, source_path, source_path_exists}],
#    casks:    [{kind:"cask", token, tap, full_token, on_request, source_path, source_path_exists}],
#    taps: [{kind:"tap", name}], vscode: [{kind:"vscode", id}], vscode_skipped, list_full_name: [...]}
# A keg with several versions is on_request if any version is, and its source path exists if any
# version's does. `list_full_name` is only a self-consistency lint for the classifier.
brew::inventory() {
  local brew
  if ! brew="$(brew::bin)"; then
    log::err "brew not found"
    return 1
  fi
  local cellar caskroom
  cellar="$("${brew}" --cellar)" || return 1
  caskroom="$("${brew}" --caskroom)" || return 1

  local -a formula_receipts=("${cellar}"/*/*/INSTALL_RECEIPT.json(N))
  local -a cask_receipts=("${caskroom}"/*/.metadata/INSTALL_RECEIPT.json(N))
  local receipts='[]'
  if (( ${#formula_receipts} + ${#cask_receipts} > 0 )); then
    receipts="$(jq -c '{file: input_filename, on_request: (.installed_on_request // false),
                        tap: .source.tap, source_path: .source.path}' \
                  "${formula_receipts[@]}" "${cask_receipts[@]}" | jq -s -c .)" || return 1
  fi

  local -a existing=()
  local source_path
  for source_path in ${(f)"$(jq -r '.[].source_path // empty' <<< "${receipts}" | sort -u)"}; do
    if [[ -e "${source_path}" ]]; then
      existing+=("${source_path}")
    fi
  done

  local taps_json list_json
  taps_json="$("${brew}" tap | brew::_lines_json)" || return 1
  list_json="$("${brew}" list --formula --full-name | brew::_lines_json)" || return 1

  local code="${NEW_MACHINE_CODE}"
  local vscode_json='[]' vscode_skipped=true extensions
  if [[ -n "${code}" && -x "${code}" ]]; then
    if extensions="$("${code}" --list-extensions 2>/dev/null)"; then
      vscode_json="$(print -r -- "${extensions}" | brew::_lines_json | jq -c 'map(ascii_downcase)')" || return 1
      vscode_skipped=false
    else
      log::warn "code --list-extensions failed; vscode inventory skipped | code='${code}'"
    fi
  else
    log::info "code not found; vscode inventory skipped"
  fi

  jq -n -c \
    --argjson receipts "${receipts}" --arg cellar "${cellar}" --arg caskroom "${caskroom}" \
    --argjson taps "${taps_json}" --argjson vscode "${vscode_json}" --argjson vscode_skipped "${vscode_skipped}" \
    --argjson list_full_name "${list_json}" \
    --args '
    ($ARGS.positional) as $existing
    | def exists($p): $p != null and any($existing[]; . == $p);
      def under($dir): select(.file | startswith($dir + "/"));
      def first_dir($dir): .file | ltrimstr($dir + "/") | split("/")[0];
      def first_tap: map(.tap) | map(select(. != null)) | .[0];
      def first_path: map(.source_path) | map(select(. != null)) | .[0];
      {
        cellar: $cellar, caskroom: $caskroom,
        formulae: ([ $receipts[] | under($cellar) | . + {keg: first_dir($cellar)} ]
          | group_by(.keg) | map(first_tap as $tap
            | {kind: "formula", keg: .[0].keg, tap: $tap,
               full_name: (if $tap == null or $tap == "homebrew/core" then .[0].keg else $tap + "/" + .[0].keg end),
               on_request: any(.[]; .on_request), source_path: first_path,
               source_path_exists: any(.[]; exists(.source_path))})),
        casks: ([ $receipts[] | under($caskroom) | . + {token: first_dir($caskroom)} ]
          | group_by(.token) | map(first_tap as $tap
            | {kind: "cask", token: .[0].token, tap: $tap,
               full_token: (if $tap == null or $tap == "homebrew/cask" then .[0].token else $tap + "/" + .[0].token end),
               on_request: any(.[]; .on_request), source_path: first_path,
               source_path_exists: any(.[]; exists(.source_path))})),
        taps: ($taps | map({kind: "tap", name: .})),
        vscode: ($vscode | map({kind: "vscode", id: .})),
        vscode_skipped: $vscode_skipped,
        list_full_name: $list_full_name
      }' "${existing[@]}"
}

# `brew info --json=v2 --installed`, normalized to {formulae, casks}. Enrichment only: the trust
# gate can omit kegs the inventory has.
brew::info_installed() {
  local brew
  if ! brew="$(brew::bin)"; then
    log::err "brew not found"
    return 1
  fi
  "${brew}" info --json=v2 --installed | jq -c '{formulae: (.formulae // []), casks: (.casks // [])}'
}

# brew::alias_map <info_installed.json> <inventory.json> → {formula: {<key>: [full_name...]},
# cask: {<key>: [token...]}}. Keys: name, full_name, aliases, oldnames, and <tap>/<alias|oldname>
# so a company `buildkite/buildkite/bk` canonicalizes to bk@3. Receipt-derived keys cover kegs the
# JSON omits. Values are arrays: a short name claimed by two taps is ambiguous, never a guess.
brew::alias_map() {
  local info="${1:?brew::alias_map: info_installed.json required}"
  local inventory="${2:?brew::alias_map: inventory.json required}"
  jq -n -c --slurpfile info "${info}" --slurpfile inv "${inventory}" '
    ($info[0]) as $info | ($inv[0]) as $inv
    | def qual($tap; $n): if $tap == null or $tap == "homebrew/core" then empty else $tap + "/" + $n end;
      def fkeys($f): [$f.name, $f.full_name] + ($f.aliases // []) + ($f.oldnames // [])
                     + [ (($f.aliases // []) + ($f.oldnames // []))[] | qual($f.tap; .) ];
      def fold: group_by(.key) | map({key: .[0].key, value: (map(.value) | unique)}) | from_entries;
      { formula: ([ ($info.formulae // [])[] | . as $f | fkeys($f)[] | select(. != null) | {key: ., value: $f.full_name} ]
                  + [ ($inv.formulae // [])[] | {key: .keg, value: .full_name}, {key: .full_name, value: .full_name} ]
                  | fold),
        cask: ([ ($info.casks // [])[] | . as $c | ([$c.token, $c.full_token] + ($c.old_tokens // []))[]
                 | select(. != null) | {key: ., value: $c.token} ]
               + [ ($inv.casks // [])[] | {key: .token, value: .token}, {key: .full_token, value: .token} ]
               | fold) }'
}

# brew::declared <brewfile> → {formula: [...], cask: [...], tap: [...], vscode: [...]}, names as
# written, duplicates preserved. brew is the only Brewfile parser; a missing file is empty sets.
brew::declared() {
  local file="${1:-}"
  if [[ -z "${file}" || ! -f "${file}" ]]; then
    print -r -- '{"formula":[],"cask":[],"tap":[],"vscode":[]}'
    return 0
  fi
  local brew
  if ! brew="$(brew::bin)"; then
    log::err "brew not found"
    return 1
  fi
  # One brew start per kind (~0.4 s each); the four are independent, so they run at once.
  local tmp
  tmp="$(mktemp -d)" || return 1
  local kind
  for kind in "${BREW_KINDS[@]}"; do
    ( "${brew}" bundle list "--${kind}" --file="${file}" > "${tmp}/${kind}"; print -r -- $? > "${tmp}/${kind}.rc" ) &
  done
  wait
  local -a parts=()
  for kind in "${BREW_KINDS[@]}"; do
    if [[ "$(<"${tmp}/${kind}.rc")" != 0 ]]; then
      rm -rf "${tmp}"
      return 1
    fi
    # ohai chatter ("==> Auto-updating Homebrew...") goes to stdout; a name never starts with it.
    parts+=("$(jq -R -s -c 'split("\n") | map(select(length > 0 and (startswith("==>") | not)))' "${tmp}/${kind}")")
  done
  rm -rf "${tmp}"
  jq -n -c --argjson formula "${parts[1]}" --argjson cask "${parts[2]}" \
           --argjson tap "${parts[3]}" --argjson vscode "${parts[4]}" \
    '{formula: $formula, cask: $cask, tap: $tap, vscode: $vscode}'
}

# brew::parse_ignore <Brewfile.ignore> <global|local> →
#   {tier, entries: [{kind, name, reason}], includes: [{path, reason}]}
# Format (§3.2): `<kind> <canonical-name>  # reason` or `include-declared <abs path>  # reason`;
# `#` comments and blank lines skipped. An unknown kind is kept as written so the classifier
# reports it as unresolvable instead of silently dropping it.
brew::parse_ignore() {
  setopt local_options extended_glob
  local file="${1:-}" tier="${2:?brew::parse_ignore: tier (global|local) required}"
  local -a entry_rows=() include_rows=()
  if [[ -n "${file}" && -f "${file}" ]]; then
    local line body reason
    local -a fields
    while IFS= read -r line || [[ -n "${line}" ]]; do
      body="${line%%\#*}"
      reason=""
      if [[ "${line}" == *'#'* ]]; then
        reason="${line#*\#}"
        reason="${reason##[[:space:]]#}"
        reason="${reason%%[[:space:]]#}"
      fi
      fields=(${=body})
      if (( ${#fields} == 0 )); then
        continue
      fi
      if [[ "${fields[1]}" == include-declared ]]; then
        if (( ${#fields} < 2 )); then
          log::warn "include-declared without a path; line ignored | file='${file}' line='${line}'"
          continue
        fi
        include_rows+=("${fields[2]}"$'\t'"${reason}")
        continue
      fi
      if (( ${#fields} < 2 )); then
        log::warn "ignore entry without a name; line ignored | file='${file}' line='${line}'"
        continue
      fi
      if (( ! ${BREW_KINDS[(Ie)${fields[1]}]} )); then
        log::warn "ignore entry with unknown kind | file='${file}' kind='${fields[1]}' name='${fields[2]}'"
      fi
      entry_rows+=("${fields[1]}"$'\t'"${fields[2]}"$'\t'"${reason}")
    done < "${file}"
  fi
  local entries='[]' includes='[]'
  if (( ${#entry_rows} > 0 )); then
    entries="$(print -rl -- "${entry_rows[@]}" | brew::_tsv_json kind name reason)" || return 1
  fi
  if (( ${#include_rows} > 0 )); then
    includes="$(print -rl -- "${include_rows[@]}" | brew::_tsv_json path reason)" || return 1
  fi
  jq -n -c --arg tier "${tier}" --argjson entries "${entries}" --argjson includes "${includes}" \
    '{tier: $tier, entries: $entries, includes: $includes}'
}

# Declared sets for a tier argument that is either a brew::declared JSON file or a Brewfile
# (callers pass whichever they have); anything else is empty sets.
brew::_declared_arg() {
  local file="${1:-}"
  if [[ -n "${file}" && -f "${file}" ]]; then
    if jq -e 'type == "object" and has("formula")' "${file}" > /dev/null 2>&1; then
      jq -c . "${file}"
      return 0
    fi
    brew::declared "${file}"
    return $?
  fi
  print -r -- '{"formula":[],"cask":[],"tap":[],"vscode":[]}'
}

# brew::parse_bundle_check <bundle_check.out> <rc> [<global declared.json|Brewfile> [<local …>]]
#   → {rc, items: [{kind, name, problem, hint?, tier}], unparsed, unparsed_lines, error_lines}
# Pure zsh over the captured text (stdout+stderr). Recognized lines:
#   → (Formula|Cask|Tap|VSCode Extension) <name> needs to be (installed|tapped|unlinked).
# `unlinked` means two declarations of one formula disagree on options: problem "conflict".
# Any other `→ ` line is unparsed; `Error:` lines are collected; everything else is chatter.
# tier: every tier whose declared list has `name` or an entry ending in "/<name>" (bundle check
# prints casks as bare tokens), joined with ","; "?" when none matches.
brew::parse_bundle_check() {
  local out_file="${1:?brew::parse_bundle_check: output file required}"
  local rc="${2:?brew::parse_bundle_check: exit code required}"
  local declared_global declared_local
  declared_global="$(brew::_declared_arg "${3:-}")" || return 1
  declared_local="$(brew::_declared_arg "${4:-}")" || return 1
  local -a rows=() unparsed=() errors=()
  local line rest kind problem
  while IFS= read -r line || [[ -n "${line}" ]]; do
    if [[ "${line}" == Error:* ]]; then
      errors+=("${line}")
      continue
    fi
    [[ "${line}" == '→ '* ]] || continue
    rest="${line#→ }"
    if [[ "${rest}" =~ '^(Formula|Cask|Tap|VSCode Extension) (.+) needs to be (installed|tapped|unlinked)\.$' ]]; then
      case "${match[1]}" in
        Formula) kind=formula ;;
        Cask) kind=cask ;;
        Tap) kind=tap ;;
        *) kind=vscode ;;
      esac
      if [[ "${match[3]}" == unlinked ]]; then
        problem="conflict"
      else
        problem="needs to be ${match[3]}"
      fi
      rows+=("${kind}"$'\t'"${match[2]}"$'\t'"${problem}")
    else
      unparsed+=("${line}")
    fi
  done < "${out_file}"

  local items='[]' unparsed_json='[]' errors_json='[]'
  if (( ${#rows} > 0 )); then
    items="$(print -rl -- "${rows[@]}" | brew::_tsv_json kind name problem)" || return 1
  fi
  if (( ${#unparsed} > 0 )); then
    unparsed_json="$(print -rl -- "${unparsed[@]}" | brew::_lines_json)" || return 1
  fi
  if (( ${#errors} > 0 )); then
    errors_json="$(print -rl -- "${errors[@]}" | brew::_lines_json)" || return 1
  fi
  jq -n -c --argjson rc "${rc}" --argjson items "${items}" \
    --argjson unparsed_lines "${unparsed_json}" --argjson error_lines "${errors_json}" \
    --argjson global "${declared_global}" --argjson local "${declared_local}" '
    [{tier: "global", decl: $global}, {tier: "local", decl: $local}] as $declared
    | {rc: $rc,
       items: ($items | map(
         if .problem == "conflict" then . + {hint: "duplicate declaration with differing options"} else . end
         | . as $item
         | ([ $declared[] | select((.decl[$item.kind] // []) | any(. == $item.name or endswith("/" + $item.name))) | .tier ]) as $tiers
         | . + {tier: (if ($tiers | length) == 0 then "?" else ($tiers | join(",")) end)})),
       unparsed: (($unparsed_lines | length) > 0),
       unparsed_lines: $unparsed_lines,
       error_lines: $error_lines}'
}

# brewfile::merge <out> <global> [<local>]: both tiers verbatim into one file, no dedupe.
# One file means one `brew bundle check`/`install` over one consistent snapshot; identical
# duplicates are tolerated by brew and option-conflicting ones must surface, not be hidden.
brewfile::merge() {
  local out="${1:?brewfile::merge: output path required}"
  local global="${2:?brewfile::merge: global Brewfile required}"
  local local_file="${3:-}"
  if [[ ! -f "${global}" ]]; then
    log::err "global Brewfile missing | path='${global}'"
    return 1
  fi
  {
    print -r -- "# generated by new-machine run_id=${RUN_ID:-}; edit the tier files, not this"
    print -r -- "# ── tier: global  ${global}"
    cat "${global}"
    print -r -- "# ── tier: local   ${local_file}"
    if [[ -f "${local_file}" ]]; then cat "${local_file}"; else print -r -- "# (absent)"; fi
  } > "${out}"
}

# Resolve every include-declared directive of the parsed ignore files into
# [{tier, path, reason, present, declared}]. A missing path is reported, never silently skipped.
brew::_include_declared() {
  local -a rows=()
  # Not `path`: that is zsh's array tied to PATH, and a local one empties it.
  local parsed tier include_path reason declared row
  for parsed in "$@"; do
    tier="$(jq -r '.tier' <<< "${parsed}")" || return 1
    while IFS=$'\t' read -r include_path reason; do
      [[ -n "${include_path}" ]] || continue
      if [[ -f "${include_path}" && -r "${include_path}" ]]; then
        declared="$(brew::declared "${include_path}")" || return 1
        row="$(jq -n -c --arg tier "${tier}" --arg path "${include_path}" --arg reason "${reason}" --argjson declared "${declared}" \
          '{tier: $tier, path: $path, reason: $reason, present: true, declared: $declared}')" || return 1
      else
        row="$(jq -n -c --arg tier "${tier}" --arg path "${include_path}" --arg reason "${reason}" \
          '{tier: $tier, path: $path, reason: $reason, present: false, declared: {}}')" || return 1
      fi
      rows+=("${row}")
    done < <(jq -r '.includes[] | [.path, .reason] | @tsv' <<< "${parsed}")
  done
  if (( ${#rows} == 0 )); then
    print -r -- '[]'
    return 0
  fi
  print -rl -- "${rows[@]}" | jq -s -c .
}

brew::_third_party_taps() {
  jq -r '.taps[].name | select(. != "homebrew/core" and . != "homebrew/cask")' "${1}"
}

# {"<tap>": {formula_names, cask_tokens}} for every tapped third-party tap. Only per-tap
# tap-info: `--installed` would pull homebrew/core and thousands of cask tokens.
# Each tap-info is a ~2 s Ruby start, so the answer is cached under the state dir keyed on the
# tap checkout's git HEAD (a tap's contents cannot change without it), and misses run at once.
# A tap dir that is not a git checkout is fetched every time.
brew::_tap_info_map() {
  local inventory="${1}"
  local brew
  brew="$(brew::bin)" || return 1
  local -a taps=(${(f)"$(brew::_third_party_taps "${inventory}")"})
  if (( ${#taps} == 0 )); then
    print -r -- '{}'
    return 0
  fi
  local cache_dir="${NEW_MACHINE_STATE_DIR}/cache/tap-info"
  local tmp
  tmp="$(mktemp -d)" || return 1
  local tap slug repo head
  local -A cache_file=()
  local -a misses=()
  for tap in "${taps[@]}"; do
    slug="${tap//\//--}"
    head=""
    if repo="$(brew::_tap_repo_dir "${tap}")"; then
      head="$(git -C "${repo}" rev-parse HEAD 2>/dev/null || true)"
    fi
    if [[ -n "${head}" ]]; then
      cache_file[${tap}]="${cache_dir}/${slug}.${head}.json"
      if [[ -s "${cache_file[${tap}]}" ]]; then
        cp "${cache_file[${tap}]}" "${tmp}/${slug}.json"
        continue
      fi
    fi
    misses+=("${tap}")
  done
  # exec keeps a hung brew as close to this process as the old $(...) did, for the watchdog's tree kill.
  for tap in "${misses[@]}"; do
    slug="${tap//\//--}"
    ( exec "${brew}" tap-info --json "${tap}" > "${tmp}/${slug}.raw" 2>/dev/null ) &
  done
  wait
  local doc
  local -a docs=()
  for tap in "${taps[@]}"; do
    slug="${tap//\//--}"
    if [[ -s "${tmp}/${slug}.json" ]]; then
      docs+=("$(<"${tmp}/${slug}.json")")
      continue
    fi
    if [[ ! -s "${tmp}/${slug}.raw" ]]; then
      log::warn "brew tap-info failed; orphan check for this tap uses the formula path only | tap='${tap}'"
      continue
    fi
    if doc="$(jq -c --arg tap "${tap}" 'if type == "array" then .[0] else . end
               | {key: $tap, value: {formula_names: (.formula_names // []), cask_tokens: (.cask_tokens // [])}}' "${tmp}/${slug}.raw")"; then
      docs+=("${doc}")
      if [[ -n "${cache_file[${tap}]:-}" ]]; then
        local -a stale=("${cache_dir}/${slug}."*.json(N))
        if mkdir -p "${cache_dir}" && print -r -- "${doc}" > "${cache_file[${tap}]}.$$" \
             && mv "${cache_file[${tap}]}.$$" "${cache_file[${tap}]}"; then
          (( ${#stale} == 0 )) || rm -f "${stale[@]}"
        else
          log::warn "tap-info cache not written | path='${cache_file[${tap}]}'"
        fi
      fi
    else
      log::warn "brew tap-info printed non-JSON; ignored | tap='${tap}'"
    fi
  done
  rm -rf "${tmp}"
  if (( ${#docs} == 0 )); then
    print -r -- '{}'
    return 0
  fi
  print -rl -- "${docs[@]}" | jq -s -c 'from_entries'
}

# {"<tap>": ["<token>", ...]} from Casks/*.rb under each tapped third-party tap's repository:
# the offline signal that a formula keg was converted to a cask.
brew::_tap_casks_on_disk() {
  local inventory="${1}"
  local brew
  brew="$(brew::bin)" || return 1
  local -a taps=(${(f)"$(brew::_third_party_taps "${inventory}")"})
  local tap repo doc
  local -a docs=() tokens
  for tap in "${taps[@]}"; do
    repo="$(brew::_tap_repo_dir "${tap}")" || continue
    tokens=("${repo}"/Casks/**/*.rb(N:t:r))
    doc="$(jq -n -c --arg tap "${tap}" --args '{key: $tap, value: $ARGS.positional}' "${tokens[@]}")" || continue
    docs+=("${doc}")
  done
  if (( ${#docs} == 0 )); then
    print -r -- '{}'
    return 0
  fi
  print -rl -- "${docs[@]}" | jq -s -c 'from_entries'
}

# Taps whose tier line carries `trusted: true`, plus trust.json's trustedtaps. This is the one
# place a Brewfile line is read directly: brew's list commands drop the options.
brew::_trusted_taps() {
  local -a names=()
  local file line
  for file in "$@"; do
    [[ -n "${file}" && -f "${file}" ]] || continue
    while IFS= read -r line || [[ -n "${line}" ]]; do
      if [[ "${line}" == *'trusted: true'* && "${line}" =~ '^[[:space:]]*tap[[:space:]]+"([^"]+)"' ]]; then
        names+=("${match[1]}")
      fi
    done < "${file}"
  done
  local trust_json="${XDG_CONFIG_HOME}/homebrew/trust.json"
  if [[ -f "${trust_json}" ]]; then
    names+=(${(f)"$(jq -r '.trustedtaps[]? // empty' "${trust_json}" 2>/dev/null || true)"})
  fi
  if (( ${#names} == 0 )); then
    print -r -- '[]'
    return 0
  fi
  print -rl -- "${names[@]}" | jq -R -s -c 'split("\n") | map(select(length > 0)) | unique'
}

# trust.json's per-item trust, {formula: [...], cask: [...]}; empty lists when there is no file.
brew::_trusted_items() {
  local trust_json="${XDG_CONFIG_HOME}/homebrew/trust.json"
  if [[ ! -f "${trust_json}" ]]; then
    print -r -- '{"formula":[],"cask":[]}'
    return 0
  fi
  jq -c '{formula: ([.trustedformulae[]? | strings] | unique), cask: ([.trustedcasks[]? | strings] | unique)}' \
    "${trust_json}" 2>/dev/null || print -r -- '{"formula":[],"cask":[]}'
}

# brew::classify [<inventory.json>] [<info_installed.json>] [<global Brewfile>] [<local Brewfile>]
#                [<global Brewfile.ignore>] [<local Brewfile.ignore>] [<previous_undeclared.json>]
#   → drift.json on stdout (shape in §2.7). Every argument defaults to the run's file
# (${RUN_DIR}/inventory.json, …/info_installed.json — produced on demand — the tier files, and
# the previous run's undeclared list), so a step may call it bare. Absent files are empty sets;
# previous_undeclared is a JSON array of "<kind>/<name>". Gathers every input the jq classifier
# needs (alias map, declared sets, parsed ignores, include-declared Brewfiles, tap-info, on-disk
# casks, trusted taps) and hands them over as one object, so the classifier itself stays pure.
brew::classify() {
  local inventory="${1:-}" info="${2:-}" global_brewfile="${3:-}"
  local local_brewfile="${4:-}" global_ignore="${5:-}" local_ignore="${6:-}" previous="${7:-}"
  if (( $# < 1 )); then
    inventory="${RUN_DIR:?brew::classify: inventory.json or RUN_DIR required}/inventory.json"
    if [[ ! -s "${inventory}" ]]; then
      brew::inventory > "${inventory}" || return 1
    fi
  fi
  if (( $# < 2 )); then
    info="${RUN_DIR:?brew::classify: info_installed.json or RUN_DIR required}/info_installed.json"
    if [[ ! -s "${info}" ]]; then
      brew::info_installed > "${info}" || return 1
    fi
  fi
  if (( $# < 3 )); then global_brewfile="$(brew::global_brewfile)"; fi
  if (( $# < 4 )); then local_brewfile="$(brew::local_brewfile)"; fi
  if (( $# < 5 )); then global_ignore="$(brew::global_ignore)"; fi
  if (( $# < 6 )); then local_ignore="$(brew::local_ignore)"; fi
  local alias_map declared_global declared_local ignore_global ignore_local
  local include_declared tap_info tap_casks trusted trusted_items previous_json
  previous_json="$(brew::previous_undeclared)"
  alias_map="$(brew::alias_map "${info}" "${inventory}")" || return 1
  declared_global="$(brew::declared "${global_brewfile}")" || return 1
  declared_local="$(brew::declared "${local_brewfile}")" || return 1
  ignore_global="$(brew::parse_ignore "${global_ignore}" global)" || return 1
  ignore_local="$(brew::parse_ignore "${local_ignore}" local)" || return 1
  include_declared="$(brew::_include_declared "${ignore_global}" "${ignore_local}")" || return 1
  tap_info="$(brew::_tap_info_map "${inventory}")" || return 1
  tap_casks="$(brew::_tap_casks_on_disk "${inventory}")" || return 1
  trusted="$(brew::_trusted_taps "${global_brewfile}" "${local_brewfile}")" || return 1
  trusted_items="$(brew::_trusted_items)" || return 1
  if [[ -n "${previous}" && -f "${previous}" ]]; then
    previous_json="$(jq -c 'if type == "array" then map(strings) else [] end' "${previous}")" || return 1
  fi
  if [[ ! -f "${inventory}" || ! -f "${info}" ]]; then
    log::err "inventory or info file missing | inventory='${inventory}' info='${info}'"
    return 1
  fi
  jq -n -c --slurpfile inventory "${inventory}" \
    --slurpfile alias_map <(print -r -- "${alias_map}") \
    --argjson declared_global "${declared_global}" --argjson declared_local "${declared_local}" \
    --argjson ignore_global "${ignore_global}" --argjson ignore_local "${ignore_local}" \
    --argjson include_declared "${include_declared}" --argjson tap_info "${tap_info}" \
    --argjson tap_casks_on_disk "${tap_casks}" --argjson trusted_taps "${trusted}" \
    --argjson trusted_items "${trusted_items}" --argjson previous_undeclared "${previous_json}" '
    {inventory: $inventory[0], alias_map: $alias_map[0],
     declared: {global: $declared_global, local: $declared_local},
     ignore: {global: $ignore_global, local: $ignore_local},
     include_declared: $include_declared, tap_info: $tap_info, tap_casks_on_disk: $tap_casks_on_disk,
     trusted_taps: $trusted_taps, trusted_items: $trusted_items, previous_undeclared: $previous_undeclared}' \
    | jq -c -f "${BREW_LIB_DIR}/brew_classify.jq"
}

# ["<kind>/<name>", ...] from the previous verify's last_result.json; [] when there is none.
brew::previous_undeclared() {
  if [[ -f "${LAST_RESULT_FILE}" ]]; then
    jq -c '(.brew_undeclared // []) | map(strings)' "${LAST_RESULT_FILE}" 2>/dev/null && return 0
  fi
  print -r -- '[]'
}

# The verdict helpers run inside a step subprocess: common.zsh provides verdict(), the runner
# exports RUN_DIR and STEP.
brew::_require_step_context() {
  if (( ! ${+functions[verdict]} )); then
    log::err "verdict() undefined; source lib/common.zsh first"
    return 1
  fi
  if [[ -z "${RUN_DIR:-}" || ! -d "${RUN_DIR}" ]]; then
    log::err "RUN_DIR unset or missing | run_dir='${RUN_DIR:-}'"
    return 1
  fi
}

# Declared sets are identical for every step of one run; brew_pkgs computes them first.
brew::_declared_file() {
  local tier="${1}" brewfile="${2}"
  local out="${RUN_DIR}/declared.${tier}.json"
  if [[ ! -s "${out}" ]]; then
    brew::declared "${brewfile}" > "${out}" || return 1
  fi
  print -r -- "${out}"
}

brew::_brew_missing_detail() {
  local probed="${NEW_MACHINE_BREW}"
  if [[ -z "${probed}" ]]; then
    local prefix
    for prefix in ${=NEW_MACHINE_BREW_PREFIXES}; do
      probed+="${probed:+ }${prefix}/bin/brew"
    done
  fi
  print -r -- "brew not found at ${probed:-PATH}"
}

# check::brew_pkgs body. Merges the tiers, runs `brew bundle check` against the merged file,
# and turns the parse into the verdict (§2.5). Busy brew and unparsed output are errors.
brew::check_pkgs_verdict() {
  brew::_require_step_context || return 1
  if brew::is_busy; then
    verdict error brew_busy -d "brew busy | pids=$(brew::busy_pids)"
    return 0
  fi
  local brew
  if ! brew="$(brew::bin)"; then
    verdict error brew_missing -d "$(brew::_brew_missing_detail)"
    return 0
  fi
  local global local_file
  global="$(brew::global_brewfile)"
  local_file="$(brew::local_brewfile)"
  local merged="${RUN_DIR}/Brewfile.merged" out="${RUN_DIR}/bundle_check.out"
  if ! brewfile::merge "${merged}" "${global}" "${local_file}"; then
    verdict error brewfile_missing -d "global Brewfile not found at ${global}"
    return 0
  fi

  local rc=0
  "${brew}" bundle check --no-upgrade --verbose --file="${merged}" > "${out}" 2>&1 || rc=$?
  print -r -- "${rc}" > "${RUN_DIR}/bundle_check.rc"
  log::info "brew bundle check | rc=${rc} out='${out}'"

  local declared_global=/dev/null declared_local=/dev/null
  if (( rc != 0 )); then
    declared_global="$(brew::_declared_file global "${global}")" || declared_global=/dev/null
    declared_local="$(brew::_declared_file local "${local_file}")" || declared_local=/dev/null
  fi
  local parsed
  if ! parsed="$(brew::parse_bundle_check "${out}" "${rc}" "${declared_global}" "${declared_local}")"; then
    verdict error bundle_check_unparsed -d "could not parse ${out}"
    return 0
  fi
  local items_file="${RUN_DIR}/brew_pkgs.items.json"
  jq -c '.items' <<< "${parsed}" > "${items_file}"

  local n_error n_unparsed n_conflict n_missing n_tap
  n_error="$(jq -r '.error_lines | length' <<< "${parsed}")"
  n_unparsed="$(jq -r '.unparsed_lines | length' <<< "${parsed}")"
  n_conflict="$(jq -r '[.items[] | select(.problem == "conflict")] | length' <<< "${parsed}")"
  n_missing="$(jq -r '[.items[] | select(.problem != "conflict" and .kind != "tap")] | length' <<< "${parsed}")"
  n_tap="$(jq -r '[.items[] | select(.problem != "conflict" and .kind == "tap")] | length' <<< "${parsed}")"

  if (( rc >= 2 || n_error > 0 || n_unparsed > 0 )); then
    local first
    first="$(jq -r '(.error_lines + .unparsed_lines)[0] // ""' <<< "${parsed}")"
    if [[ -n "${first}" ]]; then
      verdict error bundle_check_unparsed -d "bundle check printed an unparsed line: ${first}"
    else
      verdict error bundle_check_unparsed -d "bundle check exited ${rc} without naming an unmet item"
    fi
    return 0
  fi
  if (( n_conflict > 0 )); then
    # Installing would unlink a formula to satisfy the other declaration; a human fixes the Brewfiles.
    verdict fail brewfile_conflict -m \
      -d "$(nm::plural "${n_conflict}" 'declared formula conflicts' 'declared formulae conflict') with another declaration (needs to be unlinked)" \
      -f "new-machine brew triage" -i "${items_file}"
    return 0
  fi
  if (( n_missing > 0 )); then
    local detail
    detail="$(nm::plural "${n_missing}" 'declared item' 'declared items') not installed"
    if (( n_tap > 0 )); then
      detail+="; $(nm::plural "${n_tap}" 'tap' 'taps') not tapped"
    fi
    verdict fail missing -d "${detail}" -f "new-machine apply brew_pkgs" -i "${items_file}"
    return 0
  fi
  if (( n_tap > 0 )); then
    verdict warn missing_tap -a \
      -d "$(nm::plural "${n_tap}" 'declared tap' 'declared taps') not tapped" \
      -f "new-machine apply brew_pkgs" -i "${items_file}"
    return 0
  fi
  if (( rc == 0 )); then
    verdict ok satisfied -d "every declared item is installed"
    return 0
  fi
  verdict error bundle_check_unparsed -d "bundle check exited 1 without naming an unmet item"
}

# apply::brew_pkgs body: the one install, from the same merged file the check read. Runs with
# HOMEBREW_NO_AUTO_UPDATE unset because setup wants fresh metadata; nothing else ever does.
brew::apply_pkgs() {
  if (( ! ${+functions[run_cmd_mutating]} )); then
    log::err "run_cmd_mutating undefined; source lib/common.zsh first"
    return 1
  fi
  local merged="${RUN_DIR:?brew::apply_pkgs: RUN_DIR required}/Brewfile.merged"
  if [[ ! -f "${merged}" ]]; then
    brewfile::merge "${merged}" "$(brew::global_brewfile)" "$(brew::local_brewfile)" || return 1
  fi
  ( unset HOMEBREW_NO_AUTO_UPDATE; run_cmd_mutating brew bundle install --no-upgrade --file="${merged}" )
}

# check::brew_drift body. Inventory + info + classify into ${RUN_DIR}/drift.json, then the
# verdict (§2.5): anything a human must decide is `fail drift`; bookkeeping notes are a warn.
brew::check_drift_verdict() {
  brew::_require_step_context || return 1
  if brew::is_busy; then
    verdict error brew_busy -d "brew busy | pids=$(brew::busy_pids)"
    return 0
  fi
  if ! brew::bin > /dev/null; then
    verdict error brew_missing -d "$(brew::_brew_missing_detail)"
    return 0
  fi
  local inventory="${RUN_DIR}/inventory.json" info="${RUN_DIR}/info_installed.json"
  local drift="${RUN_DIR}/drift.json" previous="${RUN_DIR}/previous_undeclared.json"
  local snapshot_rc=0
  brew::snapshot "${inventory}" "${info}" || snapshot_rc=$?
  if (( snapshot_rc == 2 )); then
    verdict error inventory_failed -d "receipt inventory failed; see the step log"
    return 0
  elif (( snapshot_rc != 0 )); then
    verdict error info_failed -d "brew info --json=v2 --installed failed; see the step log"
    return 0
  fi
  brew::previous_undeclared > "${previous}"
  local global local_file global_ignore local_ignore
  global="$(brew::global_brewfile)"
  local_file="$(brew::local_brewfile)"
  global_ignore="$(brew::global_ignore)"
  local_ignore="$(brew::local_ignore)"
  if ! brew::classify "${inventory}" "${info}" "${global}" "${local_file}" "${global_ignore}" "${local_ignore}" "${previous}" > "${drift}"; then
    verdict error classify_failed -d "drift classifier failed; see the step log"
    return 0
  fi

  local items_file="${RUN_DIR}/brew_drift.items.json"
  jq -c '[.undeclared[], .orphan_keg[], .declared_orphan[], .duplicate[]]' "${drift}" > "${items_file}"
  local n_fail
  n_fail="$(jq -r 'length' "${items_file}")"
  if (( n_fail > 0 )); then
    local detail
    detail="$(jq -r '"undeclared=\(.undeclared | length) orphaned=\(.orphan_keg | length) declared_orphan=\(.declared_orphan | length) duplicate=\(.duplicate | length)"' "${drift}")"
    verdict fail drift -m -d "${detail}" -f "new-machine brew triage" -i "${items_file}"
    return 0
  fi

  local notes
  notes="$(jq -r '[ (.untrusted_taps[] | "declared tap \(.) lacks trusted: true"),
                    (.unresolvable_ignore[] | "ignore entry \(.kind) \(.name) (\(.tier)) matches nothing installed"),
                    (.include_declared_missing[] | "include-declared path missing: \(.path) (\(.tier))"),
                    (.ambiguous_alias[] | "ambiguous \(.kind) name \(.name): \(.candidates | join(", "))"),
                    (.inventory_note // empty) ] | join("; ")' "${drift}")"
  if [[ -n "${notes}" ]]; then
    local notes_file="${RUN_DIR}/brew_drift.notes.json"
    jq -c '[ (.untrusted_taps[] | {kind: "tap", name: ., problem: "lacks trusted: true"}),
             (.unresolvable_ignore[] | {kind, name, tier, problem: "ignore matches nothing installed"}),
             (.ambiguous_alias[] | {kind, name, problem: "ambiguous alias"}) ]
           | map(select(.kind == "formula" or .kind == "cask" or .kind == "tap" or .kind == "vscode"))' "${drift}" > "${notes_file}"
    verdict warn drift_notes -d "${notes}" -f "new-machine brew triage" -i "${notes_file}"
    return 0
  fi

  local counts
  counts="$(jq -r '"satisfied=\(.counts.satisfied) ignored=\(.counts.ignored)" + (if .vscode_skipped then " vscode=skipped" else "" end)' "${drift}")"
  verdict ok satisfied -d "${counts}"
}
