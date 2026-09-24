# Tests for raycast_snippets.zsh. Two fixture tier dirs (RAYCAST_SNIPPETS_DIRS), a temp manifest,
# and a stub `open` that records the deeplink stand in for the real ones; nothing reaches Raycast
# and the real tiers and manifest are never touched. Only runs when
# OTTO_TEST__ZSH_PLUGINS_RAYCAST_SNIPPETS=true
[[ "$OTTO_TEST__ZSH_PLUGINS_RAYCAST_SNIPPETS" == "true" ]] || return 0

local _pass=0 _fail=0
source "${HOME}/.config/zsh/plugins/log.zsh"
source "${HOME}/.config/zsh/plugins/raycast_snippets.zsh"

function _t() {
  local name="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    log::info "PASS: ${name}"
    ((_pass++))
  else
    log::err "FAIL: ${name}"
    print "  expected: $(print -r -- "$expected" | cat -v)"
    print "  actual:   $(print -r -- "$actual" | cat -v)"
    ((_fail++))
  fi
}

local _dir _saved_path="${PATH}" _rc _out _log _shared _local
_dir="$(mktemp -d /tmp/raycast-snippets-test.XXXXX)"
_log="${_dir}/open.log"
mkdir -p "${_dir}/bin" "${_dir}/shared" "${_dir}/local"
cat > "${_dir}/bin/open" <<EOF
#!/usr/bin/env zsh
print -r -- "\$1" >> "${_log}"
EOF
chmod +x "${_dir}/bin/open"
export PATH="${_dir}/bin:${PATH}"
export RAYCAST_SNIPPETS_DIRS="${_dir}/shared:${_dir}/local"
export RAYCAST_SNIPPETS_MANIFEST="${_dir}/state/manifest.json"
_shared="${_dir}/shared/snippets.json"
_local="${_dir}/local/snippets.json"
zmodload zsh/stat

# stub open records one URL per call; the snippet payloads are decoded back to JSON for asserting.
function _urls() { cat "${_log}" 2>/dev/null; }
function _payloads() {  # every snippet= param of the last URL, decoded, one JSON per line
  local url enc
  url="$(tail -n 1 "${_log}")"
  url="${url#*\?}"
  for enc in "${(@s:&:)url}"; do
    enc="${enc#snippet=}"
    printf '%b\n' "${enc//\%/\\x}"
  done
}

# ============================================================================
# Single store: everything in the shared file, the local dir empty.
# ============================================================================
cat > "${_shared}" <<'EOF'
[
  {"name":"sig","text":"Ari\nAirtable","keyword":";sig"},
  {"name":"shrug","text":"¯\\_(ツ)_/¯"},
  {"name":"addr","text":"1 Main St","keyword":";addr","id":"ignored-extra-field"}
]
EOF

# --- tiers / normalize / source ---
_t "tiers: first dir is shared, last is local" $'shared\t'"${_dir}/shared"$'\nlocal\t'"${_dir}/local" "$(raycast_snippets::tiers)"
_t "tier_file: local" "${_local}" "$(raycast_snippets::tier_file local)"
raycast_snippets::tier_file bogus >/dev/null 2>&1; _rc=$?
_t "tier_file: unknown label rc 1" "1" "${_rc}"
_t "placeholder_text: names the local file with HOME as ~" "OVERRIDE WITH A ~/x/y/snippets.json file" "$(RAYCAST_SNIPPETS_DIRS="${HOME}/x:${HOME}/x/y" raycast_snippets::placeholder_text)"
_t "normalize: only name/text/keyword, keyword order then keyword-less by name, empty keyword dropped" \
  '[{"name":"addr","text":"1 Main St","keyword":";addr"},{"name":"sig","text":"Ari\nAirtable","keyword":";sig"},{"name":"shrug","text":"¯\\_(ツ)_/¯"}]' \
  "$(raycast_snippets::source | jq -c .entries)"
