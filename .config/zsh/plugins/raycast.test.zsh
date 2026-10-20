# Tests for raycast.zsh, the router behind `dotfiles raycast`. The subsystem functions are
# replaced by stubs after sourcing, so nothing reaches Raycast, the allow-list, or a manifest;
# the verb is exercised through the dotfiles entrypoint with the same seams the subsystems expose.
# Only runs when OTTO_TEST__ZSH_PLUGINS_RAYCAST=true
[[ "$OTTO_TEST__ZSH_PLUGINS_RAYCAST" == "true" ]] || return 0

local _pass=0 _fail=0
# This file's own tree, so a worktree's copy tests that worktree and not the live checkout.
local _plugins="${${(%):-%x}:A:h}"
local _dotfiles="${_plugins:h:h}/bin/dotfiles"
source "${_plugins}/log.zsh"
source "${_plugins}/raycast.zsh"

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

local _dir _rc _out _calls
_dir="$(mktemp -d /tmp/raycast-test.XXXXX)"
_calls="${_dir}/calls"
mkdir -p "${_dir}/Raycast.app"
export ARI_DOTFILES_RAYCAST_APP="${_dir}/Raycast.app"

# --- every plugin sources twice in one zsh (plugin loader plus dispatcher) without a peep ---
local _p
for _p in json_sort raycast_link raycast_snippets raycast; do
  _out="$(zsh -c "source '${_plugins}/log.zsh'; source '${_plugins}/${_p}.zsh'; source '${_plugins}/${_p}.zsh'" 2>&1)"; _rc=$?
  _t "double source: ${_p}.zsh rc 0" "0" "${_rc}"
  _t "double source: ${_p}.zsh silent (no read-only variable)" "" "${_out}"
done

# Stubs stand in for the subsystems; each records its call and prints a counter.
function raycast_link()     { print -r -- "link $*" >> "${_calls}"; [[ "$*" == *--dry-run* ]] && print "would_add=2" || print "added=2"; }
function raycast_snippets() { print -r -- "snippets $*" >> "${_calls}"; [[ "$*" == *--dry-run* ]] && print "pending=1" || print $'imported=1\nchanged=0'; }

# --- routing ---
: > "${_calls}"
ari_raycast link clipboard-history --plain >/dev/null
_t "route: link <slug> --plain → raycast_link slug --plain" "link clipboard-history --plain" "$(cat "${_calls}")"
: > "${_calls}"; ari_raycast link list >/dev/null;  _t "route: link list" "link --list" "$(cat "${_calls}")"
: > "${_calls}"; ari_raycast link check >/dev/null; _t "route: link check" "link --check" "$(cat "${_calls}")"
: > "${_calls}"; ari_raycast link allow --dry-run >/dev/null; _t "route: link allow --dry-run" "link --allow --dry-run" "$(cat "${_calls}")"
: > "${_calls}"; ari_raycast snippets sync >/dev/null; _t "route: snippets sync" "snippets --sync" "$(cat "${_calls}")"
: > "${_calls}"; ari_raycast snippets pull /tmp/x.json --dry-run >/dev/null; _t "route: snippets pull FILE --dry-run" "snippets --pull /tmp/x.json --dry-run" "$(cat "${_calls}")"
: > "${_calls}"; ari_raycast snippets reset-manifest a b >/dev/null; _t "route: snippets reset-manifest names" "snippets --reset-manifest a b" "$(cat "${_calls}")"
: > "${_calls}"; ari_raycast snippets check >/dev/null; _t "route: snippets check" "snippets --check" "$(cat "${_calls}")"
: > "${_calls}"; ari_raycast snippets fmt --dry-run >/dev/null; _t "route: snippets fmt --dry-run" "snippets --fmt --dry-run" "$(cat "${_calls}")"
: > "${_calls}"; ari_raycast snippets move Phone --to shared >/dev/null; _t "route: snippets move NAME --to TIER" "snippets --move Phone --to shared" "$(cat "${_calls}")"
: > "${_calls}"; ari_raycast snippets edit --shared >/dev/null; _t "route: snippets edit --shared" "snippets --edit --shared" "$(cat "${_calls}")"
ari_raycast bogus >/dev/null 2>&1; _rc=$?
_t "route: unknown subsystem rc 1" "1" "${_rc}"
_out="$(ari_raycast bogus 2>&1)"
_t "route: unknown subsystem names the valid ones" "1" "$(print -r -- "${_out}" | grep -c "Unknown subsystem | subsystem='bogus' valid='link, snippets, sync, edit, undocumented, help'")"
ari_raycast snippets bogus >/dev/null 2>&1; _rc=$?
_t "route: unknown snippets verb rc 1" "1" "${_rc}"

