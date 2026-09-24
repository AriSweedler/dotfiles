# Tests for raycast_link.zsh. A fixture bindings document (through the RAYCAST_LINK_BINDINGS_CMD
# seam), a fixture karabiner.json, and a temp plist stand in for the real files; a stub `open`
# fails the suite if anything is opened; the real com.raycast.macos is never touched. The last
# section runs the real karabiner.ts generator (read-only) and checks the generated contract.
# Only runs when OTTO_TEST__ZSH_PLUGINS_RAYCAST_LINK=true
[[ "$OTTO_TEST__ZSH_PLUGINS_RAYCAST_LINK" == "true" ]] || return 0

local _pass=0 _fail=0
source "${HOME}/.config/zsh/plugins/log.zsh"
source "${HOME}/.config/zsh/plugins/raycast_link.zsh"

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

local _dir _saved_path="${PATH}" _rc _out
_dir="$(mktemp -d /tmp/raycast-link-test.XXXXX)"
mkdir -p "${_dir}/bin"
cat > "${_dir}/bin/open" <<'EOF'
#!/usr/bin/env zsh
print -u2 "raycast_link test: open must never be called | args='$*'"; exit 97
EOF
chmod +x "${_dir}/bin/open"
export PATH="${_dir}/bin:${PATH}"

# Fixture document in the generator's shape: a direct-only entry, a direct entry with keepFocus,
# and a layer-only entry. Entries are addressed by the path's last segment.
cat > "${_dir}/bindings.json" <<'EOF'
{"$generated":"fixture","bindings":[
  {"path":"extensions/raycast/clipboard-history/clipboard-history","title":"Clipboard History","chords":["hyper+4"],"allowId":"builtin_command_clipboardHistory"},
  {"path":"extensions/raycast/raycast/confetti","title":"Confetti","chords":["hyper+k d"],"allowId":"builtin_command_confetti"},
  {"path":"extensions/raycast/window-management/left-half","title":"Left Half","chords":["ctrl+opt+h"],"keepFocus":true}
]}
EOF
cat > "${_dir}/karabiner.json" <<'EOF'
{"profiles":[{"complex_modifications":{"rules":[
  {"description":"Clipboard History → raycast://extensions/raycast/clipboard-history/clipboard-history",
   "manipulators":[{"type":"basic",
     "from":{"key_code":"4","modifiers":{"mandatory":["command","option","control","shift"]}},
     "to":[{"shell_command":"open raycast://extensions/raycast/clipboard-history/clipboard-history"}]}]},
  {"description":"window-management direct: control+option+h → deeplink: extensions/raycast/window-management/left-half",
   "manipulators":[{"type":"basic",
     "from":{"key_code":"h","modifiers":{"mandatory":["control","option"]}},
     "to":[{"shell_command":"open -g raycast://extensions/raycast/window-management/left-half"}]}]}
]}}]}
EOF
export RAYCAST_LINK_BINDINGS_CMD="cat ${_dir}/bindings.json"
export RAYCAST_LINK_KARABINER_JSON="${_dir}/karabiner.json"
export RAYCAST_LINK_DEFAULTS_DOMAIN="${_dir}/raycast.plist"

# --- chord parsing ---
_t "parse: hyper+4 → key 4, the Hyper set in canonical order" $'4\ncontrol option shift command' "$(raycast_link::parse_chord hyper+4)"
_t "parse: case-insensitive, aliases expand, canonical order" $'k\nshift command' "$(raycast_link::parse_chord Cmd+Shift+K)"
_t "parse: fn and karabiner key names" $'return_or_enter\nfn control option' "$(raycast_link::parse_chord fn+ctrl+opt+return_or_enter)"
_t "parse: duplicate modifiers collapse" $'a\ncommand' "$(raycast_link::parse_chord cmd+command+a)"
_t "parse: symbol alias normalizes to the key name" $'open_bracket\ncontrol option' "$(raycast_link::parse_chord 'ctrl+opt+[')"
raycast_link::parse_chord 'bogus+a' >/dev/null 2>&1; _rc=$?
_t "parse: unknown modifier rc 1" "1" "${_rc}"
raycast_link::parse_chord 'cmd+' >/dev/null 2>&1; _rc=$?
_t "parse: missing key rc 1" "1" "${_rc}"
raycast_link::parse_chord 'cmd+K!' >/dev/null 2>&1; _rc=$?
_t "parse: bad key char rc 1" "1" "${_rc}"