_t "source: every name is shared" '{"addr":"shared","shrug":"shared","sig":"shared"}' "$(raycast_snippets::source | jq -cS .tiers)"
print -r -- '[{"name":"a","text":1}]' | raycast_snippets::normalize >/dev/null 2>&1; _rc=$?
_t "normalize: text must be a string, rc 1" "1" "${_rc}"
print -r -- '{"name":"a","text":"b"}' | raycast_snippets::normalize >/dev/null 2>&1; _rc=$?
_t "normalize: an object is not an array, rc 1" "1" "${_rc}"
_t "normalize: exact duplicates collapse" "1" "$(print -r -- '[{"name":"a","text":"b"},{"name":"a","text":"b","keyword":""}]' | raycast_snippets::normalize | jq length)"
_t "canonical order: byte order of keywords, ~@ then ~^ then ~~@, keyword-less last by name" '["@@s","~@","~^","~~@","-","-"]' \
  "$(print -r -- '[{"name":"z","text":"t"},{"name":"c","text":"t","keyword":"~^"},{"name":"a","text":"t","keyword":"~~@"},{"name":"y","text":"t"},{"name":"d","text":"t","keyword":"@@s"},{"name":"b","text":"t","keyword":"~@"}]' | raycast_snippets::normalize | jq -c 'map(.keyword // "-")')"

# --- first run: no manifest ---
raycast_snippets --sync --dry-run > /dev/null 2>"${_dir}/nomanifest.err"; _rc=$?
_t "no manifest: sync refuses, rc 1" "1" "${_rc}"
_t "no manifest: says adopt or pull" "1" "$(grep -c 'no manifest; run: ari-raycast snippets pull <raycast export> to adopt Raycast.s current state, or ari-raycast snippets adopt to mark the current files as already imported' "${_dir}/nomanifest.err")"
_t "no manifest: nothing opened" "" "$(_urls)"
_out="$(raycast_snippets --adopt --dry-run 2>/dev/null)"
_t "adopt --dry-run: counts, writes nothing" $'dry_run=1\nwould_adopt=3' "${_out}"
_t "adopt --dry-run: still no manifest" "absent" "$([[ -e "${RAYCAST_SNIPPETS_MANIFEST}" ]] && echo present || echo absent)"
_out="$(raycast_snippets --adopt 2>/dev/null)"; _rc=$?
_t "adopt: rc 0, adopted=3" "adopted=3" "${_out}"
_t "adopt: manifest matches the files" '["addr","shrug","sig"]' "$(jq -c 'keys' "${RAYCAST_SNIPPETS_MANIFEST}")"
_t "adopt: sync is then a no-op" $'snippets: nothing to import | unchanged=3\npending=0' "$(raycast_snippets --sync 2>/dev/null)"
_t "adopt: nothing opened" "" "$(_urls)"
raycast_snippets --reset-manifest >/dev/null 2>&1

# --- sync: all new (empty manifest) ---
_out="$(raycast_snippets --sync --dry-run 2>/dev/null)"; _rc=$?
_t "dry-run: plan lists every entry as new, canonical order" $'new addr\nnew sig\nnew shrug' "$(print -r -- "${_out}" | grep '^new ')"
_t "dry-run: counters" $'dry_run=1\npending=3\nnew=3\nchanged=0\nunchanged=0\nremoved_in_repo=0\nremoved_names=' "$(print -r -- "${_out}" | grep '=')"
_t "dry-run: rc 0" "0" "${_rc}"
_t "dry-run: nothing opened" "" "$(_urls)"
_t "dry-run: manifest untouched (still empty)" "{}" "$(jq -c . "${RAYCAST_SNIPPETS_MANIFEST}")"

_out="$(raycast_snippets --sync 2>/dev/null)"; _rc=$?
_t "sync: rc 0" "0" "${_rc}"
_t "sync: one deeplink for the whole batch" "1" "$(_urls | wc -l | tr -d ' ')"
_t "sync: deeplink is the import URL" "raycast://snippets/import?snippet=" "$(tail -n 1 "${_log}" | cut -c1-34)"
_t "sync: payload is exactly the pending set, canonical entries" \
  '[{"name":"addr","text":"1 Main St","keyword":";addr"},{"name":"sig","text":"Ari\nAirtable","keyword":";sig"},{"name":"shrug","text":"¯\\_(ツ)_/¯"}]' \
  "$(_payloads | jq -sc .)"
_t "sync: result line" "snippets: imported=3 changed=0 removed_in_repo=0" "$(print -r -- "${_out}" | grep '^snippets:')"
_t "sync: manifest records the three names with text and keyword" \
  '{"addr":{"keyword":";addr","text":"1 Main St"},"shrug":{"keyword":null,"text":"¯\\_(ツ)_/¯"},"sig":{"keyword":";sig","text":"Ari\nAirtable"}}' \
  "$(jq -c . "${RAYCAST_SNIPPETS_MANIFEST}")"

