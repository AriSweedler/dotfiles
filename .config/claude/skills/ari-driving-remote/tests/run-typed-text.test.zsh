#!/usr/bin/env zsh
# A --cmd is typed in the form /ari-driving-tmux's wrap_run_log_text gives, as one bracketed paste (load-buffer,
# then paste-buffer -p), so a heredoc and a trailing ; land whole; never '\''. A text over several lines is
# refused into a pane whose shell is not zsh (not_zsh, 75); a failed paste is 73, a failed Enter 74; the dry run
# prints the text under WOULD TYPE. The real tmux-pane lib runs under the local definition against a fake tmux
# on PATH that records the paste; HOME is a temp tree whose .config/bin/run_log is a stub. No tmux server, no
# ssh, no network.
# Run: zsh $HOME/.claude/skills/ari-driving-remote/tests/run-typed-text.test.zsh

set -uo pipefail

readonly SCRIPT_DIR="${0:A:h}"
readonly RUN_ZSH="${SCRIPT_DIR:h}/bin/run.zsh"
readonly LIB_WRAP="${HOME}/.claude/skills/ari-driving-tmux/lib/wrap.zsh"
readonly LIB_TMUX_PANE="${XDG_CONFIG_HOME:-${HOME}/.config}/claude/lib/tmux-pane.sh"
readonly FAKE_PID="run-typed-text-test-$$"
readonly LOCK_DIR="$(. "${LIB_TMUX_PANE}"; print -r -- "${ARI_DRIVING_LOCK_ROOT}")/${FAKE_PID}-5"

typeset -i pass=0 fail=0
check() {   # <name> <want> <got>
  if [[ "${2}" == "${3}" ]]; then (( pass += 1 )); print -- "ok      ${1}"
  else (( fail += 1 )); print -- "FAIL    ${1} | want='${2}' got='${3}'"; fi
}
contains() {   # <name> <needle> <haystack>
  if [[ "${3}" == *"${2}"* ]]; then (( pass += 1 )); print -- "ok      ${1}"
  else (( fail += 1 )); print -- "FAIL    ${1} | needle='${2}'"; fi
}
lacks() {   # <name> <needle> <haystack>
  if [[ "${3}" != *"${2}"* ]]; then (( pass += 1 )); print -- "ok      ${1}"
  else (( fail += 1 )); print -- "FAIL    ${1} | unwanted='${2}'"; fi
}

source "${LIB_WRAP}"

readonly T="$(mktemp -d)"
trap 'rm -rf "${T}" "${LOCK_DIR}"' EXIT
mkdir -p "${T}/bin" "${T}/data" "${T}/state" "${T}/cache" "${T}/home/.config/bin" "${T}/nolog/.config"
# A HOME with run_log, and one without; both see the real skills and the real tmux-pane lib.
ln -s "${HOME}/.claude" "${T}/home/.claude"
ln -s "${HOME}/.claude" "${T}/nolog/.claude"
print -r -- '#!/bin/sh' > "${T}/home/.config/bin/run_log"
chmod +x "${T}/home/.config/bin/run_log"

# The fake tmux: one idle pane, %5, opted in and at its prompt, running FAKE_FG (zsh). load-buffer saves its stdin
# as the buffer; paste-buffer records its flags and copies the buffer to FAKE_STATE/pasted, or fails when
# FAKE_PASTE_FAILS is set; send-keys records its arguments, or fails on Enter when FAKE_ENTER_FAILS is set.
cat > "${T}/bin/tmux" <<'FAKE'
#!/usr/bin/env zsh
case "${1}" in
  list-sessions) exit 0 ;;
  list-panes) print -r -- '%5'; exit 0 ;;
  show-options) if [[ "${@[-1]}" == @ari_driving ]]; then print -r -- on; fi; exit 0 ;;
  display-message)
    case "${@[-1]}" in
      *pane_in_mode*) print -r -- '0 0' ;;
      *pane_current_command*) print -r -- "${FAKE_FG:-zsh}" ;;
      *'#{pid}'*) print -r -- "${FAKE_PID}" ;;
      *pane_id*) print -r -- 'ID=%5|pane=1.1' ;;
    esac
    exit 0 ;;
  capture-pane) print -r -- 'home ❯'; exit 0 ;;
  load-buffer) cat > "${FAKE_STATE}/buffer"; exit 0 ;;
  paste-buffer)
    [[ -z "${FAKE_PASTE_FAILS:-}" ]] || exit 1
    print -r -- "${@[2,-1]}" > "${FAKE_STATE}/paste-flags"; cp "${FAKE_STATE}/buffer" "${FAKE_STATE}/pasted"; exit 0 ;;
  delete-buffer) exit 0 ;;
  send-keys)
    if [[ -n "${FAKE_ENTER_FAILS:-}" && "${@[-1]}" == Enter ]]; then exit 1; fi
    print -r -- "${@[2,-1]}" >> "${FAKE_STATE}/send-keys"; exit 0 ;;