# --- edit and its other spelling ---
: > "${_calls}"; ari_raycast link edit left-half >/dev/null; _t "route: link edit <slug>" "link --edit left-half" "$(cat "${_calls}")"
: > "${_calls}"; ari_raycast link --edit >/dev/null; _t "route: link --edit" "link --edit" "$(cat "${_calls}")"
: > "${_calls}"; ari_raycast snippets --edit --local >/dev/null; _t "route: snippets --edit --local" "snippets --edit --local" "$(cat "${_calls}")"
: > "${_calls}"; ari_raycast edit link left-half >/dev/null; _t "route: edit link <slug>" "link --edit left-half" "$(cat "${_calls}")"
: > "${_calls}"; ari_raycast edit bindings >/dev/null; _t "route: edit bindings is link edit" "link --edit" "$(cat "${_calls}")"
: > "${_calls}"; ari_raycast --edit snippets --shared >/dev/null; _t "route: --edit snippets --shared" "snippets --edit --shared" "$(cat "${_calls}")"
: > "${_calls}"; _out="$(ari_raycast edit 2>&1 </dev/null)"; _rc=$?
_t "edit: no target off a terminal rc 64, nothing opened" "64 " "${_rc} $(cat "${_calls}")"
_t "edit: no target lists the three targets" "3" "$(print -r -- "${_out}" | grep -c -e '^  dotfiles raycast snippets edit --local ' -e '^  dotfiles raycast snippets edit --shared ' -e '^  dotfiles raycast link edit ')"
ari_raycast edit attic >/dev/null 2>&1; _rc=$?
_t "edit: an unknown target rc 64" "64" "${_rc}"
# A chooser stands in for ui::choose; a terminal is faked by running under `script`, which gives
# the function a pty, so the pick routes like the typed form.
function ui::choose() { print -r -- "bindings: karabiner.ts, raycast_shortcuts.ts"; }
: > "${_calls}"
if command -v script >/dev/null 2>&1; then
  script -q /dev/null zsh -c "source '${_plugins}/log.zsh'; source '${_plugins}/raycast.zsh'; function ui::choose() { print -r -- 'bindings: karabiner.ts, raycast_shortcuts.ts'; }; function raycast_link() { print -r -- \"link \$*\" >> '${_calls}'; }; ari_raycast edit" </dev/null >/dev/null 2>&1
  _t "edit: on a terminal the pick routes to its edit" "link --edit" "$(cat "${_calls}")"
fi
unfunction ui::choose

# --- undocumented: every subsystem's findings, as they are, then the total ---
function raycast_link()     { print -r -- "link $*" >> "${_calls}"; print $'binding a | fix=\'dotfiles raycast link edit a\'\nundocumented=1'; }
function raycast_snippets() { print -r -- "snippets $*" >> "${_calls}"; print $'snippet S (local) | fix=\'dotfiles raycast snippets edit --local\'\nundocumented=1'; }
: > "${_calls}"; _out="$(ari_raycast undocumented 2>/dev/null)"; _rc=$?
_t "undocumented: asks each subsystem" $'link --undocumented\nsnippets --undocumented' "$(cat "${_calls}")"
_t "undocumented: the findings then the total, rc 0" $'binding a | fix=\'dotfiles raycast link edit a\'\nsnippet S (local) | fix=\'dotfiles raycast snippets edit --local\'\nundocumented=2\n0' "${_out}"$'\n'"${_rc}"
function raycast_snippets() { return 3; }
_out="$(ari_raycast undocumented 2>/dev/null)"; _rc=$?
_t "undocumented: a subsystem that cannot report makes rc 1, the others still print" $'binding a | fix=\'dotfiles raycast link edit a\'\nundocumented=1\n1' "${_out}"$'\n'"${_rc}"
function raycast_link()     { print -r -- "link $*" >> "${_calls}"; [[ "$*" == *--dry-run* ]] && print "would_add=2" || print "added=2"; }
function raycast_snippets() { print -r -- "snippets $*" >> "${_calls}"; [[ "$*" == *--dry-run* ]] && print "pending=1" || print $'imported=1\nchanged=0'; }