# --- sync: nothing to do ---
: > "${_log}"
_out="$(raycast_snippets --sync 2>/dev/null)"; _rc=$?
_t "no-op: says so with the unchanged count" $'snippets: nothing to import | unchanged=3\npending=0' "${_out}"
_t "no-op: rc 0" "0" "${_rc}"
_t "no-op: nothing opened" "" "$(_urls)"
local _mtime_before _mtime_after
_mtime_before="$(zstat +mtime "${RAYCAST_SNIPPETS_MANIFEST}")"
raycast_snippets --sync >/dev/null 2>&1
_mtime_after="$(zstat +mtime "${RAYCAST_SNIPPETS_MANIFEST}")"
_t "no-op: manifest not rewritten" "${_mtime_before}" "${_mtime_after}"

# --- sync: changed, new, removed together ---
cat > "${_shared}" <<'EOF'
[
  {"name":"sig","text":"Ari\nAirtable, Infra","keyword":";sig"},
  {"name":"addr","text":"1 Main St","keyword":";addr"},
  {"name":"greet","text":"Hi!"}
]
EOF
_out="$(raycast_snippets --sync --dry-run 2>/dev/null)"
_t "dry-run: changed, new, removed each classified" $'new greet\nchanged sig' "$(print -r -- "${_out}" | grep -E '^(new|changed) ')"
_t "dry-run: removed name reported, counters" $'pending=2\nnew=1\nchanged=1\nunchanged=1\nremoved_in_repo=1\nremoved_names=shrug' "$(print -r -- "${_out}" | grep -E '^(pending|new|changed|unchanged|removed_in_repo|removed_names)=')"
: > "${_log}"
_out="$(raycast_snippets --sync 2>/dev/null)"; _rc=$?
_t "sync: payload carries only the pending two, new before changed" '["greet","sig"]' "$(_payloads | jq -sc 'map(.name)')"
_t "sync: result and the two delete-by-hand lines" \
  $'snippets: imported=1 changed=1 removed_in_repo=1\nstale in Raycast, delete by hand: sig\nremoved_in_repo, delete by hand in Raycast: shrug' \
  "$(print -r -- "${_out}" | grep -E '^(snippets:|stale|removed_in_repo,)')"
_t "sync: manifest updated for sig and greet, shrug kept until reset" '["addr","greet","shrug","sig"]' "$(jq -c 'keys' "${RAYCAST_SNIPPETS_MANIFEST}")"
_t "sync: manifest holds the new sig text" $'Ari\nAirtable, Infra' "$(jq -r '.sig.text' "${RAYCAST_SNIPPETS_MANIFEST}")"
: > "${_log}"
_out="$(raycast_snippets --sync 2>/dev/null)"
_t "no-op after a change: removed still reported, nothing opened" $'snippets: nothing to import | unchanged=3\nremoved_in_repo, delete by hand in Raycast: shrug\npending=0' "${_out}"
_t "no-op after a change: nothing opened" "" "$(_urls)"

# --- reset-manifest ---
_out="$(raycast_snippets --reset-manifest shrug --dry-run 2>/dev/null)"
_t "reset --dry-run: names what it would forget, writes nothing" $'dry_run=1\nwould_forget=1\nnames=shrug' "${_out}"
_t "reset --dry-run: manifest unchanged" '["addr","greet","shrug","sig"]' "$(jq -c 'keys' "${RAYCAST_SNIPPETS_MANIFEST}")"
_out="$(raycast_snippets --reset-manifest shrug 2>/dev/null)"
_t "reset one name: forgotten" "forgotten=1" "${_out}"
_t "reset one name: gone from the manifest" '["addr","greet","sig"]' "$(jq -c 'keys' "${RAYCAST_SNIPPETS_MANIFEST}")"
_t "reset one name: sync is now a clean no-op" $'snippets: nothing to import | unchanged=3\npending=0' "$(raycast_snippets --sync 2>/dev/null)"
_out="$(raycast_snippets --reset-manifest 2>/dev/null)"
_t "reset all: forgotten=3" "forgotten=3" "${_out}"
_t "reset all: manifest empty" "{}" "$(jq -c . "${RAYCAST_SNIPPETS_MANIFEST}")"
_t "reset all: everything pending again" "pending=3" "$(raycast_snippets --sync --dry-run 2>/dev/null | grep '^pending=')"

