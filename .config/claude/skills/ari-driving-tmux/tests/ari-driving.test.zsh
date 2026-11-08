#!/usr/bin/env zsh
# Tests for bin/ari-driving on a throwaway tmux server (-L, bare config): on and off set and clear the pane
# and window options and copy the full label through a fake pbcopy; the machine= part follows a fake
# `dotfiles machine-name`; status prints the label; a window's own status format is marked and restored; the
# window-layout-changed hook `on` arms runs release only when no pane is marked, taking the window marker
# down when the last marked pane closed, by shell exit or kill-pane, also from a script path with a space;
# a failing or missing pbcopy never aborts. Never touches the live tmux server or the real clipboard.
# Run: zsh $HOME/.claude/skills/ari-driving-tmux/tests/ari-driving.test.zsh
set -uo pipefail

readonly HERE="${0:A:h}"
readonly SKILL="${HERE:h}"
readonly SCRIPT="${SKILL}/bin/ari-driving"
# tmux's homes, Nix's first, as bin/ari-driving tries them: Claude's Bash may lack the Nix profiles.
export PATH="${PATH}:/etc/profiles/per-user/${USERNAME}/bin:/run/current-system/sw/bin:/opt/homebrew/bin"
readonly T="${TMPDIR:-/tmp}/ari-driving-test-$$"
readonly L="ari-driving-test-$$"
mkdir -p "${T}/bin" "${T}/failbin" "${T}/sp ace"
export LOG_COLOR=0
export ARI_DRIVING_RELEASE_LOG="${T}/release.log"

typeset -i pass=0 fail=0
check() {   # <name> <want> <got>
  if [[ "${2}" == "${3}" ]]; then (( pass += 1 )); print -- "ok      ${1}"
  else (( fail += 1 )); print -- "FAIL    ${1} | want='${2}' got='${3}'"; fi
}
contains() {   # <name> <needle> <haystack>
  if [[ "${3}" == *"${2}"* ]]; then (( pass += 1 )); print -- "ok      ${1}"
  else (( fail += 1 )); print -- "FAIL    ${1} | needle='${2}' in='${3}'"; fi
}

# Fakes on PATH: the clipboard writer records what it was given (a second one fails); the dotfiles harness
# names the machine.
cat > "${T}/bin/pbcopy" <<EOF
#!/bin/sh
cat > "${T}/clip"
EOF
printf '#!/bin/sh\ncat >/dev/null; exit 1\n' > "${T}/failbin/pbcopy"
cat > "${T}/bin/dotfiles" <<'EOF'
#!/bin/sh
[ "$1" = machine-name ] && echo testbox
EOF
chmod +x "${T}/bin/pbcopy" "${T}/failbin/pbcopy" "${T}/bin/dotfiles"
# Three PATHs, none reaching the real clipboard: the shims first; the failing pbcopy first; or a minimal one
# holding only what the script needs (tmux, zsh, date) and no pbcopy or dotfiles at all. The real PATH is never
# used again: on 2026-11-02 a case that ran under it put a test label on Ari's clipboard.
mkdir -p "${T}/minbin"
for tool in tmux zsh date; do ln -s "$(command -v "${tool}")" "${T}/minbin/${tool}"; done
readonly MIN_PATH="${T}/minbin"
readonly FAIL_PATH="${T}/failbin:${T}/minbin"
export PATH="${T}/bin:${PATH}"
[[ "$(command -v pbcopy)" == "${T}/bin/pbcopy" ]] || { print -u2 "pbcopy does not resolve to the shim; refusing to run"; exit 1; }
[[ -z "$(PATH="${MIN_PATH}" command -v pbcopy)" ]] || { print -u2 "the minimal PATH reaches a pbcopy; refusing to run"; exit 1; }
clip() { cat "${T}/clip" 2>/dev/null || true; }

# The test server: bare config, /bin/sh panes (a login zsh would take seconds to start and to exit).
tm() { tmux -L "${L}" -f /dev/null "$@"; }
tm new-session -d -s t -x 100 -y 30 /bin/sh || { print -u2 "cannot start a test tmux server"; exit 1; }
trap 'tm kill-server 2>/dev/null; rm -rf "${T}"' EXIT
export TMUX="$(tm display-message -p '#{socket_path}'),0,0"
W="$(tm display-message -p -t t: '#{window_id}')"
A="$(tm list-panes -t "${W}" -F '#{pane_id}')"       # never marked; keeps the window alive
# A second, active, unmarked window: the hook's any-pane-on test must look at the hook's window, not this one.
tm new-window -d -t t: /bin/sh; X="$(tm list-windows -t t -F '#{window_id}' | tail -1)"; tm select-window -t "${X}"
# -P -F prints the new pane's id: a split lands after the active pane, so the last listed pane is not it.
split() { tm split-window -d -P -F '#{pane_id}' -t "${W}" /bin/sh; }
pane_opt() { tm show-options -pqv -t "${1}" @ari_driving; }
stamp() { tm show-options -pqv -t "${1}" @ari_driving_since; }
win_opt() { tm show-options -wqv -t "${W}" @ari_driving_window; }
win_fmt() { tm show-options -wqv -t "${W}" window-status-format; }
cur_fmt() { tm show-options -wqv -t "${W}" window-status-current-format; }
hook() { tm show-hooks -w -t "${W}" 2>/dev/null | grep -c 'ari-driving release\|ari-driving" release\|ari-driving'"'"' release' || true; }
label() { print -r -- "machine=testbox|ID=${1}|pane=$(tm display-message -p -t "${1}" '#{window_index}.#{pane_index}')"; }
run() { TMUX_PANE="${1}" zsh "${SCRIPT}" "${@:2}" 2>"${T}/err"; LAST_RC=$?; }
typeset -g LAST_RC=0
# release runs from the server through run-shell -b; give it a moment.
settle() { sleep 0.8; }
release_log() { cat "${ARI_DRIVING_RELEASE_LOG}" 2>/dev/null || true; }

