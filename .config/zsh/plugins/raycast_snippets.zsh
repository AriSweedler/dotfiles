# raycast_snippets — the `snippets` subsystem of `dotfiles raycast` (router: plugin raycast.zsh).
# Raycast Snippets from versioned files, one direction: the files are the source and Raycast the
# mirror. Two tiers, the same split the rest of the dotfiles use, and one rule: personal data
# stays in the local tier; the shared tier is for snippets safe in a public repo.
#   shared  ~/.config/raycast-snippets/snippets.json       git df, public remote
#   local   ~/.local/share/raycast-snippets/snippets.json  git ldf, private remote: addresses, phone
#                                                          numbers, emails
# Every tier's snippets.json (Raycast's import format, an array of {name, text, keyword?}) is
# loaded in RAYCAST_SNIPPETS_DIRS order and merged by name: a later file's entry replaces an
# earlier one, so local always wins over shared. After the merge two names may not share a
# keyword. Canonical order in every file: by keyword in byte order (one prefix's expansions sit
# together), entries without a keyword last by name; keys sorted by json-sort.
#
# Parity across machines without copying private text: for every local snippet the shared file
# carries a PLACEHOLDER of the same name and keyword whose text is "OVERRIDE WITH A <local file>
# file". Here the local entry overrides it; on a machine without the local file the placeholder
# is what Raycast imports, so the keyword expands to the reminder. `fmt` keeps the files in
# canonical order and the placeholders present and on the right keyword; `check` (folded into
# `sync` as `warn` lines) names the active placeholders. Nothing ever writes local text into the
# shared file.
#
# `sync` diffs the merged set against the manifest (what has been imported, name → the canonical
# entry; local state beside the local file) with a few jq calls and nothing else; when nothing
# is new or changed it says so and stops (the do-nothing pass opens nothing and writes nothing).
# Otherwise ONE import deeplink carries every pending snippet, Raycast shows one "Import N
# Snippets" review that Ari confirms with Enter, and the manifest records the batch. Raycast
# neither dedups a re-import nor takes deletions, so the manifest is the only guard, and names
# that changed or left the files are printed for Ari to delete by hand. Without a manifest, sync
# refuses: a first run must say what Raycast already holds, with `adopt` (the files are already
# in Raycast) or `pull <export>` (Raycast's export is the truth).
#
# `pull` updates a known name in place in the tier that wins it and puts an unknown name in the
# LOCAL tier (nothing is guessed public; an unknown placeholder goes to shared); `move <name>
# --to shared|local` relocates one, leaving a placeholder behind when it leaves shared.
#
# Seeding, once, and again after editing snippets inside Raycast:
#   1. Raycast → search "Export Snippets" → save the JSON anywhere
#   2. dotfiles raycast snippets pull <that file>
#
# Function flags: raycast_snippets --sync [--dry-run] | --list | --check | --adopt [--dry-run]
#                 | --pull FILE [--dry-run] | --diff FILE | --move NAME --to TIER [--dry-run]
#                 | --fmt [--dry-run] | --reset-manifest [NAME...] [--dry-run]
# Env: RAYCAST_SNIPPETS_DIRS (colon list; the LAST dir is the local tier, every other is shared,
#      placeholders go to the first), RAYCAST_SNIPPETS_MANIFEST, RAYCAST_SNIPPETS_URL_FORM
#      (params: one `snippet=` per snippet, Raycast's documented form; array: one `snippet=[…]`).

(( ${+functions[log::info]} )) || source "${${(%):-%x}:A:h}/log.zsh"
(( ${+functions[json_sort]} )) || source "${${(%):-%x}:A:h}/json_sort.zsh"

: "${RAYCAST_SNIPPETS_DIRS:=${XDG_CONFIG_HOME:-${HOME}/.config}/raycast-snippets:${HOME}/.local/share/raycast-snippets}"
: "${RAYCAST_SNIPPETS_MANIFEST:=${${(s.:.)RAYCAST_SNIPPETS_DIRS}[-1]}/manifest.json}"
: "${RAYCAST_SNIPPETS_URL_FORM:=params}"
# Guarded so re-sourcing (plugin loader plus the dispatcher) never trips "read-only variable".
(( ${+RAYCAST_SNIPPETS_IMPORT_URL} )) || typeset -gr RAYCAST_SNIPPETS_IMPORT_URL="raycast://snippets/import"
(( ${+RAYCAST_SNIPPETS_BASENAME} )) || typeset -gr RAYCAST_SNIPPETS_BASENAME="snippets.json"
# A shared entry whose text starts with this is a placeholder for a local snippet.
(( ${+RAYCAST_SNIPPETS_PLACEHOLDER_PREFIX} )) || typeset -gr RAYCAST_SNIPPETS_PLACEHOLDER_PREFIX='OVERRIDE WITH A '

# jq: the canonical order of a snippets array: by keyword in byte order, entries without a
# keyword last by name. jq compares strings by codepoint, which is byte order for UTF-8.
(( ${+RAYCAST_SNIPPETS_JQ_ORDER} )) || typeset -gr RAYCAST_SNIPPETS_JQ_ORDER='sort_by([(if (.keyword // "") == "" then 1 else 0 end), (.keyword // ""), .name])'