# --- duplicate names in one file refused; no file anywhere refused ---
mkdir -p "${_dir}/dupes" "${_dir}/empty"
cat > "${_dir}/dupes/snippets.json" <<'EOF'
[{"name":"a","text":"1"},{"name":"a","text":"2"},{"name":"b","text":"3"}]
EOF
RAYCAST_SNIPPETS_DIRS="${_dir}/dupes:${_dir}/empty" raycast_snippets --sync --dry-run > /dev/null 2>"${_dir}/dupes.err"; _rc=$?
_t "duplicate names: sync refuses, rc 1" "1" "${_rc}"
_t "duplicate names: named with the file" "1" "$(grep -c "Duplicate snippet names in one file | names='a' file='${_dir}/dupes/snippets.json'" "${_dir}/dupes.err")"
RAYCAST_SNIPPETS_DIRS="${_dir}/nope:${_dir}/empty" raycast_snippets --sync >/dev/null 2>"${_dir}/nofile.err"; _rc=$?
_t "no file in any tier: rc 1" "1" "${_rc}"
_t "no file in any tier: names both files" "1" "$(grep -c "No snippets file in any tier | files='${_dir}/nope/snippets.json,${_dir}/empty/snippets.json'" "${_dir}/nofile.err")"

# --- list ---
_t "list: state, tier, name, keyword, first line, canonical order" \
  $'new  shared  addr  ;addr  1 Main St\nnew  shared  sig  ;sig  Ari\nnew  shared  greet  -  Hi!' \
  "$(raycast_snippets --list 2>/dev/null)"

# --- pull: unknown names go to the local tier, absent names leave every tier ---
cat > "${_dir}/export.json" <<'EOF'
[
  {"name":"zeta","text":"old","keyword":"z","id":"x1"},
  {"name":"alpha","text":"A"},
  {"name":"zeta","text":"new","keyword":"z"}
]
EOF
_out="$(raycast_snippets --pull "${_dir}/export.json" --dry-run 2>/dev/null)"
_t "pull --dry-run: counts per tier, last of a name wins, writes nothing" \
  $'dry_run=1\nentries=2\ncollapsed=1\nshared: updated=0 added=0 removed=3 file=changed\nlocal: updated=0 added=2 removed=0 file=created' "${_out}"
_t "pull --dry-run: shared untouched" "3" "$(jq length "${_shared}")"
_t "pull --dry-run: local not created" "absent" "$([[ -e "${_local}" ]] && echo present || echo absent)"
_out="$(raycast_snippets --pull "${_dir}/export.json" 2>/dev/null)"; _rc=$?
_t "pull: rc 0, counts" $'entries=2\ncollapsed=1\nshared: updated=0 added=0 removed=3 file=changed\nlocal: updated=0 added=2 removed=0 file=created' "${_out}"
_t "pull: shared emptied (its names were absent from the export)" "[]" "$(cat "${_shared}")"
_t "pull: local is canonical json-sort output (keys sorted, 2-space, keyword first, last zeta wins)" \
  $'[\n  {\n    "keyword": "z",\n    "name": "zeta",\n    "text": "new"\n  },\n  {\n    "name": "alpha",\n    "text": "A"\n  }\n]' \
  "$(cat "${_local}")"
_t "pull: manifest matches the merged set; unpaired local names warned" \
  $'snippets: nothing to import | unchanged=2\npending=0\nwarn local snippet has no shared placeholder: zeta (z); run ari-raycast snippets fmt\nwarn local snippet has no shared placeholder: alpha (-); run ari-raycast snippets fmt' \
  "$(raycast_snippets --sync 2>/dev/null)"
raycast_snippets --pull "${_dir}/nope.json" >/dev/null 2>&1; _rc=$?
_t "pull: missing export rc 1" "1" "${_rc}"

# --- fmt pairs the local names with shared placeholders ---
_out="$(raycast_snippets --fmt 2>/dev/null)"; _rc=$?
_t "fmt: rc 0, two placeholders added, only shared rewritten" $'snippets: formatted\nshared=changed\nlocal=unchanged\nplaceholders_added=2\nkeywords_fixed=0\nrewritten=1' "${_out}"
_t "fmt: shared holds name+keyword placeholders, no local text" \
  "[{\"keyword\":\"z\",\"name\":\"zeta\",\"text\":\"OVERRIDE WITH A ${_local} file\"},{\"name\":\"alpha\",\"text\":\"OVERRIDE WITH A ${_local} file\"}]" \
  "$(jq -c . "${_shared}")"
_t "fmt: sync is a clean no-op afterwards (merged set unchanged)" $'snippets: nothing to import | unchanged=2\npending=0' "$(raycast_snippets --sync 2>/dev/null)"
_t "list: overrides read local>shared" $'synced  local>shared  zeta  z  new\nsynced  local>shared  alpha  -  A' "$(raycast_snippets --list 2>/dev/null)"