esac
exit 1
FAKE
chmod +x "${T}/bin/tmux"

run() {   # <home> [VAR=value…] <run.zsh flags…>; stdout on $out, exit code on $rc; a --cmd into %5 on the local definition
  local home="${1}"
  local -a env_args=()
  shift
  while [[ "${1}" == [A-Z_]*=* ]]; do env_args+=("${1}"); shift; done
  rm -f "${T}/buffer" "${T}/pasted" "${T}/paste-flags" "${T}/send-keys"
  out="$(env "${env_args[@]}" HOME="${home}" XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-${HOME}/.config}" FAKE_PID="${FAKE_PID}" FAKE_STATE="${T}" \
    PATH="${T}/bin:${PATH}" CLAUDE_CODE_SESSION_ID=test-session \
    XDG_DATA_HOME="${T}/data" XDG_STATE_HOME="${T}/state" XDG_CACHE_HOME="${T}/cache" LOG_COLOR=0 \
    zsh "${RUN_ZSH}" --host-definition here --host local --path-prefix '' --target %5 --no-wait "$@" 2>"${T}/err")"; rc=$?
}

pasted() { cat "${T}/pasted" 2>/dev/null; }

typed_lines() {   # the TYPED: echo and every line after it up to SENT, the prefix removed
  local -a lines=("${(@f)out}")
  local -i i=1
  while (( i <= ${#lines} )) && [[ "${lines[i]}" != 'TYPED: '* ]]; do i+=1; done
  local -a typed=()
  while (( i <= ${#lines} )) && [[ "${lines[i]}" != SENT ]]; do typed+=("${lines[i]}"); i+=1; done
  print -r -- "${${(F)typed}#TYPED: }"
}

expect_typed() {   # <case> <cmd> <want>: the pasted text and the TYPED: echo are the text wrap_run_log_text gives
  run "${T}/home" --cmd "${2}"
  check "${1}: exits 0" 0 "${rc}"
  check "${1}: pastes the run_log form" "${3}" "$(pasted)"
  check "${1}: echoes the run_log form under TYPED:" "${3}" "$(typed_lines)"
  lacks "${1}: never the '\\'' escape" "'\\''" "$(pasted)"
  check "${1}: the pasted text is what wrap_run_log_text gives" "$(wrap_run_log_text '' "${2}")" "$(pasted)"
  check "${1}: one bracketed paste, no send-keys of the text" "" "$(cat "${T}/send-keys" 2>/dev/null | awk '!/^-t %5 Enter$/')"
  contains "${1}: the paste is bracketed" "-p" "$(cat "${T}/paste-flags" 2>/dev/null)"
}

# --- the three forms of /ari-driving-tmux's Command layout ---

expect_typed "no single quotes" "kubectl get pods -o wide" "run_log 'kubectl get pods -o wide'"

expect_typed "single quotes alone" "rg 'foo' src" "run_log \"rg 'foo' src\""

heredoc_cmd="echo 'it''s' \"\$HOME\""
expect_typed "single quotes and a \$" "${heredoc_cmd}" "run_log \"\$(command cat <<'RUN_LOG'
${heredoc_cmd}
RUN_LOG
)\""

long_cmd="kubectl get pods --all-namespaces --output wide --selector 'app.kubernetes.io/name=web' | awk '\$4 != \"Running\" {print \$1, \$2}'"
run "${T}/home" --cmd "${long_cmd}"
check "a long command: exits 0" 0 "${rc}"
contains "a long command: typed as the quoted heredoc" "run_log \"\$(command cat <<'RUN_LOG'" "$(pasted)"
check "a long command: the heredoc holds the layout wrap_command gives" "$(wrap_command "${long_cmd}")" "$(awk 'f && /^RUN_LOG$/ {exit} f {print} /^run_log / {f = 1}' "${T}/pasted")"
check "a long command: the pasted text is what wrap_run_log_text gives" "$(wrap_run_log_text '' "${long_cmd}")" "$(pasted)"

# --- the typed text, read by zsh, hands run_log the command ---

run_log() { print -r -- "${1}"; }
check "the double-quoted form hands run_log the command" "rg 'foo' src" "$(eval "run_log \"rg 'foo' src\"")"
run "${T}/home" --cmd "${heredoc_cmd}"
check "the heredoc form hands run_log the command" "${heredoc_cmd}" "$(eval "$(pasted)")"
unfunction run_log

# --- the bare forms ---

run "${T}/home" --no-run-log --cmd "rg 'foo' src;"
check "--no-run-log: exits 0" 0 "${rc}"
check "--no-run-log: pastes the command bare, its trailing ; kept" "rg 'foo' src;" "$(pasted)"
check "--no-run-log: echoes it under TYPED:" "rg 'foo' src;" "$(typed_lines)"

run "${T}/nolog" --cmd "rg 'foo' src"
check "no run_log on the host: exits 0" 0 "${rc}"
check "no run_log on the host: pastes the command bare" "rg 'foo' src" "$(pasted)"
contains "no run_log on the host: says so" "NOTE: no ${T}/nolog/.config/bin/run_log on the host; typed the command bare" "${out}"

# --- a text over several lines goes into zsh only; one line goes anywhere the gate passes ---

run "${T}/home" FAKE_FG=fish --cmd "${heredoc_cmd}"
check "a heredoc into fish: exits 75" 75 "${rc}"
check "a heredoc into fish: pastes nothing" "" "$(pasted)"
contains "a heredoc into fish: says why" "REFUSED: ID=%5|pane=1.1 the command is laid out over several lines, which only zsh reads as one; fish runs there" "${out}"
contains "a heredoc into fish: the kind is not_zsh" $'\nREFUSED_KIND: not_zsh\n' "${out}"
contains "a heredoc into fish: the log names the kind" "kind='not_zsh'" "$(<"${T}/err")"
check "a heredoc into fish: no TYPED line" "" "$(typed_lines)"

run "${T}/home" FAKE_FG=bash --cmd "rg 'foo' src"
check "one line into bash: exits 0" 0 "${rc}"
check "one line into bash: pastes the double-quoted form" "run_log \"rg 'foo' src\"" "$(pasted)"

# --- a failed paste and a failed Enter have their own codes ---

run "${T}/home" FAKE_PASTE_FAILS=1 --cmd "echo hi"
check "a failed paste: exits 73" 73 "${rc}"
contains "a failed paste: says nothing is on the line" "FAILED: paste into ID=%5|pane=1.1; nothing is on the line" "${out}"
check "a failed paste: no TYPED line" "" "$(typed_lines)"
contains "a failed paste: the log says resend once" "resend once" "$(<"${T}/err")"

run "${T}/home" FAKE_ENTER_FAILS=1 --cmd "echo hi"
check "a failed Enter: exits 74" 74 "${rc}"
check "a failed Enter: the text was pasted" "run_log 'echo hi'" "$(pasted)"
contains "a failed Enter: says the text is on the line" "FAILED: Enter to ID=%5|pane=1.1; the text is on the line" "${out}"
contains "a failed Enter: the log says to tell Ari" "tell Ari, as for --no-enter" "$(<"${T}/err")"

# --- the dry run prints the text verbatim ---

run "${T}/home" --dry-run --cmd "${heredoc_cmd}"
check "a dry run: exits 0" 0 "${rc}"
check "a dry run: pastes nothing" "" "$(pasted)"
check "a dry run: WOULD TYPE holds the text verbatim" "$(wrap_run_log_text '' "${heredoc_cmd}")" "$(print -r -- "${out}" | awk '/^WOULD TYPE \(bare\):/ {f = 0} f {print} /^WOULD TYPE \(when/ {f = 1}')"
contains "a dry run: WOULD TYPE holds the bare command last" $'WOULD TYPE (bare):\n'"${heredoc_cmd}" "${out}"

# --- a capture pastes nothing ---

run "${T}/home" --cmd ''
check "an empty --cmd: exits 0" 0 "${rc}"
check "an empty --cmd: pastes nothing" "" "$(pasted)"
check "an empty --cmd: no TYPED line" "" "$(typed_lines)"

print -- "${pass} passed, ${fail} failed"
if (( fail > 0 )); then print -u2 -- "--- run.zsh stdout and stderr of the last run:"; print -u2 -r -- "${out}"; cat "${T}/err" >&2; exit 1; fi