# --- sync ---
: > "${_calls}"
_out="$(ari_raycast sync 2>/dev/null)"; _rc=$?
_t "sync: runs every step in order" $'link --allow\nsnippets --sync' "$(cat "${_calls}")"
_t "sync: one line per step and the total" $'ok link allow | pending=\'2\'\nok snippets sync | pending=\'1\'\ntotal_pending=3' "${_out}"
_t "sync: rc 0" "0" "${_rc}"
: > "${_calls}"
_out="$(ari_raycast sync --dry-run 2>/dev/null)"
_t "sync --dry-run: passes --dry-run through" $'link --allow --dry-run\nsnippets --sync --dry-run' "$(cat "${_calls}")"
_t "sync --dry-run: sums would_add and pending" "total_pending=3" "$(print -r -- "${_out}" | tail -n 1)"
function raycast_snippets() { print -r -- "snippets $*" >> "${_calls}"; print $'snippets: nothing to import | unchanged=5\npending=0\nwarn placeholder active: orphan (~o) fill in /x/snippets.json'; }
_out="$(ari_raycast sync 2>/dev/null)"; _rc=$?
_t "sync: a step's warn line is forwarded with the step name, pending stays 0" \
  $'ok link allow | pending=\'2\'\nok snippets sync | pending=\'0\'\nwarn snippets sync | placeholder active: orphan (~o) fill in /x/snippets.json\ntotal_pending=2' "${_out}"
_t "sync: a warn is not a failure" "0" "${_rc}"
function raycast_snippets() { print -r -- "snippets $*" >> "${_calls}"; print -u2 "boom"; return 7; }
_out="$(ari_raycast sync 2>/dev/null)"; _rc=$?
_t "sync: a failing step is reported and the run continues" "1" "$(print -r -- "${_out}" | grep -c "^FAIL snippets sync | rc='7'")"
_t "sync: a failing step makes rc 1" "1" "${_rc}"
_t "sync: the other step still ran" "1" "$(print -r -- "${_out}" | grep -c "^ok link allow")"
_out="$(ARI_DOTFILES_RAYCAST_APP="${_dir}/nope.app" ari_raycast sync 2>/dev/null)"; _rc=$?
_t "sync: skips when Raycast is not installed" "skip raycast not installed | app='${_dir}/nope.app'" "${_out}"
_t "sync: skip is rc 0" "0" "${_rc}"

# --- the verb, through the real subsystems with their seams ---
function _bin() { "${_dotfiles}" raycast "$@"; }
cat > "${_dir}/bindings.json" <<'EOF'
{"$generated":"fixture","bindings":[{"path":"extensions/raycast/clipboard-history/clipboard-history","title":"Clipboard History","chords":["hyper+4"],"allowId":"builtin_command_clipboardHistory"}]}
EOF
print -r -- '{"profiles":[{"complex_modifications":{"rules":[]}}]}' > "${_dir}/karabiner.json"
_t "bin: link <slug> renders the widget" \
  "<[Raycast: Clipboard History | key: '✦4' (not compiled yet)](raycast://extensions/raycast/clipboard-history/clipboard-history)>" \
  "$(ARI_DOTFILES_RAYCAST_LINK_BINDINGS_CMD="cat ${_dir}/bindings.json" ARI_DOTFILES_RAYCAST_LINK_KARABINER_JSON="${_dir}/karabiner.json" _bin link clipboard-history 2>/dev/null)"
_t "bin: --plain" \
  "<Raycast: Clipboard History | key: '✦4' (not compiled yet)> raycast://extensions/raycast/clipboard-history/clipboard-history" \
  "$(ARI_DOTFILES_RAYCAST_LINK_BINDINGS_CMD="cat ${_dir}/bindings.json" ARI_DOTFILES_RAYCAST_LINK_KARABINER_JSON="${_dir}/karabiner.json" _bin link clipboard-history --plain 2>/dev/null)"
mkdir -p "${_dir}/shared" "${_dir}/local"
print -r -- '[]' > "${_dir}/shared/snippets.json"
local _env=(ARI_DOTFILES_RAYCAST_SNIPPETS_DIRS="${_dir}/shared:${_dir}/local" ARI_DOTFILES_RAYCAST_SNIPPETS_MANIFEST="${_dir}/m.json")
env "${_env[@]}" "${_dotfiles}" raycast snippets sync >/dev/null 2>&1; _rc=$?
_t "bin: snippets sync without a manifest proceeds" "0" "${_rc}"
_t "bin: snippets adopt then sync is a no-op" $'snippets: nothing to import | unchanged=0\npending=0' \
  "$(env "${_env[@]}" "${_dotfiles}" raycast snippets adopt >/dev/null 2>&1; env "${_env[@]}" "${_dotfiles}" raycast snippets sync 2>/dev/null)"
_t "bin: snippets check on empty tiers is in parity" $'snippets: tiers in parity | entries=0\nwarnings=0' "$(env "${_env[@]}" "${_dotfiles}" raycast snippets check 2>/dev/null)"
_t "bin: snippets fmt --dry-run on canonical files" $'dry_run=1\nshared=unchanged\nlocal=absent\nkeywords_fixed=0\nrewritten=0' "$(env "${_env[@]}" "${_dotfiles}" raycast snippets fmt --dry-run 2>/dev/null)"
_bin edit </dev/null >/dev/null 2>&1; _rc=$?; _t "bin: edit with no target off a terminal rc 64" "64" "${_rc}"
_bin --edit </dev/null >/dev/null 2>&1; _rc=$?; _t "bin: --edit is the same" "64" "${_rc}"
_t "bin: undocumented names the fixture binding with its fix" \
  $'binding clipboard-history | fix=\'dotfiles raycast link edit clipboard-history\'\nundocumented=1' \
  "$(env "${_env[@]}" ARI_DOTFILES_RAYCAST_LINK_BINDINGS_CMD="cat ${_dir}/bindings.json" "${_dotfiles}" raycast undocumented 2>/dev/null)"