# --- diff ---
cat > "${_dir}/export2.json" <<'EOF'
[{"name":"alpha","text":"A"},{"name":"zeta","text":"other","keyword":"z"},{"name":"omega","text":"O"}]
EOF
_t "diff: changed and only_in_raycast" $'only_in_raycast omega\nchanged zeta' "$(raycast_snippets --diff "${_dir}/export2.json" 2>/dev/null)"
_t "diff: in sync" "in sync" "$(raycast_snippets --diff "${_dir}/export.json" 2>/dev/null)"

# --- url form: array ---
: > "${_log}"; raycast_snippets --reset-manifest >/dev/null 2>&1
RAYCAST_SNIPPETS_URL_FORM=array raycast_snippets --sync >/dev/null 2>&1
_t "array form: one snippet= param holding a JSON array of the batch, canonical order" '["zeta","alpha"]' "$(_payloads | jq -c 'map(.name)')"
_t "array form: exactly one param" "1" "$(_payloads | wc -l | tr -d ' ')"

# ============================================================================
# Two tiers: override by name, collisions, placeholders, fmt, check, move, pull routing.
# ============================================================================
rm -rf "${_dir}/shared" "${_dir}/local" "${_dir}/state"; mkdir -p "${_dir}/shared" "${_dir}/local"
cat > "${_shared}" <<'EOF'
[
  {"name":"pub","text":"public text","keyword":";pub"},
  {"name":"Home","text":"OVERRIDE WITH A ~/elsewhere/snippets.json file","keyword":"~^"},
  {"name":"orphan","text":"OVERRIDE WITH A ~/elsewhere/snippets.json file","keyword":"~o"}
]
EOF
cat > "${_local}" <<'EOF'
[
  {"name":"nokw","text":"plain"},
  {"name":"Home","text":"1 Main","keyword":"~^"},
  {"name":"Phone","text":"555","keyword":"~#"}
]
EOF

# --- merge: local overrides shared by name ---
_t "merge: local Home replaces the shared placeholder, canonical order" '["pub","Phone","Home","orphan","nokw"]' "$(raycast_snippets::source | jq -c '.entries | map(.name)')"
_t "merge: Home carries the local text" "1 Main" "$(raycast_snippets::source | jq -r '.entries[] | select(.name == "Home") | .text')"
_t "merge: tier labels" '{"Home":"local>shared","Phone":"local","nokw":"local","orphan":"shared","pub":"shared"}' "$(raycast_snippets::source | jq -cS .tiers)"
_t "merge: the winner's file" "${_local}" "$(raycast_snippets::source | jq -r '.files.Home')"
_t "list: shared, local, local>shared and placeholder tiers" \
  $'new  shared  pub  ;pub  public text\nnew  local  Phone  ~#  555\nnew  local>shared  Home  ~^  1 Main\nnew  placeholder  orphan  ~o  OVERRIDE WITH A ~/elsewhere/snippets.json file\nnew  local  nokw  -  plain' \
  "$(raycast_snippets --list 2>/dev/null)"

# --- cross-tier keyword collision ---
cp "${_local}" "${_dir}/local.bak"
jq '. + [{"name":"X","text":"x","keyword":";pub"}]' "${_dir}/local.bak" > "${_local}"
raycast_snippets --list >/dev/null 2>"${_dir}/collide.err"; _rc=$?
_t "collision: two names on one keyword refuse, rc 1" "1" "${_rc}"
_t "collision: both names and files are named" "1" "$(grep -c "Two snippets share a keyword | collisions=';pub: pub (${_shared}) and X (${_local})'" "${_dir}/collide.err")"
raycast_snippets --check >/dev/null 2>&1; _rc=$?
_t "collision: check rc 1" "1" "${_rc}"
cp "${_dir}/local.bak" "${_local}"
_t "override: same name and keyword across tiers is not a collision" "0" "$(raycast_snippets --list >/dev/null 2>&1; echo $?)"

# --- check ---
_out="$(raycast_snippets --check 2>/dev/null)"; _rc=$?
_t "check: rc 0 with warns" "0" "${_rc}"
_t "check: active placeholder and unpaired local names" \
  $'warn placeholder active: orphan (~o) fill in '"${_local}"$'\nwarn local snippet has no shared placeholder: Phone (~#); run ari-raycast snippets fmt\nwarn local snippet has no shared placeholder: nokw (-); run ari-raycast snippets fmt\nwarnings=3' \
  "${_out}"