# --- glyph rendering, one case per rule ---
_t "glyph: Hyper set is ✦" "✦4" "$(raycast_link::render_binding hyper+4)"
_t "glyph: three modifiers in macOS order, letter upper-cased" "⌃⌥⇧K" "$(raycast_link::render_binding shift+opt+ctrl+k)"
_t "glyph: shift before command in macOS order, return glyph" "⇧⌘⏎" "$(raycast_link::render_binding cmd+shift+return_or_enter)"
_t "glyph: Hyper plus fn is not ✦" "fn⌃⌥⇧⌘A" "$(raycast_link::render_binding hyper+fn+a)"
_t "glyph: caps_lock" "⇪A" "$(raycast_link::render_binding caps_lock+a)"
_t "glyph: fn spelled out, f-keys as-is" "fnf1" "$(raycast_link::render_binding fn+f1)"
_t "glyph: f12 as-is" "⌘f12" "$(raycast_link::render_binding cmd+f12)"
_t "glyph: spacebar renders as Space, Raycast style" "⌃⌘Space" "$(raycast_link::render_binding ctrl+cmd+spacebar)"
_t "glyph: space alias" "⌘Space" "$(raycast_link::render_binding cmd+space)"
_t "glyph: tab" "⌥⇥" "$(raycast_link::render_binding opt+tab)"
_t "glyph: escape" "⌃⎋" "$(raycast_link::render_binding ctrl+escape)"
_t "glyph: backspace" "⌘⌫" "$(raycast_link::render_binding cmd+delete_or_backspace)"
_t "glyph: arrows" "⇧↑⌃↓⌥←⌘→" "$(raycast_link::render_binding shift+up_arrow)$(raycast_link::render_binding ctrl+down_arrow)$(raycast_link::render_binding opt+left_arrow)$(raycast_link::render_binding cmd+right_arrow)"
_t "glyph: digit as-is, no modifiers" "7" "$(raycast_link::render_binding 7)"
_t "glyph: punctuation key names" "⌃⌥= ⌃⌥- ⌃⌥[ ⌃⌥] ⌃⌥. ⌃⌥, ✦\` ⌘; ⌘' ⌘/ ⌘\\" "$(raycast_link::render_binding ctrl+opt+equal_sign) $(raycast_link::render_binding ctrl+opt+hyphen) $(raycast_link::render_binding ctrl+opt+open_bracket) $(raycast_link::render_binding ctrl+opt+close_bracket) $(raycast_link::render_binding ctrl+opt+period) $(raycast_link::render_binding ctrl+opt+comma) $(raycast_link::render_binding hyper+grave_accent_and_tilde) $(raycast_link::render_binding cmd+semicolon) $(raycast_link::render_binding cmd+quote) $(raycast_link::render_binding cmd+slash) $(raycast_link::render_binding cmd+backslash)"
_t "glyph: symbol aliases normalize to the same glyphs" "⌃⌥= ⌃⌥- ⌃⌥[ ⌃⌥] ⌃⌥. ⌃⌥, ✦\` ⌘; ⌘' ⌘/ ⌘\\ ⌘⏎ ⌘⌫" "$(raycast_link::render_binding 'ctrl+opt+=') $(raycast_link::render_binding 'ctrl+opt+-') $(raycast_link::render_binding 'ctrl+opt+[') $(raycast_link::render_binding 'ctrl+opt+]') $(raycast_link::render_binding 'ctrl+opt+.') $(raycast_link::render_binding 'ctrl+opt+,') $(raycast_link::render_binding 'hyper+`') $(raycast_link::render_binding 'cmd+;') $(raycast_link::render_binding "cmd+'") $(raycast_link::render_binding 'cmd+/') $(raycast_link::render_binding 'cmd+\') $(raycast_link::render_binding 'cmd+⏎') $(raycast_link::render_binding 'cmd+⌫')"
_t "chord: layer chord renders each step, space-joined" "✦K D" "$(raycast_link::render_chord 'hyper+k d')"
_t "chord: layer chord with a symbol key" "✦T ⌫" "$(raycast_link::render_chord 'hyper+t ⌫')"
_t "chord: direct chord unchanged" "⌃⌥H" "$(raycast_link::render_chord 'ctrl+opt+h')"