_t "bin: the raycast help lists edit, --edit, link edit and undocumented" "4" \
  "$("${_dotfiles}" help raycast 2>&1 | grep -c -e '^  dotfiles raycast edit \[link' -e '(also: raycast --edit)' -e '^  dotfiles raycast link edit \[<slug>\]' -e '^  dotfiles raycast undocumented')"
_t "bin: the raycast help lists the --edit flag" "1" "$("${_dotfiles}" help raycast 2>&1 | grep -c '^  --edit ')"
_bin help >/dev/null 2>&1; _rc=$?; _t "bin: help rc 0" "0" "${_rc}"
_t "bin: help lists the subsystems" "1" "$(_bin help 2>&1 | grep -c 'Subsystems:.*link, snippets')"
_t "bin: help names both tier files" "2" "$(_bin help 2>&1 | grep -c -e 'shared  ~/.config/raycast-snippets/snippets.json' -e 'local   ~/.local/share/raycast-snippets/snippets.json')"
_t "bin: help states the one rule" "1" "$(_bin help 2>&1 | grep -c 'personal data stays in the local tier')"
_bin link help >/dev/null 2>&1; _rc=$?; _t "bin: link help rc 0" "0" "${_rc}"
_bin snippets help >/dev/null 2>&1; _rc=$?; _t "bin: snippets help rc 0" "0" "${_rc}"
_t "bin: snippets help covers move and fmt" "2" "$(_bin snippets help 2>&1 | grep -c -e '^  dotfiles raycast snippets move NAME --to shared|local' -e '^  dotfiles raycast snippets fmt \[--dry-run\]')"
_bin bogus >/dev/null 2>&1; _rc=$?; _t "bin: unknown subsystem rc 1" "1" "${_rc}"
_t "bin: unknown subsystem names the valid ones and prints help" "2" "$(_bin bogus 2>&1 | grep -c -e "Unknown subsystem | subsystem='bogus' valid='link, snippets, sync, edit, undocumented, help'" -e 'Usage:' | tr -d ' ')"
: > "${_calls}"; ari_raycast snippets adopt --dry-run >/dev/null; _t "route: snippets adopt --dry-run" "snippets --adopt --dry-run" "$(cat "${_calls}")"
_bin snippets bogus >/dev/null 2>&1; _rc=$?; _t "bin: unknown verb rc 1" "1" "${_rc}"
_t "bin: --dry-run on a read-only verb is the read-only run" "$(_bin link list 2>/dev/null)" "$(_bin link list --dry-run 2>/dev/null)"
_bin snippets pull >/dev/null 2>&1; _rc=$?; _t "bin: pull without FILE rc 1" "1" "${_rc}"
_bin snippets move Phone >/dev/null 2>&1; _rc=$?; _t "bin: move without --to rc 1" "1" "${_rc}"
_bin snippets move Phone --to attic >/dev/null 2>&1; _rc=$?; _t "bin: move to an unknown tier rc 1" "1" "${_rc}"
_bin snippets move --to local >/dev/null 2>&1; _rc=$?; _t "bin: move without NAME rc 1" "1" "${_rc}"
_bin snippets list --to local >/dev/null 2>&1; _rc=$?; _t "bin: --to on another verb rc 1" "1" "${_rc}"
_t "bin: move --dry-run reaches the plugin with --to" "name=nobody" \
  "$(print -r -- '[{"name":"nobody","text":"x"}]' > "${_dir}/local/snippets.json"; env "${_env[@]}" "${_dotfiles}" raycast snippets move nobody --to shared --dry-run 2>/dev/null | grep '^name=')"
_t "bin: sync --dry-run skips without Raycast" "skip raycast not installed | app='${_dir}/nope.app'" "$(ARI_DOTFILES_RAYCAST_APP="${_dir}/nope.app" _bin sync --dry-run 2>/dev/null | grep '^skip')"

unset ARI_DOTFILES_RAYCAST_APP
unfunction raycast_link raycast_snippets _bin
rm -rf "${_dir}"

if (( _fail == 0 )); then
  log::info "raycast: all ${_pass} passed"
else
  log::err "raycast: ${_pass} passed, ${_fail} failed"
  return 1
fi