# --- fmt: placeholders, keyword fix, idempotent ---
_mtime_before="$(zstat +mtime "${_shared}")"
_out="$(raycast_snippets --fmt --dry-run 2>/dev/null)"
_t "fmt --dry-run: verdicts and counts, writes nothing" $'dry_run=1\nshared=changed\nlocal=changed\nplaceholders_added=2\nkeywords_fixed=0\nrewritten=2' "${_out}"
_t "fmt --dry-run: shared untouched" "${_mtime_before}" "$(zstat +mtime "${_shared}")"
_t "fmt --dry-run: local untouched (still unsorted)" '["nokw","Home","Phone"]' "$(jq -c 'map(.name)' "${_local}")"
_out="$(raycast_snippets --fmt 2>/dev/null)"; _rc=$?
_t "fmt: rc 0" "0" "${_rc}"
_t "fmt: report" $'snippets: formatted\nshared=changed\nlocal=changed\nplaceholders_added=2\nkeywords_fixed=0\nrewritten=2' "${_out}"
_t "fmt: local only sorted, text untouched" '[{"name":"Phone","keyword":"~#","text":"555"},{"name":"Home","keyword":"~^","text":"1 Main"},{"name":"nokw","keyword":null,"text":"plain"}]' "$(jq -c 'map({name, keyword, text})' "${_local}")"
_t "fmt: shared gained placeholders for Phone and nokw, kept pub and the existing ones, canonical order" \
  "[{\"name\":\"pub\",\"keyword\":\";pub\",\"text\":\"public text\"},{\"name\":\"Phone\",\"keyword\":\"~#\",\"text\":\"OVERRIDE WITH A ${_local} file\"},{\"name\":\"Home\",\"keyword\":\"~^\",\"text\":\"OVERRIDE WITH A ~/elsewhere/snippets.json file\"},{\"name\":\"orphan\",\"keyword\":\"~o\",\"text\":\"OVERRIDE WITH A ~/elsewhere/snippets.json file\"},{\"name\":\"nokw\",\"keyword\":null,\"text\":\"OVERRIDE WITH A ${_local} file\"}]" \
  "$(jq -c 'map({name, keyword, text})' "${_shared}")"
_t "fmt: no local text in shared" "0" "$(grep -c -e '1 Main' -e '555' -e plain "${_shared}")"
_t "fmt: shared keys sorted by json-sort" $'  {\n    "keyword": ";pub",\n    "name": "pub",\n    "text": "public text"\n  },' "$(sed -n '2,6p' "${_shared}")"
_mtime_before="$(zstat +mtime "${_shared}")"
_out="$(raycast_snippets --fmt 2>/dev/null)"
_t "fmt: second run is a no-op and says so" $'snippets: already canonical, nothing to format\nshared=unchanged\nlocal=unchanged\nplaceholders_added=0\nkeywords_fixed=0\nrewritten=0' "${_out}"
_t "fmt: second run leaves the mtime alone" "${_mtime_before}" "$(zstat +mtime "${_shared}")"
_t "check after fmt: only the orphan placeholder remains" $'warn placeholder active: orphan (~o) fill in '"${_local}"$'\nwarnings=1' "$(raycast_snippets --check 2>/dev/null)"
_t "list after fmt: paired local names read local>shared, the orphan stays placeholder" \
  $'new  shared  pub  ;pub  public text\nnew  local>shared  Phone  ~#  555\nnew  local>shared  Home  ~^  1 Main\nnew  placeholder  orphan  ~o  OVERRIDE WITH A ~/elsewhere/snippets.json file\nnew  local>shared  nokw  -  plain' \
  "$(raycast_snippets --list 2>/dev/null)"
# keyword drift: the local Home moves to ~H; fmt follows in the shared placeholder
jq '(.[] | select(.name == "Home")).keyword = "~H"' "${_local}" > "${_dir}/t.json" && mv "${_dir}/t.json" "${_local}"
_out="$(raycast_snippets --fmt 2>/dev/null)"
_t "fmt: keyword drift fixed in the placeholder" $'snippets: formatted\nshared=changed\nlocal=unchanged\nplaceholders_added=0\nkeywords_fixed=1\nrewritten=1' "${_out}"
_t "fmt: the placeholder now carries ~H" "~H" "$(jq -r '.[] | select(.name == "Home") | .keyword' "${_shared}")"
_t "fmt: the placeholder text was not rewritten" "OVERRIDE WITH A ~/elsewhere/snippets.json file" "$(jq -r '.[] | select(.name == "Home") | .text' "${_shared}")"
_t "fmt: idempotent after the fix" "rewritten=0" "$(raycast_snippets --fmt 2>/dev/null | tail -n 1)"

