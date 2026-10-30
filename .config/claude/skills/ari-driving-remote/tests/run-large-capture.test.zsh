#!/usr/bin/env zsh
# Regression: a capture larger than a pipe buffer must not kill run.zsh with SIGPIPE (exit 141, no
# stdout) while it scans the host output for the BIND line; the comment above that scan in bin/run.zsh
# holds the history. A fake ssh on PATH ignores the script it is handed and prints a canned run: PANE,
# BIND, TYPED, SENT, then CAPTURE_LINES long lines. No tmux, no network.
# Run: zsh $HOME/.claude/skills/ari-driving-remote/tests/run-large-capture.test.zsh

set -uo pipefail

readonly SCRIPT_DIR="${0:A:h}"
readonly RUN_ZSH="${SCRIPT_DIR:h}/bin/run.zsh"
readonly CAPTURE_LINES=3000     # ~450 KB with the padding below: past any pipe buffer

typeset -i pass=0 fail=0
check() {   # <name> <want> <got>
  if [[ "${2}" == "${3}" ]]; then (( pass += 1 )); print -- "ok      ${1}"
  else (( fail += 1 )); print -- "FAIL    ${1} | want='${2}' got='${3}'"; fi
}
contains() {   # <name> <needle> <haystack>
  if [[ "${3}" == *"${2}"* ]]; then (( pass += 1 )); print -- "ok      ${1}"
  else (( fail += 1 )); print -- "FAIL    ${1} | needle='${2}'"; fi
}

readonly T="$(mktemp -d)"
trap 'rm -rf "${T}"' EXIT
mkdir -p "${T}/bin" "${T}/data" "${T}/state" "${T}/cache"

# The fake ssh: whatever script it is handed, it answers like a host whose pane ran the command and
# then printed a CAPTURE_LINES-line capture of long lines.
cat > "${T}/bin/ssh" <<FAKE
#!/usr/bin/env zsh
print -r -- 'PANE: machine=fake|ID=%5|pane=1.1'
print -r -- 'BIND: %5 0'
print -r -- "TYPED: echo hi"
print -r -- 'SENT'
pad="\$(printf 'x%.0s' {1..150})"
for (( i = 1; i <= ${CAPTURE_LINES}; i++ )); do print -r -- "line \$i \$pad"; done
exit 0
FAKE
chmod +x "${T}/bin/ssh"

# Every XDG dir points into the temp tree: run.zsh migrates an old hosts dir on each run, and the real one must stay put.
out="$(PATH="${T}/bin:${PATH}" XDG_DATA_HOME="${T}/data" XDG_STATE_HOME="${T}/state" XDG_CACHE_HOME="${T}/cache" CLAUDE_CODE_SESSION_ID=test-session LOG_COLOR=0 \
  zsh "${RUN_ZSH}" --host-definition fake --host fake@host --target %5 --no-run-log --cmd 'echo hi' 2>"${T}/err")"; rc=$?
check "run.zsh exits 0" 0 "${rc}"
contains "run.zsh prints line 1" $'\nline 1 ' "${out}"
contains "run.zsh prints line ${CAPTURE_LINES}" "line ${CAPTURE_LINES} " "${out}"
check "run.zsh prints every line" "${CAPTURE_LINES}" "$(print -r -- "${out}" | awk '/^line / { n++ } END { print n + 0 }')"
contains "run.zsh prints SENT" $'\nSENT\n' "${out}"
check "run.zsh binds the pane to this session" "session=test-session" "$(head -1 "${T}/state/ari-driving-remote/bindings/fake/5" 2>/dev/null)"
check "run.zsh prints no error on stderr" 0 "$(awk '/ERROR|exit.*141/ { n++ } END { print n + 0 }' "${T}/err")"

print -- "${pass} passed, ${fail} failed"
if (( fail > 0 )); then print -u2 -- "--- run.zsh stderr:"; cat "${T}/err" >&2; exit 1; fi