# --- on: pane and window marked, hook armed, full label copied ---
B="$(split)"; C="$(split)"
run "${B}" on
check "on: rc 0" 0 "${LAST_RC}"
check "on: pane option" on "$(pane_opt "${B}")"
check "on: window option" on "$(win_opt)"
contains "on: window format carries the marker" '✦' "$(win_fmt)"
check "on: the release hook is armed on the window" 1 "$(hook)"
check "on: the full label is on the clipboard" "$(label "${B}")" "$(clip)"
contains "on: says it copied" "Label copied to the clipboard" "$(<"${T}/err")"
contains "on: names the displaced clipboard entry" "Raycast Clipboard History" "$(<"${T}/err")"
run "${C}" on
check "on (second pane): its label replaces the clipboard" "$(label "${C}")" "$(clip)"

# --- on twice: granted afresh, said so, one marker ---
s1="$(stamp "${B}")"; sleep 1.1; run "${B}" on
check "on twice: rc 0" 0 "${LAST_RC}"
contains "on twice: says it was granted afresh" "granted afresh" "$(<"${T}/err")"
[[ "$(stamp "${B}")" -gt "${s1}" ]] && got=newer || got=same; check "on twice: the stamp moves" newer "${got}"
check "on twice: one marker in the format" 1 "$(win_fmt | awk -F'✦' '{ print NF - 1 }')"

# --- the gate: a layout change with a pane still on runs nothing ---
: > "${ARI_DRIVING_RELEASE_LOG}"
tm resize-pane -t "${B}" -D 2; tm resize-pane -t "${B}" -U 2; settle
check "gate: a resize with marked panes spawns no release" "" "$(release_log)"

# --- status ---
out="$(TMUX_PANE="${C}" zsh "${SCRIPT}" status 2>/dev/null)"
contains "status: pane= line" "pane=ID=${C}|pane=" "${out}"
contains "status: label= line carries the machine" "label=$(label "${C}")" "${out}"
contains "status: on" "ari_driving=on" "${out}"

# --- off with another pane still on: window stays marked, label copied ---
run "${B}" off
check "off: rc 0" 0 "${LAST_RC}"
check "off: pane option cleared" "" "$(pane_opt "${B}")"
check "off: window still marked while another pane is on" on "$(win_opt)"
check "off: hook stays while the window is marked" 1 "$(hook)"
check "off: the label is on the clipboard" "$(label "${B}")" "$(clip)"

# --- off on a pane that was not on: said so, still copied, nothing else touched ---
: > "${T}/clip"; run "${B}" off
check "off twice: rc 0" 0 "${LAST_RC}"
contains "off twice: says it was not on" "Pane was not on" "$(<"${T}/err")"
check "off twice: still copies the label" "$(label "${B}")" "$(clip)"
check "off twice: window still marked" on "$(win_opt)"

# --- the last marked pane's shell exits: release takes the marker down ---
: > "${ARI_DRIVING_RELEASE_LOG}"
tm send-keys -t "${C}" 'exit' Enter; settle
check "exit: the pane is gone" "" "$(tm list-panes -t "${W}" -F '#{pane_id}' | grep -x "${C}" || true)"
check "exit: window option cleared by release" "" "$(win_opt)"
check "exit: window format restored" "" "$(win_fmt)"
check "exit: hook dropped" 0 "$(hook)"
contains "exit: release logged it" "Last driving pane closed" "$(release_log)"

# --- kill-pane: a non-last close keeps the marker; the last close drops it ---
run "${B}" on; D="$(split)"; run "${D}" on
tm kill-pane -t "${D}"; settle
check "kill-pane (not last): window still marked" on "$(win_opt)"
check "kill-pane (not last): hook kept" 1 "$(hook)"
tm kill-pane -t "${B}"; settle
check "kill-pane (last): window option cleared" "" "$(win_opt)"
check "kill-pane (last): hook dropped" 0 "$(hook)"
check "kill-pane: the unmarked pane survives" "${A}" "$(tm list-panes -t "${W}" -F '#{pane_id}')"