# --- bindings source ---
raycast_link::load_bindings; _rc=$?
_t "load: seam command loads the document" "0" "${_rc}"
_t "load: entries in document order, addressed by slug" $'clipboard-history\nconfetti\nleft-half' "$(raycast_link::entries | while IFS= read -r e; do raycast_link::slug "${e}"; done)"
RAYCAST_LINK_BINDINGS_CMD="false" raycast_link --list >/dev/null 2>&1; _rc=$?
_t "load: failing seam command rc 1" "1" "${_rc}"
RAYCAST_LINK_BINDINGS_CMD="echo '{\"nope\":1}'" raycast_link --list >/dev/null 2>&1; _rc=$?
_t "load: wrong shape rc 1" "1" "${_rc}"
RAYCAST_LINK_BINDINGS_CMD="" RAYCAST_LINK_KARABINER_TS="${_dir}/no-such-checkout" raycast_link --list >/dev/null 2>&1; _rc=$?
_t "load: unbuilt karabiner.ts rc 1 (fix: run bake)" "1" "${_rc}"

# --- widget ---
_t "widget: markdown, brackets wrap the link, first chord is the key, compiled → no suffix" \
  "<[Raycast: Clipboard History | key: '✦4'](raycast://extensions/raycast/clipboard-history/clipboard-history)>" \
  "$(raycast_link clipboard-history)"
_t "widget: plain" \
  "<Raycast: Clipboard History | key: '✦4'> raycast://extensions/raycast/clipboard-history/clipboard-history" \
  "$(raycast_link clipboard-history --plain)"
_t "widget: --plain before the slug also works" \
  "<Raycast: Clipboard History | key: '✦4'> raycast://extensions/raycast/clipboard-history/clipboard-history" \
  "$(raycast_link --plain clipboard-history)"
_t "widget: addressed by full path too" \
  "<Raycast: Left Half | key: '⌃⌥H'](raycast://extensions/raycast/window-management/left-half)>" \
  "$(raycast_link extensions/raycast/window-management/left-half | sed 's/^<\[/</')"
_t "widget: keepFocus entry compiled with -g is OK" \
  "<[Raycast: Left Half | key: '⌃⌥H'](raycast://extensions/raycast/window-management/left-half)>" \
  "$(raycast_link left-half)"
_t "widget: layer-only entry shows the layer chord, no suffix" \
  "<[Raycast: Confetti | key: '✦K D'](raycast://extensions/raycast/raycast/confetti)>" \
  "$(raycast_link confetti)"
_out="$(raycast_link nope 2>&1)"; _rc=$?
_t "widget: unknown command rc 1" "1" "${_rc}"
_t "widget: unknown command names the known slugs and the source" "1" "$(print -r -- "${_out}" | grep -c "Unknown command | selector='nope' known='clipboard-history, confetti, left-half' source='karabiner.ts/src")"

# --- list / check ---
_t "list: one line per binding: slug, chords, title, deeplink" \
  $'clipboard-history  ✦4  Clipboard History  raycast://extensions/raycast/clipboard-history/clipboard-history\nconfetti  ✦K D  Confetti  raycast://extensions/raycast/raycast/confetti\nleft-half  ⌃⌥H  Left Half  raycast://extensions/raycast/window-management/left-half' \
  "$(raycast_link --list)"
