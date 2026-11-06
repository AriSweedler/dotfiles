#!/usr/bin/env zsh
# Tests for the copy-on-click link: link.zsh --copy prints it, focus.zsh --pane '?copy=…' copies. A shim
# stands in for the system clipboard writer and wins PATH, a throwaway tmux server (-L) supplies a Claude Code
# pane (a compiled stand-in named claude) and a plain shell pane. Never touches the live tmux server or Ari's clipboard.
# Run: zsh $HOME/.claude/skills/ari-driving-tmux/tests/copy.test.zsh
set -uo pipefail

readonly HERE="${0:A:h}"
readonly SKILL="${HERE:h}"
readonly T="${TMPDIR:-/tmp}/ari-driving-copy-test-$$"
readonly L="ari-driving-copy-test-$$"
mkdir -p "${T}/shim" "${T}/zdot"
export LOG_COLOR=0

typeset -i pass=0 fail=0
check() {   # <name> <want> <got>
  if [[ "${2}" == "${3}" ]]; then (( pass += 1 )); print -- "ok      ${1}"
  else (( fail += 1 )); print -- "FAIL    ${1}"; print -r -- "--- want"; print -r -- "${2}"; print -r -- "--- got"; print -r -- "${3}"; fi
}

cat > "${T}/shim/pbcopy" <<EOF
#!/bin/sh
cat > "${T}/clip"
EOF
chmod +x "${T}/shim/pbcopy"
printf '#include <unistd.h>\nint main(void) { for (;;) sleep(60); }\n' > "${T}/claude.c"
cc -o "${T}/shim/claude" "${T}/claude.c" || { print -u2 "cannot build the claude stand-in (needs cc)"; exit 1; }
export PATH="${T}/shim:${PATH}"
if [[ "$(command -v pbcopy)" != "${T}/shim/pbcopy" ]]; then
  print -u2 "the shim does not win PATH; refusing to run"
  exit 1
fi

tm() { tmux -L "${L}" -f /dev/null "$@"; }
tm new-session -d -s t -x 200 -y 50 -e "PATH=${PATH}" -e "ZDOTDIR=${T}/zdot" zsh || { print -u2 "cannot start a test tmux server"; exit 1; }
trap 'tm kill-server 2>/dev/null; rm -rf "${T}"' EXIT
export TMUX="$(tm display-message -p '#{socket_path}'),0,0"
SHELL_PANE="$(tm list-panes -t t -F '#{pane_id}')"
CLAUDE_PANE="$(tm new-window -d -P -F '#{pane_id}' -t t: "${T}/shim/claude")"
sleep 0.5

click() {   # <url payload> <return pane>
  rm -f "${T}/clip"
  zsh "${SKILL}/bin/focus.zsh" --no-activate --pane "${1}" --return-pane "${2}" >/dev/null 2>&1
  print -r -- "$?"
}
clipboard() { [[ -f "${T}/clip" ]] && cat "${T}/clip" || print -rn -- "<untouched>"; }

# --- link.zsh --copy ---
OUT="$(zsh "${SKILL}/bin/link.zsh" --copy 'bd close beads-q1h --reason "done"' 2>/dev/null)"
check "link: the copy link and the command's code block" '> [⧉ copy to clipboard](tmux-pane://?copy=bd%20close%20beads-q1h%20--reason%20%22done%22)
> ```zsh
> bd close beads-q1h --reason "done"
> ```' "${OUT}"
zsh "${SKILL}/bin/link.zsh" --copy x --pane 2.4 >/dev/null 2>&1
check "link: --copy with --pane is refused" 1 "$?"
zsh "${SKILL}/bin/link.zsh" --copy $'a\nb' >/dev/null 2>&1
check "link: a newline is refused" 1 "$?"
zsh "${SKILL}/bin/link.zsh" --copy 'clear && ls' >/dev/null 2>&1
check "link: a leading clear is refused" 1 "$?"
zsh "${SKILL}/bin/link.zsh" --copy 'ari-driving on' >/dev/null 2>&1
check "link: the opt-in text is refused" 1 "$?"

