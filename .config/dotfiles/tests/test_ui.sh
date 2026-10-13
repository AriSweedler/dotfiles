#!/usr/bin/env bash
# lib/ui.zsh: every plain fallback byte for byte, clip and table, the ARI_DOTFILES_UI seam, and
# no gum ever when not fancy (NO_COLOR, no tty, a step subprocess). A fake gum logs its calls.
set -u
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

world_new

# ui_run [VAR=value…] -- CODE: the kernel sourced in the hermetic env plus VARs, then CODE; OUT, ERR, RC.
# OUT keeps every byte (no $(…) trimming): it is read back from the file with a sentinel.
ui_run() {
  local -a extra=()
  while [[ "$1" != -- ]]; do extra+=("$1"); shift; done
  shift
  hermetic_env
  RC=0
  env -i "${HERMETIC_ENV[@]}" "${extra[@]}" "${FIX}/tools/zsh" -c \
    'for f in "$1"/*.zsh(N); do source "${f}"; done; eval "$2"' _ "${ORIG_CONFIG_DIR}/dotfiles/lib" "$1" \
    > "${FIX}/ui.out" 2> "${FIX}/ui.err" || RC=$?
  OUT="$(cat "${FIX}/ui.out"; printf x)"; OUT="${OUT%x}"
  ERR="$(cat "${FIX}/ui.err")"
}

FAKE_GUM="${FIX}/fakegum"
printf '#!/bin/sh\nprintf "%%s|%%s\\n" "${CLICOLOR_FORCE:-}" "$*" >> "%s/gum.log"\nprintf "GUM\\n"\n' "${FIX}" > "${FAKE_GUM}"
chmod +x "${FAKE_GUM}"
gum_log() { if [[ -f "${FIX}/gum.log" ]]; then cat "${FIX}/gum.log"; fi; }

# ── The probe and the seam ───────────────────────────────────────────────────
ui_run -- 'print -r -- "[${ARI_DOTFILES_GUM}] ${ARI_DOTFILES_UI}"'
assert_eq "the world has no gum; the seam defaults to auto" "[] auto"$'\n' "${OUT}"

fancy_rc() { ui_run "$@" -- 'ui::is_fancy; print -r -- $?'; printf '%s' "${OUT%$'\n'}"; }
assert_eq "auto without a tty is plain, gum or not" 1 "$(fancy_rc ARI_DOTFILES_GUM="${FAKE_GUM}")"
assert_eq "fancy with gum is fancy" 0 "$(fancy_rc ARI_DOTFILES_UI=fancy ARI_DOTFILES_GUM="${FAKE_GUM}")"
assert_eq "fancy without gum is plain" 1 "$(fancy_rc ARI_DOTFILES_UI=fancy)"
assert_eq "fancy with a gum path that is not there is plain" 1 "$(fancy_rc ARI_DOTFILES_UI=fancy ARI_DOTFILES_GUM="${FIX}/nope")"
assert_eq "NO_COLOR=1 beats fancy" 1 "$(fancy_rc ARI_DOTFILES_UI=fancy ARI_DOTFILES_GUM="${FAKE_GUM}" NO_COLOR=1)"
assert_eq "plain is plain" 1 "$(fancy_rc ARI_DOTFILES_UI=plain ARI_DOTFILES_GUM="${FAKE_GUM}")"
assert_eq "launchd under fancy is still fancy (the seam is for tests)" 0 \
  "$(fancy_rc ARI_DOTFILES_UI=fancy ARI_DOTFILES_GUM="${FAKE_GUM}" ARI_DOTFILES_INVOKED_BY=launchd)"
ui_run ARI_DOTFILES_UI=fancy ARI_DOTFILES_GUM="${FAKE_GUM}" -- \
  'ui::is_fancy; a=$?; ARI_DOTFILES_UI=plain NO_COLOR=1; ui::is_fancy; print -r -- "${a} $?"'
assert_eq "decided once per process" "0 0"$'\n' "${OUT}"
export ARI_DOTFILES_UI=sparkly
nm help
unset ARI_DOTFILES_UI
assert_eq "a bad seam value stops the entrypoint" 3 "${RC}"
assert_contains "and names the seam" "${ERR}" "var='ARI_DOTFILES_UI' value='sparkly'"