_out="$(raycast_link --check 2>/dev/null)"; _rc=$?
_t "check: OK for direct chords, layer for layer-only, allow column" \
  $'OK clipboard-history ✦4 NOT-ALLOWED\nlayer confetti ✦K D NOT-ALLOWED\nOK left-half ⌃⌥H no-allow-id' "${_out}"
_t "check: rc 0 when nothing is MISSING (layer and allow state do not fail)" "0" "${_rc}"
jq '.profiles[0].complex_modifications.rules[1].manipulators[0].to[0].shell_command = "open raycast://extensions/raycast/window-management/left-half"' "${_dir}/karabiner.json" > "${_dir}/k3.json"
_t "check: keepFocus entry compiled without -g is MISSING" "1" "$(RAYCAST_LINK_KARABINER_JSON="${_dir}/k3.json" raycast_link --check 2>/dev/null | grep -c '^MISSING left-half ⌃⌥H no-allow-id$')"
RAYCAST_LINK_KARABINER_JSON="${_dir}/k3.json" raycast_link --check >/dev/null 2>&1; _rc=$?
_t "check: rc 1 on a MISSING" "1" "${_rc}"
jq '.profiles[0].complex_modifications.rules[0].manipulators[0].from.modifiers.mandatory = ["command","option"]' "${_dir}/karabiner.json" > "${_dir}/k2.json"
_t "check: wrong modifier set is MISSING and marks the widget" "1" "$(RAYCAST_LINK_KARABINER_JSON="${_dir}/k2.json" raycast_link clipboard-history | grep -c "key: '✦4' (not compiled yet)\](raycast://.*)>$")"
RAYCAST_LINK_KARABINER_JSON="${_dir}/nope.json" raycast_link --check >/dev/null 2>&1; _rc=$?
_t "check: missing karabiner.json makes direct chords MISSING, rc 1" "1" "${_rc}"

# --- removed modes ---
raycast_link --set confetti hyper+5 >/dev/null 2>&1; _rc=$?
_t "--set is gone: unknown flag rc 1" "1" "${_rc}"
raycast_link --keep-focus >/dev/null 2>&1; _rc=$?
_t "--keep-focus is gone: unknown flag rc 1" "1" "${_rc}"

# --- allow-list (temp plist) ---
_t "allowed_ids: empty domain reads as no ids, rc 0" "" "$(raycast_link::allowed_ids)"
defaults write "${RAYCAST_LINK_DEFAULTS_DOMAIN}" alwaysAllowCommandDeeplinking -dict-add builtin_command_clipboardHistory -bool true
_t "allowed_ids: parses the defaults read dict" "builtin_command_clipboardHistory" "$(raycast_link::allowed_ids)"
_out="$(raycast_link --allow --dry-run 2>/dev/null)"; _rc=$?
_t "allow --dry-run: reports what it would add, writes nothing" $'dry_run=1\nwould_add=1\nalready=1\nno_allow_id=1\nwould_add_aliases=confetti\nwould_add_ids=builtin_command_confetti\nno_allow_id_aliases=left-half' "${_out}"
_t "allow --dry-run: plist unchanged" "builtin_command_clipboardHistory" "$(raycast_link::allowed_ids)"
_out="$(raycast_link --allow 2>/dev/null)"; _rc=$?
_t "allow: writes only the missing id" $'added=1\nalready=1\nno_allow_id=1\nadded_aliases=confetti\nno_allow_id_aliases=left-half' "${_out}"
_t "allow: rc 0" "0" "${_rc}"
_t "allow: plist now holds both ids" $'builtin_command_clipboardHistory\nbuiltin_command_confetti' "$(raycast_link::allowed_ids | sort)"
_out="$(raycast_link --allow 2>/dev/null)"; _rc=$?
_t "allow: second run adds nothing" $'added=0\nalready=2\nno_allow_id=1\nadded_aliases=\nno_allow_id_aliases=left-half' "${_out}"
_t "check: allow column after --allow" \
  $'OK clipboard-history ✦4 allowed\nlayer confetti ✦K D allowed\nOK left-half ⌃⌥H no-allow-id' \
  "$(raycast_link --check 2>/dev/null)"

# --- generated contract: the real karabiner.ts generator, read-only ---
local _kts="${XDG_CONFIG_HOME:-${HOME}/.config}/karabiner/karabiner.ts"
if [[ -x "${_kts}/node_modules/.bin/tsx" ]]; then
  local _gen
  _gen="$(RAYCAST_LINK_BINDINGS_CMD="" RAYCAST_LINK_KARABINER_TS="${_kts}" zsh -c 'source "${HOME}/.config/zsh/plugins/raycast_link.zsh"; raycast_link::load_bindings && print -r -- "${RAYCAST_LINK_BINDINGS_CACHE}"')"
  _t "generated: parses, has a bindings array, no alias field" "true" "$(print -r -- "${_gen}" | jq '(.bindings | type == "array") and ([.bindings[] | has("alias")] | any | not)')"
  _t "generated: 34 entries (26 window management + 6 shortcuts + confetti + typing practice)" "34" "$(print -r -- "${_gen}" | jq '.bindings | length')"
  _t "generated: paths unique and sorted, slugs unique" "true" "$(print -r -- "${_gen}" | jq '([.bindings[].path] | (length == (unique | length)) and (. == sort)) and ([.bindings[].path | split("/") | last] | length == (unique | length))')"
  _t "generated: every wm entry has keepFocus, an allowId, and exactly one direct ⌃⌥ chord (no layer)" "26" "$(print -r -- "${_gen}" | jq '[.bindings[] | select(.path | startswith("extensions/raycast/window-management/")) | select(.keepFocus == true and (.allowId | startswith("builtin_command_windowManagement")) and (.chords | length == 1) and (.chords[0] | startswith("ctrl+opt+")))] | length')"
  _t "generated: no hyper+w chord anywhere" "0" "$(print -r -- "${_gen}" | jq '[.bindings[].chords[] | select(startswith("hyper+w "))] | length')"
  _t "generated: sixths on a s d / z x v, c stays Center" $'bottom-center-sixth ctrl+opt+x\nbottom-left-sixth ctrl+opt+z\nbottom-right-sixth ctrl+opt+v\ncenter ctrl+opt+c\ntop-center-sixth ctrl+opt+s\ntop-left-sixth ctrl+opt+a\ntop-right-sixth ctrl+opt+d' "$(print -r -- "${_gen}" | jq -r '.bindings[] | (.path | split("/") | last) as $s | select(($s | endswith("-sixth")) or $s == "center") | "\($s) \(.chords[0])"')"
  _t "generated: shortcut chords canonical (snippets uses the key name)" "hyper+grave_accent_and_tilde" "$(print -r -- "${_gen}" | jq -r '.bindings[] | select(.path | endswith("/search-snippets")) | .chords[0]')"
  _t "generated: layer-only deeplinks carry their layer chord" $'hyper+k d\nhyper+t r' "$(print -r -- "${_gen}" | jq -r '.bindings[] | select((.path | endswith("/confetti")) or (.path | endswith("/start-typing-practice"))) | .chords[0]')"
  _t "generated: the committed artifact matches the generator" "same" "$(diff <(print -r -- "${_gen}" | jq -S .) <(jq -S . "${_kts}/src/raycast_bindings.json") >/dev/null && echo same || echo differs)"
else
  log::warn "raycast_link: karabiner.ts not built, skipping the generated-contract checks | tsx='${_kts}/node_modules/.bin/tsx'"
fi

unset RAYCAST_LINK_BINDINGS_CMD RAYCAST_LINK_KARABINER_JSON RAYCAST_LINK_DEFAULTS_DOMAIN
RAYCAST_LINK_BINDINGS_CACHE="" RAYCAST_LINK_BINDINGS_CACHE_KEY=""
export PATH="${_saved_path}"
rm -rf "${_dir}"

if (( _fail == 0 )); then
  log::info "raycast_link: all ${_pass} passed"
else
  log::err "raycast_link: ${_pass} passed, ${_fail} failed"
  return 1
fi