# --- focus.zsh: the click ---
check "click in a Claude Code pane: rc 0" 0 "$(click '?copy=bd%20close%20beads-q1h%20--reason%20%22done%22' "${CLAUDE_PANE}")"
check "click in a Claude Code pane: the clipboard holds the command" 'bd close beads-q1h --reason "done"' "$(clipboard)"
LONG="op item create --category 'API Credential' --title 'Registry pull token (registry.example.com)' --vault Private \"credential=\$(pbpaste)\""
ENC="$(python3 -I -c 'import sys,urllib.parse; print(urllib.parse.quote(sys.argv[1], safe=""), end="")' "${LONG}")"
click "?copy=${ENC}" "${CLAUDE_PANE}" >/dev/null
source "${SKILL}/lib/wrap.zsh"
check "click: a long command is copied laid out, as its code block shows" "$(wrap_command "${LONG}")" "$(clipboard)"
check "click in a plain shell pane: refused, rc 1" 1 "$(click '?copy=ls' "${SHELL_PANE}")"
check "click in a plain shell pane: the clipboard is untouched" "<untouched>" "$(clipboard)"
click '?copy=ls' "" >/dev/null
check "click with no clicked pane: the clipboard is untouched" "<untouched>" "$(clipboard)"
click '?copy=ari-driving%20on' "${CLAUDE_PANE}" >/dev/null
check "click: the opt-in text is not copied" "<untouched>" "$(clipboard)"
zsh "${SKILL}/bin/focus.zsh" --no-activate --pane "%1?copy=ls" --return-pane "${CLAUDE_PANE}" >/dev/null 2>&1
check "click: a pane id with a copy payload is not a copy" "<untouched>" "$(clipboard)"

rm -f "${T}/clip"
zsh "${SKILL}/bin/focus.zsh" --no-activate --copy 'ls' --return-pane "${CLAUDE_PANE}" >/dev/null 2>&1
check "no --copy flag: the CLI route is refused" 1 "$?"
check "no --copy flag: the clipboard is untouched" "<untouched>" "$(clipboard)"
check "click: an empty payload is refused, rc 1" 1 "$(click '?copy=' "${CLAUDE_PANE}")"
check "click: an empty payload leaves the clipboard untouched" "<untouched>" "$(clipboard)"
click '?copy=echo%20100%25%20%60x%60' "${CLAUDE_PANE}" >/dev/null
check "click: %, backtick survive the round trip" 'echo 100% `x`' "$(clipboard)"
GUARD_FOCUS="$(print -r -- '{"tool_input":{"command":"zsh $HOME/.claude/skills/ari-driving-tmux/bin/focus.zsh --pane \"?copy=ls\" --return-pane %1"}}' | zsh "${SKILL}/bin/pretooluse_bash_pbcopy_guard.sh" >/dev/null 2>&1; print -r -- $?)"
check "guard: a Bash call to focus.zsh with ?copy= is blocked" 2 "${GUARD_FOCUS}"

# --- the pbcopy guard's message points at links, not a bare block ---
GUARD_MSG="$(print -r -- '{"tool_input":{"command":"false && pbcopy"}}' | zsh "${SKILL}/bin/pretooluse_bash_pbcopy_guard.sh" 2>&1 >/dev/null)"
check "guard: the message names link.zsh --copy" 0 "$([[ "${GUARD_MSG}" == *'link.zsh --copy'* ]]; print -r -- $?)"
check "guard: the message no longer says to print a fenced block instead" 1 "$([[ "${GUARD_MSG}" == *'Print the text in the chat message instead'* ]]; print -r -- $?)"

print -- "${pass} passed, ${fail} failed"
(( fail == 0 ))
