# Tests for raycast_link.zsh. Fixture bindings, a fixture karabiner.json, and a stub bake stand
# in for the real files; a stub `open` fails the suite if anything is opened.
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

local _dir _bake_hit _saved_path="${PATH}"
_dir="$(mktemp -d /tmp/raycast-link-test.XXXXX)"
_bake_hit="${_dir}/bake.hit"
mkdir -p "${_dir}/bin"
cat > "${_dir}/bin/open" <<'EOF'
#!/usr/bin/env zsh
print -u2 "raycast_link test: open must never be called | args='$*'"; exit 97
EOF
cat > "${_dir}/bin/bake" <<EOF
#!/usr/bin/env zsh
print -r -- "bake \${XDG_CONFIG_HOME:-unset}" >> "${_bake_hit}"
EOF
chmod +x "${_dir}/bin/open" "${_dir}/bin/bake"
export PATH="${_dir}/bin:${PATH}"

cat > "${_dir}/bindings.json" <<'EOF'
[
  {"alias":"clipboard-history","title":"Clipboard History","path":"extensions/raycast/clipboard-history/clipboard-history","chord":"hyper+4"},
  {"alias":"confetti","title":"Confetti","path":"extensions/raycast/raycast/confetti","chord":"cmd+shift+k"}
]
EOF
cat > "${_dir}/karabiner.json" <<'EOF'
{"profiles":[{"complex_modifications":{"rules":[
  {"description":"Clipboard History → raycast://extensions/raycast/clipboard-history/clipboard-history",
   "manipulators":[{"type":"basic",
     "from":{"key_code":"4","modifiers":{"mandatory":["command","option","control","shift"]}},
     "to":[{"shell_command":"open raycast://extensions/raycast/clipboard-history/clipboard-history"}]}]},
  {"description":"unrelated","manipulators":[{"type":"basic","from":{"key_code":"k","modifiers":{"mandatory":["command"]}},"to":[{"shell_command":"open raycast://extensions/raycast/raycast/confetti"}]}]}
]}}]}
EOF
export RAYCAST_LINK_BINDINGS="${_dir}/bindings.json"
export RAYCAST_LINK_KARABINER_JSON="${_dir}/karabiner.json"
export RAYCAST_LINK_BAKE="${_dir}/bin/bake"

# --- chord parsing ---
_t "parse: hyper+4 → key 4, the Hyper set in canonical order" $'4\ncontrol option shift command' "$(raycast_link::parse_chord hyper+4)"
_t "parse: case-insensitive, aliases expand, canonical order" $'k\nshift command' "$(raycast_link::parse_chord Cmd+Shift+K)"
_t "parse: fn and karabiner key names" $'return_or_enter\nfn control option' "$(raycast_link::parse_chord fn+ctrl+opt+return_or_enter)"
_t "parse: duplicate modifiers collapse" $'a\ncommand' "$(raycast_link::parse_chord cmd+command+a)"
local _rc
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
_t "glyph: punctuation key names" "⌃⌥= ⌃⌥- ⌃⌥[ ⌃⌥] ⌃⌥. ⌃⌥, ✦\` ⌘; ⌘' ⌘/ ⌘\\" "$(raycast_link::render_binding ctrl+opt+equal_sign) $(raycast_link::render_binding ctrl+opt+hyphen) $(raycast_link::render_binding ctrl+opt+open_bracket) $(raycast_link::render_binding ctrl+opt+close_bracket) $(raycast_link::render_binding ctrl+opt+period) $(raycast_link::render_binding ctrl+opt+comma) $(raycast_link::render_binding hyper+grave_accent_and_tilde) $(raycast_link::render_binding cmd+semicolon) $(raycast_link::render_binding cmd+quote) $(raycast_link::render_binding cmd+slash) $(raycast_link::render_binding cmd+backslash)"
_t "glyph: symbol aliases normalize to the same glyphs" "⌃⌥= ⌃⌥- ⌃⌥[ ⌃⌥] ⌃⌥. ⌃⌥, ✦\` ⌘; ⌘' ⌘/ ⌘\\ ⌘⏎ ⌘⌫" "$(raycast_link::render_binding 'ctrl+opt+=') $(raycast_link::render_binding 'ctrl+opt+-') $(raycast_link::render_binding 'ctrl+opt+[') $(raycast_link::render_binding 'ctrl+opt+]') $(raycast_link::render_binding 'ctrl+opt+.') $(raycast_link::render_binding 'ctrl+opt+,') $(raycast_link::render_binding 'hyper+`') $(raycast_link::render_binding 'cmd+;') $(raycast_link::render_binding "cmd+'") $(raycast_link::render_binding 'cmd+/') $(raycast_link::render_binding 'cmd+\') $(raycast_link::render_binding 'cmd+⏎') $(raycast_link::render_binding 'cmd+⌫')"
_t "parse: symbol alias normalizes to the key name" $'open_bracket\ncontrol option' "$(raycast_link::parse_chord 'ctrl+opt+[')"
_t "parse: single-char key keeps its case-insensitive letter form" $'k\ncommand' "$(raycast_link::parse_chord 'cmd+K')"
_t "glyph: tab" "⌥⇥" "$(raycast_link::render_binding opt+tab)"
_t "glyph: escape" "⌃⎋" "$(raycast_link::render_binding ctrl+escape)"
_t "glyph: backspace" "⌘⌫" "$(raycast_link::render_binding cmd+delete_or_backspace)"
_t "glyph: arrows" "⇧↑⌃↓⌥←⌘→" "$(raycast_link::render_binding shift+up_arrow)$(raycast_link::render_binding ctrl+down_arrow)$(raycast_link::render_binding opt+left_arrow)$(raycast_link::render_binding cmd+right_arrow)"
_t "glyph: digit as-is, no modifiers" "7" "$(raycast_link::render_binding 7)"

