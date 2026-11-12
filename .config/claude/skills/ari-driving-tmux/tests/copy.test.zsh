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
: > "${T}/zdot/.zshrc"
export LOG_COLOR=0

typeset -i pass=0 fail=0
check() {   # <name> <want> <got>
  if [[ "${2}" == "${3}" ]]; then (( pass += 1 )); print -- "ok      ${1}"
  else (( fail += 1 )); print -- "FAIL    ${1}"; print -r -- "--- want"; print -r -- "${2}"; print -r -- "--- got"; print -r -- "${3}"; fi
}
lacks() {   # <name> <needle> <haystack>
  if [[ "${3}" != *"${2}"* ]]; then (( pass += 1 )); print -- "ok      ${1}"
  else (( fail += 1 )); print -- "FAIL    ${1} | found='${2}'"; fi
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
check "link: the copy link and the command's code block" '> [⎘ copy to clipboard](tmux-pane://copy?copy=bd%20close%20beads-q1h%20--reason%20%22done%22)
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

check "link: the URL names a host, never an empty authority" 0 "$([[ "${OUT}" == *'](tmux-pane://copy?copy='* && "${OUT}" != *'tmux-pane://?'* ]]; print -r -- $?)"
lacks "link: no U+29C9 (Claude Code would print the URL after the link text)" $'⧉' "${OUT}"

# --- link.zsh --copy: the artifact line comes back to Claude's pane ---
DELIVER="$(TMUX_PANE=%96 zsh "${SKILL}/bin/link.zsh" --copy 'run_log -- kubectl get pods' 2>/dev/null)"
check "deliver: run_log text gets --deliver-to Claude's pane" '> [⎘ copy to clipboard](tmux-pane://copy?copy=run_log%20--deliver-to%20%2596%20--%20kubectl%20get%20pods)
> ```zsh
> run_log --deliver-to %96 -- kubectl get pods
> ```' "${DELIVER}"
check "deliver: never --focus-after" 1 "$([[ "${DELIVER}" == *focus-after* ]]; print -r -- $?)"
check "deliver: the shell-string form gets it too" 'run_log --deliver-to %96 '"'"'ls | wc -l'"'" "$(TMUX_PANE=%96 zsh "${SKILL}/bin/link.zsh" --copy "run_log 'ls | wc -l'" 2>/dev/null | sed -n 3p | sed 's/^> //')"
check "deliver: a text that is not run_log is as given" 'bd close x' "$(TMUX_PANE=%96 zsh "${SKILL}/bin/link.zsh" --copy 'bd close x' 2>/dev/null | sed -n 3p | sed 's/^> //')"
check "deliver: a run_log that names its --deliver-to keeps it" 'run_log --deliver-to %7 -- ls' "$(TMUX_PANE=%96 zsh "${SKILL}/bin/link.zsh" --copy 'run_log --deliver-to %7 -- ls' 2>/dev/null | sed -n 3p | sed 's/^> //')"
check "deliver: a --deliver-to after other run_log flags keeps it" 'run_log --name x --deliver-to %7 -- ls' "$(TMUX_PANE=%96 zsh "${SKILL}/bin/link.zsh" --copy 'run_log --name x --deliver-to %7 -- ls' 2>/dev/null | sed -n 3p | sed 's/^> //')"
check "deliver: other run_log flags stay, the pane goes first" 'run_log --deliver-to %96 --name x -- ls' "$(TMUX_PANE=%96 zsh "${SKILL}/bin/link.zsh" --copy 'run_log --name x -- ls' 2>/dev/null | sed -n 3p | sed 's/^> //')"
NOPANE_ERR="$(env -u TMUX_PANE zsh "${SKILL}/bin/link.zsh" --copy 'run_log -- ls' 2>&1 >"${T}/nopane.out")"
check "deliver: no \$TMUX_PANE copies today's text" 'run_log -- ls' "$(sed -n 3p "${T}/nopane.out" | sed 's/^> //')"
check "deliver: no \$TMUX_PANE warns on stderr" 0 "$([[ "${NOPANE_ERR}" == *'No Claude pane to deliver to'* ]]; print -r -- $?)"
LAID="$(TMUX_PANE=%96 zsh "${SKILL}/bin/link.zsh" --copy "run_log -- zsh /private/tmp/claude-502/-Users-me-project/0000-session-0000-0000-000000000000/scratchpad/close-beads.zsh" 2>/dev/null | sed -n '3,$p' | sed '$d' | sed 's/^> //')"
check "deliver: a long command is laid out with the flag and its pane kept together" 'run_log --deliver-to %96 -- zsh \
    /private/tmp/claude-502/-Users-me-project/0000-session-0000-0000-000000000000/scratchpad/close-beads.zsh' "${LAID}"

# --- focus.zsh: the click ---
check "click in a Claude Code pane: rc 0" 0 "$(click '?copy=bd%20close%20beads-q1h%20--reason%20%22done%22' "${CLAUDE_PANE}")"
check "click in a Claude Code pane: the clipboard holds the command" 'bd close beads-q1h --reason "done"' "$(clipboard)"
LONG="op item create --category 'API Credential' --title 'Registry pull token (registry.example.com)' --vault Private \"credential=\$(pbpaste)\""
ENC="$(python3 -I -c 'import sys,urllib.parse; print(urllib.parse.quote(sys.argv[1], safe=""), end="")' "${LONG}")"
click "?copy=${ENC}" "${CLAUDE_PANE}" >/dev/null
source "${SKILL}/lib/wrap.zsh"
check "click: a long command is copied laid out, as its code block shows" "$(wrap_command "${LONG}")" "$(clipboard)"
click '?copy=ls%20-1' "${CLAUDE_PANE}" >/dev/null
check "click: the older empty-host payload still copies" 'ls -1' "$(clipboard)"
check "click: the host form copies, rc 0" 0 "$(click 'copy?copy=ls%20-2' "${CLAUDE_PANE}")"
check "click: the host form puts the command on the clipboard" 'ls -2' "$(clipboard)"
check "click in a plain shell pane: refused, rc 1" 1 "$(click '?copy=ls' "${SHELL_PANE}")"
check "click in a plain shell pane: the clipboard is untouched" "<untouched>" "$(clipboard)"
click '?copy=ls' "" >/dev/null
check "click with no clicked pane: the clipboard is untouched" "<untouched>" "$(clipboard)"
click '?copy=ari-driving%20on' "${CLAUDE_PANE}" >/dev/null
check "click: the opt-in text is not copied" "<untouched>" "$(clipboard)"
zsh "${SKILL}/bin/focus.zsh" --no-activate --pane "%1?copy=ls" --return-pane "${CLAUDE_PANE}" >/dev/null 2>&1
check "click: a pane id with a copy payload is not a copy" "<untouched>" "$(clipboard)"

# The copied text, typed into a plain shell pane, pastes its artifact line into Claude's pane.
if [[ -x "${HOME}/.config/bin/run_log" ]]; then
  CLIP_URL="$(TMUX_PANE="${CLAUDE_PANE}" zsh "${SKILL}/bin/link.zsh" --copy 'run_log -- echo copy-e2e' 2>/dev/null | sed -n 1p | sed 's/.*(tmux-pane:\/\/\(.*\))$/\1/')"
  click "${CLIP_URL}" "${CLAUDE_PANE}" >/dev/null
  check "e2e: the click copied the delivering command" "run_log --deliver-to ${CLAUDE_PANE} -- echo copy-e2e" "$(clipboard)"
  tm send-keys -t "${SHELL_PANE}" -l "export PATH=${HOME}/.config/bin:\${PATH} LOG_DIR=${T}/captures; $(clipboard)"
  tm send-keys -t "${SHELL_PANE}" Enter
  for _ in {1..40}; do
    [[ "$(tm capture-pane -p -J -t "${CLAUDE_PANE}")" == *'run_log artifact:'* ]] && break
    sleep 0.25
  done
  check "e2e: the artifact line landed in Claude's pane" 0 "$([[ "$(tm capture-pane -p -J -t "${CLAUDE_PANE}")" == *"run_log artifact: ${T}/captures/"* ]]; print -r -- $?)"
fi

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