# --- a window-status format the window had of its own is marked and restored byte for byte ---
tm set-option -w -t "${W}" window-status-format 'mine #I here'
F="$(split)"; run "${F}" on
check "own format: marked, not replaced" "mine #{?@ari_driving_window,✦,}#I here" "$(win_fmt)"
contains "own format: the other format got the marker too" '✦' "$(cur_fmt)"
check "own format: the original is saved" 'mine #I here' "$(tm show-options -wqv -t "${W}" @ari_driving_saved_window-status-format)"
run "${F}" off
check "own format: restored by off" 'mine #I here' "$(win_fmt)"
check "own format: the other format is unset again" "" "$(cur_fmt)"
check "own format: the saved copy is gone" "" "$(tm show-options -wqv -t "${W}" @ari_driving_saved_window-status-format)"
tm set-option -wu -t "${W}" window-status-format; tm kill-pane -t "${F}"; settle

# --- a script path with a space: the hook still reaches release ---
cp "${SCRIPT}" "${T}/sp ace/ari-driving"; chmod +x "${T}/sp ace/ari-driving"
G="$(split)"; TMUX_PANE="${G}" zsh "${T}/sp ace/ari-driving" on 2>"${T}/err"
check "space path: on rc 0" 0 "$?"
contains "space path: the hook quotes the path" "'${T:A}/sp ace/ari-driving'" "$(tm show-hooks -w -t "${W}")"
: > "${ARI_DRIVING_RELEASE_LOG}"; tm kill-pane -t "${G}"; settle
check "space path: release ran and unmarked the window" "" "$(win_opt)"
contains "space path: release logged it" "Last driving pane closed" "$(release_log)"

# --- release by hand: a gone window and an unmarked window are left alone ---
zsh "${SCRIPT}" release @999 2>"${T}/err"; check "release: gone window rc 0" 0 "$?"
zsh "${SCRIPT}" release "${W}" 2>"${T}/err"; check "release: unmarked window rc 0" 0 "$?"
zsh "${SCRIPT}" release >/dev/null 2>"${T}/err"; check "release: no window rc 1" 1 "$?"

# --- pbcopy fails: still on, warned, nothing half done ---
E="$(split)"; : > "${T}/clip"
PATH="${FAIL_PATH}" TMUX_PANE="${E}" zsh "${SCRIPT}" on 2>"${T}/err"
check "failing clipboard: rc 0" 0 "$?"
check "failing clipboard: pane on" on "$(pane_opt "${E}")"
check "failing clipboard: hook armed" 1 "$(hook)"
contains "failing clipboard: warned" "Clipboard command failed" "$(<"${T}/err")"
run "${E}" off

# --- no pbcopy, no dotfiles: still on, label without machine=, a warning ---
: > "${T}/clip"
PATH="${MIN_PATH}" TMUX_PANE="${E}" zsh "${SCRIPT}" on 2>"${T}/err"
check "no clipboard: rc 0" 0 "$?"
check "no clipboard: pane on" on "$(pane_opt "${E}")"
contains "no clipboard: warned" "label not copied" "$(<"${T}/err")"
contains "no dotfiles: label has no machine part" "label='ID=${E}|pane=" "$(<"${T}/err")"
check "no clipboard: clipboard untouched" "" "$(clip)"

# --- tmux off PATH (a Claude Bash without the Nix profiles): check_tmux still finds it ---
readonly BARE_PATH=/usr/bin:/bin
if [[ -n "$(PATH="${BARE_PATH}" command -v tmux)" ]]; then
  print -- "skip    tmux off PATH: ${BARE_PATH} holds a tmux"
else
  out="$(PATH="${BARE_PATH}" TMUX_PANE="${E}" /bin/zsh "${SCRIPT}" status 2>"${T}/err")"
  check "tmux off PATH: status rc 0" 0 "$?"
  contains "tmux off PATH: status names the pane" "pane=ID=${E}|" "${out}"
fi

# --- errors ---
TMUX_PANE= zsh "${SCRIPT}" on 2>"${T}/err"; check "no TMUX_PANE: rc 1" 1 "$?"
TMUX_PANE=%999 zsh "${SCRIPT}" on 2>"${T}/err"; check "unknown TMUX_PANE: rc 1" 1 "$?"
contains "unknown TMUX_PANE: says so" "unknown to the tmux server" "$(<"${T}/err")"
zsh "${SCRIPT}" >/dev/null 2>"${T}/err"; check "no action: rc 1" 1 "$?"
zsh "${SCRIPT}" bogus >/dev/null 2>"${T}/err"; check "unknown action: rc 1" 1 "$?"

print -- "${pass} passed, ${fail} failed"
(( fail == 0 ))