# --- sync imports the merged set and forwards the parity warn ---
raycast_snippets --adopt >/dev/null 2>&1
_t "adopt: manifest holds the merged set, Home with the local text" "1 Main" "$(jq -r '.Home.text' "${RAYCAST_SNIPPETS_MANIFEST}")"
_t "sync: no-op plus the active placeholder as a warn line" $'snippets: nothing to import | unchanged=5\npending=0\nwarn placeholder active: orphan (~o) fill in '"${_local}" "$(raycast_snippets --sync 2>/dev/null)"
_t "sync: nothing opened" "" "$(_urls | grep -c orphan | tr -d ' ' | sed 's/^0$//')"
: > "${_log}"
raycast_snippets --reset-manifest orphan >/dev/null 2>&1
raycast_snippets --sync >/dev/null 2>&1
_t "sync: an unoverridden placeholder is imported as the reminder" '[{"name":"orphan","text":"OVERRIDE WITH A ~/elsewhere/snippets.json file","keyword":"~o"}]' "$(_payloads | jq -sc .)"

# --- move ---
_out="$(raycast_snippets --move Phone --to shared --dry-run 2>/dev/null)"; _rc=$?
_t "move --dry-run: plan, rc 0" $'dry_run=1\nname=Phone\nfrom='"${_local}"$'\nto='"${_shared}"$'\nplaceholder_left=no' "${_out}"
_t "move --dry-run: local untouched" "555" "$(jq -r '.[] | select(.name == "Phone") | .text' "${_local}")"
_out="$(raycast_snippets --move Phone --to shared 2>/dev/null)"; _rc=$?
_t "move local→shared: rc 0" "0" "${_rc}"
_t "move local→shared: the real entry replaces the placeholder" "555" "$(jq -r '.[] | select(.name == "Phone") | .text' "${_shared}")"
_t "move local→shared: gone from local" '["Home","nokw"]' "$(jq -c 'map(.name)' "${_local}")"
_t "move local→shared: exactly one Phone in shared" "1" "$(jq '[.[] | select(.name == "Phone")] | length' "${_shared}")"
_mtime_before="$(zstat +mtime "${RAYCAST_SNIPPETS_MANIFEST}")"
_out="$(raycast_snippets --move Phone --to local 2>/dev/null)"; _rc=$?
_t "move shared→local: rc 0, a placeholder stays behind" $'name=Phone\nfrom='"${_shared}"$'\nto='"${_local}"$'\nplaceholder_left=yes' "${_out}"
_t "move shared→local: local has the text again" "555" "$(jq -r '.[] | select(.name == "Phone") | .text' "${_local}")"
_t "move shared→local: shared keeps a placeholder with the keyword" "~# OVERRIDE WITH A ${_local} file" "$(jq -r '.[] | select(.name == "Phone") | "\(.keyword) \(.text)"' "${_shared}")"
_t "move: manifest untouched (content unchanged)" "${_mtime_before}" "$(zstat +mtime "${RAYCAST_SNIPPETS_MANIFEST}")"
_t "move: sync still a no-op after both moves" "pending=0" "$(raycast_snippets --sync 2>/dev/null | grep '^pending=')"
raycast_snippets --move nope --to local >/dev/null 2>"${_dir}/move1.err"; _rc=$?
_t "move: unknown name refused, rc 1" "1" "${_rc}"
_t "move: unknown name lists the known ones" "1" "$(grep -c "Unknown snippet | name='nope' known='pub, Phone, Home, orphan, nokw'" "${_dir}/move1.err")"
raycast_snippets --move Phone --to local >/dev/null 2>"${_dir}/move2.err"; _rc=$?
_t "move: already local refused, rc 1" "1" "${_rc}"
_t "move: already-there names the tier" "1" "$(grep -c "Already in that tier | name='Phone' tier='local'" "${_dir}/move2.err")"
raycast_snippets --move pub --to shared >/dev/null 2>&1; _rc=$?
_t "move: already shared refused, rc 1" "1" "${_rc}"
raycast_snippets --move pub --to bogus >/dev/null 2>&1; _rc=$?
_t "move: unknown tier refused, rc 1" "1" "${_rc}"
raycast_snippets --move pub >/dev/null 2>&1; _rc=$?
_t "move: without --to rc 1" "1" "${_rc}"
raycast_snippets --list --to local >/dev/null 2>&1; _rc=$?
_t "--to on another mode rc 1" "1" "${_rc}"