# --- widget ---
_t "widget: markdown, brackets wrap the link and are not part of it, no suffix when compiled" \
  "<[Raycast: Clipboard History | key: '✦4'](raycast://extensions/raycast/clipboard-history/clipboard-history)>" \
  "$(raycast_link clipboard-history)"
_t "widget: plain" \
  "<Raycast: Clipboard History | key: '✦4'> raycast://extensions/raycast/clipboard-history/clipboard-history" \
  "$(raycast_link clipboard-history --plain)"
_t "widget: --plain before the alias also works" \
  "<Raycast: Clipboard History | key: '✦4'> raycast://extensions/raycast/clipboard-history/clipboard-history" \
  "$(raycast_link --plain clipboard-history)"
_t "widget: uncompiled entry gets the suffix inside the link text" \
  "<[Raycast: Confetti | key: '⇧⌘K' (not compiled yet)](raycast://extensions/raycast/raycast/confetti)>" \
  "$(raycast_link confetti)"
local _out
_out="$(raycast_link nope 2>&1)"; _rc=$?
_t "widget: unknown alias rc 1" "1" "${_rc}"
_t "widget: unknown alias names the file and the known aliases" "1" "$(print -r -- "${_out}" | grep -c "Unknown alias | alias='nope' file='${_dir}/bindings.json' known='clipboard-history, confetti'")"

# --- list / check ---
_t "list: one line per binding" \
  $'clipboard-history  ✦4  Clipboard History  raycast://extensions/raycast/clipboard-history/clipboard-history\nconfetti  ⇧⌘K  Confetti  raycast://extensions/raycast/raycast/confetti' \
  "$(raycast_link --list)"
_out="$(raycast_link --check 2>/dev/null)"; _rc=$?
_t "check: OK and MISSING per alias" $'OK clipboard-history ✦4\nMISSING confetti ⇧⌘K' "${_out}"
_t "check: rc 1 when any is missing" "1" "${_rc}"
# Same key, different modifiers, must not count as compiled.
jq '.profiles[0].complex_modifications.rules[0].manipulators[0].from.modifiers.mandatory = ["command","option"]' "${_dir}/karabiner.json" > "${_dir}/k2.json"
RAYCAST_LINK_KARABINER_JSON="${_dir}/k2.json" raycast_link --check >/dev/null 2>&1; _rc=$?
_t "check: wrong modifier set is MISSING" "1" "${_rc}"
_t "check: wrong modifier set marks the widget" "1" "$(RAYCAST_LINK_KARABINER_JSON="${_dir}/k2.json" raycast_link clipboard-history | grep -c "key: '✦4' (not compiled yet)\](raycast://.*)>$")"

# --- set ---
: > "${_bake_hit}"
_out="$(raycast_link --set confetti hyper+5 2>&1)"; _rc=$?
_t "set: existing alias rechorded" "hyper+5" "$(jq -r '.[] | select(.alias=="confetti") | .chord' "${_dir}/bindings.json")"
_t "set: existing alias keeps path and title" "extensions/raycast/raycast/confetti Confetti" "$(jq -r '.[] | select(.alias=="confetti") | "\(.path) \(.title)"' "${_dir}/bindings.json")"
_t "set: bake ran once with XDG_CONFIG_HOME" "bake ${XDG_CONFIG_HOME:-${HOME}/.config}" "$(cat "${_bake_hit}")"
_t "set: ends with the check (confetti now ✦5, still uncompiled in the fixture)" "1" "$(print -r -- "${_out}" | grep -c '^MISSING confetti ✦5$')"
: > "${_bake_hit}"
raycast_link --set newone cmd+n >/dev/null 2>&1; _rc=$?
_t "set: new alias without --path/--title rc 1" "1" "${_rc}"
_t "set: refused alias not written" "0" "$(jq '[.[] | select(.alias=="newone")] | length' "${_dir}/bindings.json")"
_t "set: refused alias did not bake" "" "$(cat "${_bake_hit}")"
raycast_link --set newone cmd+n --path extensions/x/y/z --title 'New One' >/dev/null 2>&1
_t "set: new alias appended" '{"alias":"newone","title":"New One","path":"extensions/x/y/z","chord":"cmd+n"}' "$(jq -c '.[] | select(.alias=="newone")' "${_dir}/bindings.json")"
_t "set: still valid JSON with three entries" "3" "$(jq length "${_dir}/bindings.json")"
raycast_link --set confetti 'bogus+z' >/dev/null 2>&1; _rc=$?
_t "set: bad chord rc 1" "1" "${_rc}"
_t "set: bad chord not written" "hyper+5" "$(jq -r '.[] | select(.alias=="confetti") | .chord' "${_dir}/bindings.json")"

# --- missing files ---
RAYCAST_LINK_BINDINGS="${_dir}/nope.json" raycast_link clipboard-history >/dev/null 2>&1; _rc=$?
_t "missing bindings file rc 1" "1" "${_rc}"
RAYCAST_LINK_KARABINER_JSON="${_dir}/nope.json" raycast_link --check >/dev/null 2>&1; _rc=$?
_t "missing karabiner.json: everything MISSING, rc 1" "1" "${_rc}"

unset RAYCAST_LINK_BINDINGS RAYCAST_LINK_KARABINER_JSON RAYCAST_LINK_BAKE
export PATH="${_saved_path}"
rm -rf "${_dir}"

if (( _fail == 0 )); then
  log::info "raycast_link: all ${_pass} passed"
else
  log::err "raycast_link: ${_pass} passed, ${_fail} failed"
  return 1
fi