# ── Plain fallbacks, byte for byte, with gum present but the seam plain ──────
rm -f "${FIX}/gum.log"
P=(ARI_DOTFILES_UI=plain ARI_DOTFILES_GUM="${FAKE_GUM}")
ui_run "${P[@]}" -- 'ui::spin_start "working"; ui::spin_start again; ui::spin_stop; ui::spin_stop; print -r -- "rc=$? pid=[${UI_SPIN_PID}]"'
assert_eq "spin_start/stop are silent no-ops" "rc=0 pid=[]"$'\n' "${OUT}"
assert_eq "spin_start/stop print nothing on stderr" "" "${ERR}"
ui_run "${P[@]}" -- 'ui::paint ok "all good"; ui::paint error "boom"; ui::paint cyan "c"; ui::paint nosuch "n"'
assert_eq "paint leaves text unchanged" $'all good\nboom\nc\nn\n' "${OUT}"
ui_run "${P[@]}" -- 'for s in ok warn fail error skip other; do ui::glyph "${s}"; done'
assert_eq "glyph is the status word" $'ok\nwarn\nfail\nerror\nskip\nother\n' "${OUT}"
ui_run "${P[@]}" -- 'ui::box --title "Repos" --color green -- "dotfiles ok" "local warn"'
assert_eq "box: title, then lines indented two" $'Repos\n  dotfiles ok\n  local warn\n' "${OUT}"
ui_run "${P[@]}" -- 'ui::box "a" "-b"'
assert_eq "box without a title" $'  a\n  -b\n' "${OUT}"
ui_run "${P[@]}" -- 'ui::join_h $'"'"'A\nB'"'"' "C" $'"'"'D\nE'"'"''
assert_eq "join_h: blocks with a blank line between" $'A\nB\n\nC\n\nD\nE\n' "${OUT}"
ui_run "${P[@]}" -- 'ui::choose --header "Pick" one two; print -r -- "rc=$?"'
assert_eq "choose returns 1 and prints nothing" "rc=1"$'\n' "${OUT}"
printf '# Title\n\n- *item*\n' > "${FIX}/doc.md"
ui_run "${P[@]}" -- "ui::markdown '${FIX}/doc.md'"
assert_eq "markdown is cat" $'# Title\n\n- *item*\n' "${OUT}"
assert_eq "plain never called gum" "" "$(gum_log)"

# The auto path with no tty gets the same bytes and no gum either.
ui_run ARI_DOTFILES_GUM="${FAKE_GUM}" -- 'ui::paint warn w; ui::glyph ok; ui::box --title T x; ui::choose a; ui::spin_start s; ui::spin_stop'
assert_eq "auto without a tty: plain output" $'w\nok\nT\n  x\n' "${OUT}"
assert_eq "auto without a tty never called gum" "" "$(gum_log)"

# ── clip and cols: pure, the same in both modes ──────────────────────────────
ui_run -- 'ui::clip 5 abcdefgh; ui::clip 5 abcde; ui::clip 1 abc; ui::clip 0 abc; ui::clip 4 "✓é…xyz"; ui::clip 3 "✓✗‼"'
assert_eq "clip cuts to the width with a trailing …" $'abcd…\nabcde\n…\n\n✓é……\n✓✗‼\n' "${OUT}"
ui_run -- 'ui::clip 3 $'"'"'\e[31mabcdef\e[0m'"'"'; ui::clip 9 $'"'"'\e[1mabc\e[0m'"'"''
assert_eq "clip ignores colour escapes and closes them" $'\e[31mab…\e[0m\n\e[1mabc\e[0m\n' "${OUT}"
ui_run ARI_DOTFILES_UI=fancy ARI_DOTFILES_GUM="${FAKE_GUM}" -- 'ui::clip 5 abcdefgh'
assert_eq "clip is the same when fancy" $'abcd…\n' "${OUT}"
ui_run -- 'ui::cols'
assert_eq "cols defaults to 100 without a tty" $'100\n' "${OUT}"
ui_run COLUMNS=42 -- 'ui::cols'
assert_eq "cols reads COLUMNS" $'42\n' "${OUT}"