# --- pull routing across tiers ---
cat > "${_dir}/export3.json" <<'EOF'
[
  {"name":"pub","text":"public text v2","keyword":";pub"},
  {"name":"Home","text":"2 Main","keyword":"~H"},
  {"name":"Phone","text":"555","keyword":"~#"},
  {"name":"nokw","text":"plain"},
  {"name":"newone","text":"brand new","keyword":"~n"},
  {"name":"ph","text":"OVERRIDE WITH A ~/elsewhere/snippets.json file","keyword":"~p"}
]
EOF
_out="$(raycast_snippets --pull "${_dir}/export3.json" 2>/dev/null)"; _rc=$?
_t "pull: rc 0, per-tier counts" $'entries=6\ncollapsed=0\nshared: updated=1 added=1 removed=1 file=changed\nlocal: updated=1 added=1 removed=0 file=changed' "${_out}"
_t "pull: shared name updated in place" "public text v2" "$(jq -r '.[] | select(.name == "pub") | .text' "${_shared}")"
_t "pull: local name updated in place (winner), shared placeholder untouched" "2 Main|OVERRIDE WITH A ~/elsewhere/snippets.json file" \
  "$(jq -r '.[] | select(.name == "Home") | .text' "${_local}")|$(jq -r '.[] | select(.name == "Home") | .text' "${_shared}")"
_t "pull: unknown real name went to local" "brand new" "$(jq -r '.[] | select(.name == "newone") | .text' "${_local}")"
_t "pull: unknown placeholder went to shared" "~p" "$(jq -r '.[] | select(.name == "ph") | .keyword' "${_shared}")"
_t "pull: absent name left shared (orphan)" "0" "$(jq '[.[] | select(.name == "orphan")] | length' "${_shared}")"
_t "pull: no local text in shared" "0" "$(grep -c -e '2 Main' -e '555' -e 'brand new' -e '"plain"' "${_shared}")"
_t "pull: manifest is the export, so sync is a no-op with parity warns" \
  $'snippets: nothing to import | unchanged=6\npending=0\nwarn placeholder active: ph (~p) fill in '"${_local}"$'\nwarn local snippet has no shared placeholder: newone (~n); run ari-raycast snippets fmt' \
  "$(raycast_snippets --sync 2>/dev/null)"
_t "pull then fmt: newone gets its placeholder" "placeholders_added=1" "$(raycast_snippets --fmt 2>/dev/null | grep '^placeholders_added=')"

# --- seeding a machine with no files at all ---
rm -rf "${_dir}/shared" "${_dir}/local" "${_dir}/state"
_out="$(raycast_snippets --pull "${_dir}/export.json" 2>/dev/null)"; _rc=$?
_t "pull with no files: seeds the local tier, rc 0" $'entries=2\ncollapsed=1\nshared: updated=0 added=0 removed=0 file=absent\nlocal: updated=0 added=2 removed=0 file=created' "${_out}"
_t "pull with no files: shared not created" "absent" "$([[ -e "${_shared}" ]] && echo present || echo absent)"

# --- flags ---
raycast_snippets --bogus >/dev/null 2>&1; _rc=$?
_t "unknown flag rc 1" "1" "${_rc}"
raycast_snippets >/dev/null 2>&1; _rc=$?
_t "no mode rc 1" "1" "${_rc}"
_t "help mentions the two seeding steps" "1" "$(raycast_snippets --help 2>&1 | grep -c 'Export Snippets.*ari-raycast snippets pull')"
_t "help states the one rule" "1" "$(raycast_snippets --help 2>&1 | grep -c 'personal data stays in the local tier; the shared tier is for snippets safe in a public repo')"
_t "help names both tier files" "2" "$(raycast_snippets --help 2>&1 | grep -c -e "shared ${_dir}/shared/snippets.json" -e "local  ${_dir}/local/snippets.json")"

unset RAYCAST_SNIPPETS_DIRS RAYCAST_SNIPPETS_MANIFEST
export PATH="${_saved_path}"
rm -rf "${_dir}"

if (( _fail == 0 )); then
  log::info "raycast_snippets: all ${_pass} passed"
else
  log::err "raycast_snippets: ${_pass} passed, ${_fail} failed"
  return 1
fi