# jq: an array of snippets → the canonical array. Only name/text/keyword (keyword dropped when
# empty), exact duplicates removed, in canonical order. Errors on anything that is not an array
# of entries with string name and text.
(( ${+RAYCAST_SNIPPETS_JQ_NORMALIZE} )) || typeset -gr RAYCAST_SNIPPETS_JQ_NORMALIZE='
  if type != "array" then error("not a JSON array") else . end
  | map(if (.name | type) != "string" or (.text | type) != "string" then error("entry without string name and text: \(tojson)") else . end)
  | map({name, text} + (if ((.keyword // "") | tostring) != "" then {keyword: (.keyword | tostring)} else {} end))
  | unique_by(.name, .keyword // "", .text)
  | '"${RAYCAST_SNIPPETS_JQ_ORDER}"

# --- tiers ---

# Output: "label\tdir" per tier, in RAYCAST_SNIPPETS_DIRS order; the last dir is `local`.
function raycast_snippets::tiers() {
  local -a dirs=("${(@s.:.)RAYCAST_SNIPPETS_DIRS}")
  local -i i
  for (( i = 1; i <= ${#dirs}; i++ )); do
    if (( i == ${#dirs} )); then print -r -- "local"$'\t'"${dirs[i]}"; else print -r -- "shared"$'\t'"${dirs[i]}"; fi
  done
}

# Output: every tier's snippets file, one per line, in tier order (the last is local).
function raycast_snippets::tier_files() {
  local line
  for line in "${(@f)$(raycast_snippets::tiers)}"; do print -r -- "${line#*$'\t'}/${RAYCAST_SNIPPETS_BASENAME}"; done
}

# Input: tier label. Output: that tier's snippets file; exit 1 for an unknown label.
function raycast_snippets::tier_file() {
  local wanted="${1}" line
  for line in "${(@f)$(raycast_snippets::tiers)}"; do
    [[ "${line%%$'\t'*}" == "${wanted}" ]] && { print -r -- "${line#*$'\t'}/${RAYCAST_SNIPPETS_BASENAME}"; return 0; }
  done
  log::err "Unknown tier | tier='${wanted}' valid='$(raycast_snippets::tiers | cut -f1 | sort -u | paste -sd, -)'"
  return 1
}

# Output: the placeholder text, naming the local file with $HOME as ~ so every machine agrees.
function raycast_snippets::placeholder_text() {
  local file
  file="$(raycast_snippets::tier_file local)" || return 1
  print -r -- "${RAYCAST_SNIPPETS_PLACEHOLDER_PREFIX}${file/#${HOME}/~} file"
}

# --- files ---

# stdin: any snippets array. stdout: the canonical array. Exit 1 with jq's message otherwise.
function raycast_snippets::normalize() {
  local out
  if ! out="$(jq -e "${RAYCAST_SNIPPETS_JQ_NORMALIZE}" 2>&1)"; then
    log::err "Not a snippets array | error='${out}'"
    return 1
  fi
  print -r -- "${out}"
}

# Input: a tier file. stdout: its canonical array; a missing file is []. Exit 1 when invalid or
# when two entries share a name.
function raycast_snippets::read_tier() {
  local file="${1}" canonical dupes
  if [[ ! -e "${file}" ]]; then
    print -r -- "[]"
    return 0
  fi
  canonical="$(raycast_snippets::normalize < "${file}")" || { log::err "Snippets file invalid | file='${file}'"; return 1; }
  dupes="$(print -r -- "${canonical}" | jq -r '[.[].name] | group_by(.) | map(select(length > 1) | .[0]) | join(", ")')"
  if [[ -n "${dupes}" ]]; then
    log::err "Duplicate snippet names in one file | names='${dupes}' file='${file}' fix='rename or merge them; pull keeps the last of a name'"
    return 1
  fi
  print -r -- "${canonical}"
}

# Input: a file, its full text, dry_run. Writes the file atomically when the text differs,
# creating its dir. stdout: created|changed|unchanged (under dry_run, what a write would be).
function raycast_snippets::write_file() {
  local file="${1}" content="${2}" dry_run="${3:-0}" tmp
  if [[ ! -e "${file}" ]]; then
    if (( dry_run )); then
      print -r -- created
      return 0
    fi
    mkdir -p "${file:h}"
    tmp="$(mktemp "${file}.XXXXXX")" || return 1
    print -r -- "${content}" > "${tmp}" && mv "${tmp}" "${file}" || { rm -f "${tmp}"; return 1; }
    print -r -- created
    return 0
  fi
  tmp="$(mktemp "${file}.XXXXXX")" || return 1
  print -r -- "${content}" > "${tmp}"
  if cmp -s "${tmp}" "${file}"; then
    rm -f "${tmp}"
    print -r -- unchanged
    return 0
  fi
  if (( dry_run )); then
    rm -f "${tmp}"
    print -r -- changed
    return 0
  fi
  mv "${tmp}" "${file}" || { rm -f "${tmp}"; return 1; }
  print -r -- changed
}

# Input: a tier file, a snippets array (any shape normalize takes), dry_run. Writes the file in
# canonical form (canonical order, json-sort keys). stdout: created|changed|unchanged.
function raycast_snippets::write_tier() {
  local file="${1}" canonical
  canonical="$(print -r -- "${2}" | raycast_snippets::normalize)" || return 1
  canonical="$(print -r -- "${canonical}" | json_sort)" || return 1
  raycast_snippets::write_file "${file}" "${canonical}" "${3:-0}"
}

# Input: allow_empty (default 0: refuse when no tier has a file, so a wrong RAYCAST_SNIPPETS_DIRS
# cannot read as "everything removed"; pull passes 1 to seed a machine). stdout: one JSON object:
# {entries: [merged, canonical order], tiers: {name: label}, files: {name: file}}. A later tier's
# entry replaces an earlier one of the same name (local wins); the label then reads winner>loser
# (local>shared) and the file is the winner's. Exit 1 on an invalid file, or when two names share
# a keyword after the merge, naming both and their files.
function raycast_snippets::source() {
  local allow_empty="${1:-0}" line label dir file arr merged='{"by_name":{},"tiers":{},"files":{}}' collisions
  local -i present=0
  for line in "${(@f)$(raycast_snippets::tiers)}"; do
    label="${line%%$'\t'*}"; dir="${line#*$'\t'}"; file="${dir}/${RAYCAST_SNIPPETS_BASENAME}"
    [[ -e "${file}" ]] && present+=1
    arr="$(raycast_snippets::read_tier "${file}")" || return 1
    merged="$(jq -cn --argjson m "${merged}" --argjson a "${arr}" --arg label "${label}" --arg file "${file}" '
      reduce $a[] as $e ($m;
        .by_name[$e.name] = $e
        | .tiers[$e.name] = (if .tiers[$e.name] == null then $label else "\($label)>\(.tiers[$e.name])" end)
        | .files[$e.name] = $file)')"
  done
  if (( present == 0 && allow_empty == 0 )); then
    log::err "No snippets file in any tier | files='$(raycast_snippets::tier_files | paste -sd, -)' fix='dotfiles raycast snippets pull <Raycast export>'"
    return 1
  fi
  collisions="$(print -r -- "${merged}" | jq -r '
    . as $m
    | [$m.by_name[] | select(.keyword != null)] | group_by(.keyword) | map(select(length > 1))
    | map("\(.[0].keyword): " + (map("\(.name) (\($m.files[.name]))") | join(" and "))) | join("; ")')"
  if [[ -n "${collisions}" ]]; then
    log::err "Two snippets share a keyword | collisions='${collisions}' fix='change one keyword'"
    return 1
  fi
  print -r -- "${merged}" | jq -c "{entries: ([.by_name[]] | ${RAYCAST_SNIPPETS_JQ_ORDER}), tiers, files}"
}

# stdout: the manifest object; a missing file is {}. Exit 1 when the file is not JSON.
function raycast_snippets::manifest() {
  if [[ -r "${RAYCAST_SNIPPETS_MANIFEST}" ]]; then
    jq -c 'if type == "object" then . else error("manifest is not an object") end' "${RAYCAST_SNIPPETS_MANIFEST}" 2>/dev/null \
      || { log::err "Manifest invalid | file='${RAYCAST_SNIPPETS_MANIFEST}' fix='dotfiles raycast snippets reset-manifest'"; return 1; }
  else
    print -r -- "{}"
  fi
}

# Input: manifest JSON. Writes it canonical, atomically.
function raycast_snippets::write_manifest() {
  local tmp
  mkdir -p "${RAYCAST_SNIPPETS_MANIFEST:h}"
  tmp="$(mktemp "${RAYCAST_SNIPPETS_MANIFEST}.XXXXXX")"
  print -r -- "${1}" | jq -S . > "${tmp}" && mv "${tmp}" "${RAYCAST_SNIPPETS_MANIFEST}"
}

# Input: canonical array. Output: the manifest that says every entry of it is imported.
function raycast_snippets::manifest_of() {
  print -r -- "${1}" | jq -c 'map({(.name): {text, keyword}}) | add // {}'
}

# --- parity ---

# Input: the merged object. Output: one line per finding, without the `warn` prefix: an active
# placeholder (shared, nothing overrides it: Raycast gets the reminder, fill the local file) and
# a local snippet without a shared placeholder (fmt not run since it was added).
function raycast_snippets::parity_lines() {
  local local_file
  local_file="$(raycast_snippets::tier_file local)" || return 1
  print -r -- "${1}" | jq -r --arg prefix "${RAYCAST_SNIPPETS_PLACEHOLDER_PREFIX}" --arg local_file "${local_file}" '
    . as $src
    | ($src.entries[] | select($src.tiers[.name] == "shared" and (.text | startswith($prefix)))
        | "placeholder active: \(.name) (\(.keyword // "-")) fill in \($local_file)"),
      ($src.entries[] | select($src.tiers[.name] == "local")
        | "local snippet has no shared placeholder: \(.name) (\(.keyword // "-")); run dotfiles raycast snippets fmt")'
}

# Input: parity lines. Prints each as `warn <line>` (ari-raycast sync forwards those); nothing
# when none, so the do-nothing pass keeps its two lines.
function raycast_snippets::print_warns() {
  local line
  for line in "$@"; do print -r -- "warn ${line}"; done
}

# --- diff ---

# Input: canonical merged array, manifest object. Output: one JSON object:
#   {new: [entries], changed: [entries], unchanged: N, removed: [names]}
function raycast_snippets::diff_plan() {
  jq -cn --argjson src "${1}" --argjson m "${2}" '
    ($src | map(.name)) as $names
    | {
        new:       [$src[] | select($m[.name] == null)],
        changed:   [$src[] | select($m[.name] != null and $m[.name] != {text, keyword})],
        unchanged: ([$src[] | select($m[.name] == {text, keyword})] | length),
        removed:   [$m | keys[] | select(. as $n | $names | index($n) | not)]
      }'
}

# Input: entries (JSON lines). Output: one import deeplink. `params` repeats snippet=<obj> per
# snippet; `array` sends one snippet=[…]. Both percent-encode the JSON.
function raycast_snippets::import_url() {
  local entry url="${RAYCAST_SNIPPETS_IMPORT_URL}" sep="?"
  if [[ "${RAYCAST_SNIPPETS_URL_FORM}" == array ]]; then
    print -r -- "${url}?snippet=$(printf '%s\n' "$@" | jq -sc . | jq -r '@uri')"
    return
  fi
  for entry in "$@"; do
    url+="${sep}snippet=$(print -r -- "${entry}" | jq -r '@uri')"
    sep="&"
  done
  print -r -- "${url}"
}

# --- modes ---

# --sync [dry_run]: diff the merged set, then one deeplink for everything pending, then the
# manifest. Parity findings follow as `warn` lines.
function raycast_snippets::sync() {
  local dry_run="${1:-0}" merged src manifest plan
  local -a new_names changed_names removed pending warns
  merged="$(raycast_snippets::source)" || return 1
  src="$(print -r -- "${merged}" | jq -c .entries)"
  if [[ ! -e "${RAYCAST_SNIPPETS_MANIFEST}" ]]; then
    log::err "no manifest; run: dotfiles raycast snippets pull <raycast export> to adopt Raycast's current state, or dotfiles raycast snippets adopt to mark the current files as already imported | manifest='${RAYCAST_SNIPPETS_MANIFEST}'"
    return 1
  fi
  manifest="$(raycast_snippets::manifest)" || return 1
  warns=("${(@f)$(raycast_snippets::parity_lines "${merged}")}"); [[ -z "${warns[1]:-}" ]] && warns=()
  plan="$(raycast_snippets::diff_plan "${src}" "${manifest}")"
  new_names=("${(@f)$(print -r -- "${plan}" | jq -r '.new[].name')}"); [[ -z "${new_names[1]:-}" ]] && new_names=()
  changed_names=("${(@f)$(print -r -- "${plan}" | jq -r '.changed[].name')}"); [[ -z "${changed_names[1]:-}" ]] && changed_names=()
  removed=("${(@f)$(print -r -- "${plan}" | jq -r '.removed[]')}"); [[ -z "${removed[1]:-}" ]] && removed=()
  local -i unchanged; unchanged="$(print -r -- "${plan}" | jq '.unchanged')"
  local -i n_pending=$(( ${#new_names} + ${#changed_names} ))
  if (( n_pending == 0 )); then
    print -r -- "snippets: nothing to import | unchanged=${unchanged}"
    (( ${#removed} )) && print -r -- "removed_in_repo, delete by hand in Raycast: ${(j:, :)removed}"
    print -r -- "pending=0"
    raycast_snippets::print_warns "${warns[@]}"
    return 0
  fi
  local name
  for name in "${new_names[@]}"; do print -r -- "new ${name}"; done
  for name in "${changed_names[@]}"; do print -r -- "changed ${name}"; done
  if (( dry_run )); then
    log::info "snippets sync dry run | pending='${n_pending}' new='${#new_names}' changed='${#changed_names}' unchanged='${unchanged}' removed_in_repo='${#removed}' deeplinks='1'"
    cat <<EOF
dry_run=1
pending=${n_pending}
new=${#new_names}
changed=${#changed_names}
unchanged=${unchanged}
removed_in_repo=${#removed}
removed_names=${(j:,:)removed}
EOF
    raycast_snippets::print_warns "${warns[@]}"
    return 0
  fi
  if ! command -v open >/dev/null 2>&1; then
    log::err "open not found; cannot reach Raycast's import deeplink"
    return 1
  fi
  pending=("${(@f)$(print -r -- "${plan}" | jq -c '(.new + .changed)[]')}")
  if ! open "$(raycast_snippets::import_url "${pending[@]}")"; then
    log::err "open failed for the import deeplink | snippets='${n_pending}'"
    return 1
  fi
  log::info "import deeplink opened; confirm the review in Raycast with Enter | snippets='${n_pending}' form='${RAYCAST_SNIPPETS_URL_FORM}'"
  raycast_snippets::write_manifest "$(print -r -- "${manifest}" | jq --argjson add "$(raycast_snippets::manifest_of "$(print -r -- "${plan}" | jq -c '.new + .changed')")" '. + $add')"
  print -r -- "snippets: imported=${#new_names} changed=${#changed_names} removed_in_repo=${#removed}"
  (( ${#changed_names} )) && print -r -- "stale in Raycast, delete by hand: ${(j:, :)changed_names}"
  (( ${#removed} )) && print -r -- "removed_in_repo, delete by hand in Raycast: ${(j:, :)removed}"
  cat <<EOF
imported=${#new_names}
changed=${#changed_names}
unchanged=${unchanged}
removed_in_repo=${#removed}
removed_names=${(j:,:)removed}
EOF
  raycast_snippets::print_warns "${warns[@]}"
}

# --adopt [dry_run]: the merged set is marked as already imported (the manifest is rewritten
# from it), nothing is sent to Raycast. The first run on a machine whose Raycast already holds
# these snippets.
function raycast_snippets::adopt() {
  local dry_run="${1:-0}" src
  local -i count
  src="$(raycast_snippets::source)" || return 1
  src="$(print -r -- "${src}" | jq -c .entries)"
  count="$(print -r -- "${src}" | jq length)"
  if (( dry_run )); then
    log::info "snippets adopt dry run | would_adopt='${count}' manifest='${RAYCAST_SNIPPETS_MANIFEST}'"
    cat <<EOF
dry_run=1
would_adopt=${count}
EOF
    return 0
  fi
  raycast_snippets::write_manifest "$(raycast_snippets::manifest_of "${src}")"
  log::info "snippets adopted; the manifest now says every entry of the files is in Raycast | adopted='${count}' manifest='${RAYCAST_SNIPPETS_MANIFEST}'"
  print -r -- "adopted=${count}"
}

# --list: state (new|changed|synced), tier (shared | local | local>shared for an override |
# placeholder for a shared placeholder nothing overrides), name, keyword, first line of the
# text.
function raycast_snippets::list() {
  local merged manifest
  merged="$(raycast_snippets::source)" || return 1
  manifest="$(raycast_snippets::manifest)" || return 1
  jq -rn --argjson src "${merged}" --argjson m "${manifest}" --arg prefix "${RAYCAST_SNIPPETS_PLACEHOLDER_PREFIX}" '
    $src.entries[]
    | (if $m[.name] == null then "new" elif $m[.name] == {text, keyword} then "synced" else "changed" end) as $state
    | (if $src.tiers[.name] == "shared" and (.text | startswith($prefix)) then "placeholder" else $src.tiers[.name] end) as $tier
    | "\($state)  \($tier)  \(.name)  \(.keyword // "-")  \(.text | split("\n")[0] | .[0:60])"'
}

# --check: parity of the tiers; writes nothing. Exit 1 when two names share a keyword (or a
# file is invalid); otherwise exit 0, with one `warn` line per active placeholder and per local
# snippet without one.
function raycast_snippets::check() {
  local merged
  local -a warns
  merged="$(raycast_snippets::source)" || return 1
  warns=("${(@f)$(raycast_snippets::parity_lines "${merged}")}"); [[ -z "${warns[1]:-}" ]] && warns=()
  if (( ${#warns} == 0 )); then
    print -r -- "snippets: tiers in parity | entries=$(print -r -- "${merged}" | jq '.entries | length')"
  fi
  raycast_snippets::print_warns "${warns[@]}"
  print -r -- "warnings=${#warns}"
}

# --pull FILE [dry_run]: a Raycast export is the truth. A known name is updated in place in the
# tier that wins it (a shared placeholder under a local override is left alone: local text
# never enters shared), an unknown name goes to the LOCAL tier (an unknown placeholder to
# shared), a name absent from the export leaves every tier. The last entry of a name in the
# export wins. Touched files are written canonical, the manifest is rewritten to match. Run fmt
# afterwards for the placeholders of newly added local names.
function raycast_snippets::pull() {
  local export_file="${1}" dry_run="${2:-0}" export_arr merged file tier_arr next verdict is_first is_last
  local -i before after n_added n_removed n_updated i
  local -a files labels report
  if [[ ! -r "${export_file}" ]]; then
    log::err "Export file missing | file='${export_file}'"
    return 1
  fi
  before="$(jq 'if type == "array" then length else 0 end' "${export_file}" 2>/dev/null || echo 0)"
  export_arr="$(jq -e 'if type == "array" then reverse | unique_by(.name) else . end' "${export_file}" 2>/dev/null | raycast_snippets::normalize)" || return 1
  after="$(print -r -- "${export_arr}" | jq length)"
  merged="$(raycast_snippets::source 1)" || return 1
  files=("${(@f)$(raycast_snippets::tier_files)}")
  labels=("${(@f)$(raycast_snippets::tiers | cut -f1)}")
  for (( i = 1; i <= ${#files}; i++ )); do
    file="${files[i]}"
    is_first=0; (( i == 1 )) && is_first=1
    is_last=0; (( i == ${#files} )) && is_last=1
    tier_arr="$(raycast_snippets::read_tier "${file}")" || return 1
    # kept: this tier's names present in the export, with the export's content when this tier
    # wins the name, untouched otherwise; added: export names no tier holds (real text to the
    # last tier, placeholders to the first); removed: this tier's names absent from the export.
    next="$(jq -cn --argjson tier "${tier_arr}" --argjson ex "${export_arr}" --argjson m "${merged}" \
        --arg file "${file}" --arg is_first "${is_first}" --arg is_last "${is_last}" --arg prefix "${RAYCAST_SNIPPETS_PLACEHOLDER_PREFIX}" '
      ($ex | map({(.name): .}) | add // {}) as $e
      | def wins: $m.files[.name] == $file;
        def placeholder: .text | startswith($prefix);
        {
          kept:    [$tier[] | select($e[.name] != null) | if wins then $e[.name] else . end],
          added:   [$ex[] | select($m.tiers[.name] == null)
                    | select((placeholder and $is_first == "1") or ((placeholder | not) and $is_last == "1"))],
          removed: [$tier[] | select($e[.name] == null) | .name],
          updated: [$tier[] | select($e[.name] != null and wins and $e[.name] != .) | .name]
        }
      | .result = ((.kept + .added) | '"${RAYCAST_SNIPPETS_JQ_ORDER}"')')"
    n_added="$(print -r -- "${next}" | jq '.added | length')"
    n_removed="$(print -r -- "${next}" | jq '.removed | length')"
    n_updated="$(print -r -- "${next}" | jq '.updated | length')"
    verdict=absent
    if [[ -e "${file}" ]] || (( n_added > 0 )); then
      verdict="$(raycast_snippets::write_tier "${file}" "$(print -r -- "${next}" | jq -c .result)" "${dry_run}")" || return 1
    fi
    report+=("${labels[i]}: updated=${n_updated} added=${n_added} removed=${n_removed} file=${verdict}")
  done
  if (( dry_run )); then
    log::info "snippets pull dry run | export_entries='${after}' collapsed='$(( before - after ))' ${(j: :)report} would_reset='${RAYCAST_SNIPPETS_MANIFEST}'"
    printf '%s\n' "dry_run=1" "entries=${after}" "collapsed=$(( before - after ))" "${report[@]}"
    return 0
  fi
  raycast_snippets::write_manifest "$(raycast_snippets::manifest_of "${export_arr}")"
  log::info "snippets pulled; run dotfiles raycast snippets fmt for the placeholders of new local names | export_entries='${after}' collapsed='$(( before - after ))' ${(j: :)report} manifest='${RAYCAST_SNIPPETS_MANIFEST}'"
  printf '%s\n' "entries=${after}" "collapsed=$(( before - after ))" "${report[@]}"
}

# --diff FILE: merged set versus a Raycast export, by name; writes nothing.
function raycast_snippets::diff() {
  local export_file="${1}" theirs ours
  [[ -r "${export_file}" ]] || { log::err "Export file missing | file='${export_file}'"; return 1; }
  theirs="$(jq -e 'if type == "array" then reverse | unique_by(.name) else . end' "${export_file}" 2>/dev/null | raycast_snippets::normalize)" || return 1
  ours="$(raycast_snippets::source)" || return 1
  ours="$(print -r -- "${ours}" | jq -c .entries)"
  jq -rn --argjson ours "${ours}" --argjson theirs "${theirs}" '
    ($ours | map({(.name): .}) | add // {}) as $o
    | ($theirs | map({(.name): .}) | add // {}) as $t
    | [ ($o | keys[]) as $n | select($t[$n] == null) | "only_in_repo \($n)" ]
      + [ ($t | keys[]) as $n | select($o[$n] == null) | "only_in_raycast \($n)" ]
      + [ ($o | keys[]) as $n | select($t[$n] != null and ($o[$n] | {text, keyword}) != ($t[$n] | {text, keyword})) | "changed \($n)" ]
    | if length == 0 then "in sync" else .[] end'
}

# --move NAME --to TIER [dry_run]: relocate one snippet from the tier that wins it to another;
# both files rewritten canonical, the manifest untouched (the merged set is unchanged). Into
# shared, the entry replaces its placeholder; out of shared, a placeholder stays behind.
# Refuses an unknown name or a name already won by the target tier.
function raycast_snippets::move() {
  local name="${1}" to="${2}" dry_run="${3:-0}" merged from_file to_file first_file entry from_arr to_arr from_verdict to_verdict placeholder=no
  merged="$(raycast_snippets::source)" || return 1
  from_file="$(print -r -- "${merged}" | jq -r --arg n "${name}" '.files[$n] // empty')"
  if [[ -z "${from_file}" ]]; then
    log::err "Unknown snippet | name='${name}' known='$(print -r -- "${merged}" | jq -r '[.entries[].name] | join(", ")')'"
    return 1
  fi
  to_file="$(raycast_snippets::tier_file "${to}")" || return 1
  if [[ "${from_file}" == "${to_file}" ]]; then
    log::err "Already in that tier | name='${name}' tier='${to}' file='${to_file}'"
    return 1
  fi
  first_file="${${(@f)$(raycast_snippets::tier_files)}[1]}"
  entry="$(print -r -- "${merged}" | jq -c --arg n "${name}" '.entries[] | select(.name == $n)')"
  from_arr="$(raycast_snippets::read_tier "${from_file}")" || return 1
  from_arr="$(print -r -- "${from_arr}" | jq -c --arg n "${name}" 'map(select(.name != $n))')"
  if [[ "${from_file}" == "${first_file}" && "${to_file}" != "${first_file}" ]]; then
    placeholder=yes
    from_arr="$(print -r -- "${from_arr}" | jq -c --argjson e "${entry}" --arg text "$(raycast_snippets::placeholder_text)" '. + [$e | .text = $text]')"
  fi
  to_arr="$(raycast_snippets::read_tier "${to_file}")" || return 1
  to_arr="$(print -r -- "${to_arr}" | jq -c --argjson e "${entry}" 'map(select(.name != $e.name)) + [$e]')"
  if (( dry_run )); then
    log::info "snippets move dry run | name='${name}' from='${from_file}' to='${to_file}' placeholder_left='${placeholder}'"
    printf '%s\n' "dry_run=1" "name=${name}" "from=${from_file}" "to=${to_file}" "placeholder_left=${placeholder}"
    return 0
  fi
  from_verdict="$(raycast_snippets::write_tier "${from_file}" "${from_arr}")" || return 1
  to_verdict="$(raycast_snippets::write_tier "${to_file}" "${to_arr}")" || return 1
  log::info "snippet moved | name='${name}' from='${from_file}' to='${to_file}' from_file='${from_verdict}' to_file='${to_verdict}' placeholder_left='${placeholder}'"
  printf '%s\n' "name=${name}" "from=${from_file}" "to=${to_file}" "placeholder_left=${placeholder}"
}

# --fmt [dry_run]: every tier file that exists is rewritten in canonical form (canonical order,
# json-sort keys); the shared file gains a placeholder for every local name it lacks and a
# placeholder whose keyword drifted from the local entry gets the local keyword. Local text
# never enters shared; the local file is only sorted. A file already canonical is left alone
# (mtime too), so a second run is a no-op. Under dry_run the verdicts say what a write would do.
function raycast_snippets::fmt() {
  local dry_run="${1:-0}" file arr next verdict placeholder local_arr earlier='[]'
  local -a files labels report
  local -i rewritten=0 added=0 fixed=0 i
  raycast_snippets::source >/dev/null || return 1
  files=("${(@f)$(raycast_snippets::tier_files)}")
  labels=("${(@f)$(raycast_snippets::tiers | cut -f1)}")
  placeholder="$(raycast_snippets::placeholder_text)" || return 1
  local_arr="$(raycast_snippets::read_tier "${files[-1]}")" || return 1
  for (( i = 1; i < ${#files}; i++ )); do
    arr="$(raycast_snippets::read_tier "${files[i]}")" || return 1
    earlier="$(jq -cn --argjson e "${earlier}" --argjson a "${arr}" '$e + ($a | map(.name))')"
  done
  for (( i = 1; i <= ${#files}; i++ )); do
    file="${files[i]}"
    arr="$(raycast_snippets::read_tier "${file}")" || return 1
    next="${arr}"
    if (( i < ${#files} )); then
      # A placeholder follows its local entry's keyword; the first shared file takes a
      # placeholder for every local name no shared file holds.
      next="$(jq -cn --argjson a "${arr}" --argjson loc "${local_arr}" --argjson earlier "${earlier}" \
          --arg prefix "${RAYCAST_SNIPPETS_PLACEHOLDER_PREFIX}" --arg text "${placeholder}" --arg is_first "$(( i == 1 ))" '
        ($loc | map({(.name): (.keyword // "")}) | add // {}) as $lk
        | ($a | map(if (.text | startswith($prefix)) and $lk[.name] != null and $lk[.name] != (.keyword // "")
                    then (if $lk[.name] == "" then del(.keyword) else .keyword = $lk[.name] end) | .fixed = true
                    else . end)) as $fixed_arr
        | (if $is_first == "1"
           then [$loc[] | select(.name | IN($earlier[]) | not) | {name, text: $text} + (if .keyword != null then {keyword} else {} end)]
           else [] end) as $new
        | {result: ($fixed_arr | map(del(.fixed))) + $new, fixed: ([$fixed_arr[] | select(.fixed == true)] | length), added: ($new | length)}')"
      fixed+="$(print -r -- "${next}" | jq '.fixed')"
      added+="$(print -r -- "${next}" | jq '.added')"
      next="$(print -r -- "${next}" | jq -c '.result')"
    fi
    if [[ ! -e "${file}" ]] && [[ "${next}" == "[]" ]]; then
      report+=("${labels[i]}=absent")
      continue
    fi
    verdict="$(raycast_snippets::write_tier "${file}" "${next}" "${dry_run}")" || return 1
    [[ "${verdict}" != unchanged ]] && rewritten+=1
    report+=("${labels[i]}=${verdict}")
  done
  if (( dry_run )); then
    log::info "snippets fmt dry run | ${(j: :)report} would_rewrite='${rewritten}' placeholders_added='${added}' keywords_fixed='${fixed}'"
    printf '%s\n' "dry_run=1" "${report[@]}" "placeholders_added=${added}" "keywords_fixed=${fixed}" "rewritten=${rewritten}"
    return 0
  fi
  if (( rewritten == 0 )); then
    print -r -- "snippets: already canonical, nothing to format"
  else
    print -r -- "snippets: formatted"
  fi
  log::info "snippets fmt | ${(j: :)report} rewritten='${rewritten}' placeholders_added='${added}' keywords_fixed='${fixed}'"
  printf '%s\n' "${report[@]}" "placeholders_added=${added}" "keywords_fixed=${fixed}" "rewritten=${rewritten}"
}

# --reset-manifest [dry_run] [NAME...]: forget names (all when none) so the next sync re-imports
# them, e.g. after a cancelled review.
function raycast_snippets::reset_manifest() {
  local dry_run="${1:-0}"; shift
  local manifest name
  manifest="$(raycast_snippets::manifest)" || return 1
  local -a known=("${(@f)$(print -r -- "${manifest}" | jq -r 'keys[]')}"); [[ -z "${known[1]:-}" ]] && known=()
  local -a targets
  if (( $# == 0 )); then targets=("${known[@]}"); else targets=("$@"); fi
  if (( dry_run )); then
    log::info "manifest reset dry run | would_forget='${#targets}' names='${(j:, :)targets}' manifest='${RAYCAST_SNIPPETS_MANIFEST}'"
    cat <<EOF
dry_run=1
would_forget=${#targets}
names=${(j:,:)targets}
EOF
    return 0
  fi
  if (( $# == 0 )); then
    manifest="{}"
  else
    for name in "$@"; do manifest="$(print -r -- "${manifest}" | jq --arg n "${name}" 'del(.[$n])')"; done
  fi
  raycast_snippets::write_manifest "${manifest}"
  log::info "manifest entries forgotten; the next sync re-imports them | forgotten='${#targets}' names='${(j:, :)targets}' manifest='${RAYCAST_SNIPPETS_MANIFEST}'"
  print -r -- "forgotten=${#targets}"
}

function raycast_snippets::help() {
  cat >&2 <<EOF
dotfiles raycast snippets — Raycast Snippets from the versioned files, shared and local

  dotfiles raycast snippets sync [--dry-run]           import what is new or changed since the last sync in ONE deeplink
                                                  (Raycast shows one review; confirm with Enter); nothing pending →
                                                  "nothing to import", no other effect; parity findings follow as warn lines
  dotfiles raycast snippets list                       state (new|changed|synced), tier (shared|local|local>shared|placeholder),
                                                  name, keyword, first line
  dotfiles raycast snippets check                      parity: warn per active placeholder (fill the local file) and per local
                                                  snippet without one (run fmt); exit 1 when two names share a keyword
  dotfiles raycast snippets adopt [--dry-run]          first run on a machine whose Raycast already holds the files' snippets:
                                                  the manifest is written from the merged set, nothing is imported
  dotfiles raycast snippets pull FILE [--dry-run]      a Raycast export is the truth: known names updated in the tier that wins
                                                  them, unknown names added to the LOCAL tier, absent names removed
  dotfiles raycast snippets diff FILE                  merged set versus a Raycast export, by name; writes nothing
  dotfiles raycast snippets move NAME --to shared|local [--dry-run]   relocate one snippet; leaving shared leaves a placeholder
  dotfiles raycast snippets fmt [--dry-run]            rewrite both files canonical (keyword order, json-sort keys); give shared
                                                  a placeholder for every local name and fix drifted placeholder keywords
  dotfiles raycast snippets reset-manifest [NAME...] [--dry-run]   forget names (all when none), e.g. after a cancelled review

  One rule: personal data stays in the local tier; the shared tier is for snippets safe in a public repo.
  Tiers: shared $(raycast_snippets::tier_file shared 2>/dev/null) (git df, public remote)
         local  $(raycast_snippets::tier_file local 2>/dev/null) (git ldf, private remote)
  Merge: files load in that order and a later entry replaces an earlier one of the same name, so local wins.
  Placeholders: for every local snippet, shared holds {name, keyword, text: "$(raycast_snippets::placeholder_text 2>/dev/null)"};
         here local overrides it, on a machine without the local file Raycast imports the reminder. Nothing copies text
         between tiers.
  Order in every file: by keyword (byte order), entries without a keyword last by name; keys sorted by json-sort.
  Raycast cannot be told to delete a snippet: a changed one leaves its old version behind and a removed one stays,
  so both are printed for you to delete by hand. Without a manifest, sync refuses: adopt or pull first.
  Seeding: Raycast → "Export Snippets" → save anywhere → dotfiles raycast snippets pull <that file>
  Manifest: ${RAYCAST_SNIPPETS_MANIFEST} (local, not versioned)
EOF
}

function raycast_snippets() {
  local mode="" dry_run=0 file="" name="" to=""
  local -a names
  while (( $# > 0 )); do case "${1}" in
    -h|--help)        raycast_snippets::help; return 0 ;;
    --dry-run)        dry_run=1; shift ;;
    --sync)           mode=sync; shift ;;
    --adopt)          mode=adopt; shift ;;
    --list)           mode=list; shift ;;
    --check)          mode=check; shift ;;
    --fmt)            mode=fmt; shift ;;
    --pull)           mode=pull; file="${2:?--pull needs a file}"; shift 2 ;;
    --diff)           mode=diff; file="${2:?--diff needs a file}"; shift 2 ;;
    --move)           mode=move; name="${2:?--move needs a snippet name}"; shift 2 ;;
    --to)             to="${2:?--to needs shared or local}"; shift 2 ;;
    --reset-manifest) mode=reset; shift; while (( $# > 0 )) && [[ "${1}" != -* ]]; do names+=("${1}"); shift; done ;;
    -*)               log::err "Unknown flag | flag='${1}'"; raycast_snippets::help; return 1 ;;
    *)                log::err "Unexpected argument | argument='${1}'"; raycast_snippets::help; return 1 ;;
  esac; done
  if [[ "${mode}" == move && -z "${to}" ]]; then
    log::err "--move needs --to shared|local | name='${name}'"
    return 1
  fi
  if [[ "${mode}" != move && -n "${to}" ]]; then
    log::err "--to applies to --move only | mode='${mode}' to='${to}'"
    return 1
  fi
  case "${mode}" in
    sync)  raycast_snippets::sync "${dry_run}" ;;
    adopt) raycast_snippets::adopt "${dry_run}" ;;
    list)  raycast_snippets::list ;;
    check) raycast_snippets::check ;;
    fmt)   raycast_snippets::fmt "${dry_run}" ;;
    pull)  raycast_snippets::pull "${file}" "${dry_run}" ;;
    diff)  raycast_snippets::diff "${file}" ;;
    move)  raycast_snippets::move "${name}" "${to}" "${dry_run}" ;;
    reset) raycast_snippets::reset_manifest "${dry_run}" "${names[@]}" ;;
    *)     raycast_snippets::help; return 1 ;;
  esac
}