# ── table ────────────────────────────────────────────────────────────────────
printf 'step\tstatus\tdetail\nbrew\tok\tall formulae declared\nclaude_skills\twarn\t\n\nssh_key\tfail\tno key\n' > "${FIX}/t.tsv"
ui_run -- "ui::table '${FIX}/t.tsv'"
assert_eq "table aligns columns two apart, no trailing blanks, skips empty rows" \
$'step           status  detail
brew           ok      all formulae declared
claude_skills  warn
ssh_key        fail    no key\n' "${OUT}"
ui_run -- "ui::table '${FIX}/t.tsv' --widths 6,0,8"
assert_eq "table clips to --widths" \
$'step    status  detail
brew    ok      all for…
claud…  warn
ssh_k…  fail    no key\n' "${OUT}"
ui_run COLUMNS=20 -- "ui::table --widths=0,0,0 - < '${FIX}/t.tsv'"
assert_eq "table reads stdin and clips each line to cols" \
$'step           stat…
brew           ok  …
claude_skills  warn
ssh_key        fail…\n' "${OUT}"
ui_run -- 'printf "a\t%s\tz\nlonger\tb\n" $'"'"'\e[38;5;71mok\e[0m'"'"' | ui::table -'
assert_eq "table pads by display width, not escape bytes" $'a       \e[38;5;71mok\e[0m  z\nlonger  b\n' "${OUT}"
ui_run ARI_DOTFILES_UI=fancy ARI_DOTFILES_GUM="${FAKE_GUM}" -- "ui::table '${FIX}/t.tsv' --widths 6,0,8"
assert_eq "fancy table: same layout, header bold" \
$'\e[1mstep    status  detail\e[0m
brew    ok      all for…
claud…  warn
ssh_k…  fail    no key\n' "${OUT}"
ui_run ARI_DOTFILES_UI=fancy ARI_DOTFILES_GUM="${FAKE_GUM}" -- "ui::table --no-header '${FIX}/t.tsv' --widths 6,0,8"
assert_eq "fancy table --no-header: same layout, nothing bold" \
$'step    status  detail
brew    ok      all for…
claud…  warn
ssh_k…  fail    no key\n' "${OUT}"
ui_run COLUMNS=20 -- "ui::table --no-clip - < '${FIX}/t.tsv'"
assert_eq "table --no-clip keeps lines wider than cols whole" \
$'step           status  detail
brew           ok      all formulae declared
claude_skills  warn
ssh_key        fail    no key\n' "${OUT}"
ui_run -- 'printf "a\tb\tc\nlonger\n" | ui::table --no-header --no-clip -'
assert_eq "a short row is padded only up to its own last cell" $'a       b  c\nlonger\n' "${OUT}"
assert_eq "table never calls gum" "" "$(gum_log)"

# ── input and confirm: no tty on stdin is 1 with nothing drawn, gum or not, never a yes ─
for seam in plain fancy; do
  ui_run ARI_DOTFILES_UI="${seam}" ARI_DOTFILES_GUM="${FAKE_GUM}" -- \
    'ui::input --header H --placeholder P < /dev/null; print -r -- "input=$?"; ui::confirm "go?" < /dev/null; print -r -- "confirm=$?"'
  assert_eq "${seam}: input and confirm without a tty return 1" $'input=1\nconfirm=1\n' "${OUT}"
  assert_eq "${seam}: input and confirm without a tty draw nothing" "" "${ERR}"
done
assert_eq "input and confirm without a tty never call gum" "" "$(gum_log)"

# ── Fancy routes through the one gum wrapper ────────────────────────────────
ui_run ARI_DOTFILES_UI=fancy ARI_DOTFILES_GUM="${FAKE_GUM}" -- 'ui::paint ok hi; ui::paint error E; ui::glyph fail; ui::box --title T --color green -- x'
assert_eq "fancy paint, glyph and box" $'\e[38;5;71mhi\e[0m\n\e[1m\e[38;5;196mE\e[0m\n✗\nGUM\n' "${OUT}"
assert_eq "box is one gum style call with the colour forced" \
  "1|style --border rounded --padding 0 1 --border-foreground 71 -- "$'\e[1mT\e[0m x' "$(gum_log)"

# ── Inside a step subprocess ui is never fancy, even with the seam forced ────
# A checkout whose steps/ holds one probe step; lib and the log plugins are the real ones.
root="${FIX}/dfconf"
mkdir -p "${root}/dotfiles/steps" "${root}/zsh"
ln -s "${ORIG_CONFIG_DIR}/dotfiles/lib" "${root}/dotfiles/lib"
ln -s "${ORIG_CONFIG_DIR}/zsh/plugins" "${root}/zsh/plugins"
printf 'check::uiprobe() { if ui::is_fancy; then print fancy; else print plain; fi; ui::box --title T x; }\n' > "${root}/dotfiles/steps/uiprobe.zsh"
rm -f "${FIX}/gum.log"
ui_run ARI_DOTFILES_LIB="${root}/dotfiles/lib" ARI_DOTFILES_UI=fancy ARI_DOTFILES_GUM="${FAKE_GUM}" -- \
  'ui::is_fancy; print -r -- "parent=$?"; step::run_isolated check uiprobe 10'
assert_eq "the parent is fancy, the step subprocess plain" $'parent=0\nplain\nT\n  x\n' "${OUT}"
assert_eq "the step subprocess never called gum" "" "$(gum_log)"

report
