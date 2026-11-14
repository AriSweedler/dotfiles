#!/usr/bin/env zsh
# Every --cmd refusal at exit 75 or 77 prints 'REFUSED_KIND: <kind>' on the line right after its REFUSED: text,
# one kind per gate reason, and its exit code follows from the kind; no other exit prints one. The REFUSED:
# words are checked too, for the callers that still read them. The real tmux-pane lib runs under the local
# definition (and once over a fake ssh) against a fake tmux on PATH whose pane state each case sets; every
# kind the lib gate can give is checked against --help; the lib, not run.zsh, decides each kind. --refusal-kinds
# prints exactly run.zsh's KIND_* constants and the lib's gate kinds, one per row of SKILL.md's gate table; it runs no
# tmux or ssh, writes nothing, and prints nothing beside another argument or a broken lib.
# No tmux server, no ssh, no network.
# Run: zsh $HOME/.claude/skills/ari-driving-remote/tests/run-refusal-kind.test.zsh

set -uo pipefail

readonly SCRIPT_DIR="${0:A:h}"
readonly RUN_ZSH="${SCRIPT_DIR:h}/bin/run.zsh"
readonly LIB_TMUX_PANE="${XDG_CONFIG_HOME:-${HOME}/.config}/claude/lib/tmux-pane.sh"
readonly FAKE_PID="run-refusal-kind-test-$$"
# Where tmux_pane_lock puts this fake server's lock for pane %5: '<ARI_DRIVING_LOCK_ROOT>/<pid>-<pane>'.
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

readonly T="$(mktemp -d)"
trap 'rm -rf "${T}" "${LOCK_DIR}"' EXIT
mkdir -p "${T}/bin" "${T}/data" "${T}/state" "${T}/cache"

# The fake tmux: one pane, %5, whose state comes from FAKE_OPT_IN (on), FAKE_MODE and FAKE_SYNC (0), FAKE_FG (zsh),
# FAKE_EARLIER (the pane's earlier output), FAKE_LAST (its last line, 'home ❯'), FAKE_INPUT_FAILS (set: tmux cannot
# read the pane's mode) and FAKE_PANE_GONE (set: %5 closes after it resolved; real tmux then answers the opt-in
# lookup with nothing, and list-panes without it). It answers the buffer commands, so a pane that passes the
# gate is typed into.
cat > "${T}/bin/tmux" <<'FAKE'
#!/usr/bin/env zsh
case "${1}" in
  list-sessions|send-keys|load-buffer|paste-buffer|delete-buffer) exit 0 ;;
  list-panes)
    if [[ -n "${FAKE_PANE_GONE:-}" && -e "${FAKE_STATE}/resolved" ]]; then print -r -- '%9'; exit 0; fi
    : > "${FAKE_STATE}/resolved"
    print -r -- '%5'; exit 0 ;;
  show-options)
    [[ -z "${FAKE_PANE_GONE:-}" ]] || exit 1
    if [[ "${@[-1]}" == @ari_driving ]]; then print -r -- "${FAKE_OPT_IN:-on}"; fi
    exit 0 ;;
  display-message)
    case "${@[-1]}" in
      *pane_in_mode*) [[ -z "${FAKE_INPUT_FAILS:-}" ]] || exit 1; print -r -- "${FAKE_MODE:-0} ${FAKE_SYNC:-0}" ;;
      *pane_current_command*) print -r -- "${FAKE_FG:-zsh}" ;;
      *'#{pid}'*) print -r -- "${FAKE_PID}" ;;
      *pane_id*) print -r -- 'ID=%5|pane=1.1' ;;
    esac
    exit 0 ;;
  capture-pane) print -r -- "${FAKE_EARLIER:-earlier output}"; print -r -- "${FAKE_LAST:-home ❯}"; exit 0 ;;
esac
exit 1
FAKE
# The fake ssh: drops the options and the host and runs the command in zsh, a Mac's login shell (run-put.test.zsh).
cat > "${T}/bin/ssh" <<'FAKE'
#!/usr/bin/env zsh
exec zsh -c "${@[-1]}"
FAKE
chmod +x "${T}/bin/tmux" "${T}/bin/ssh"

run() {   # <env…> -- [run.zsh flags…]; stdout on $out, exit code on $rc; a --cmd into %5 on the local definition
  local -a env_args=()
  while [[ "${1}" != "--" ]]; do env_args+=("${1}"); shift; done
  shift
  rm -f "${T}/resolved"
  out="$(env "${env_args[@]}" FAKE_PID="${FAKE_PID}" FAKE_STATE="${T}" PATH="${T}/bin:${PATH}" CLAUDE_CODE_SESSION_ID=test-session \
    XDG_DATA_HOME="${T}/data" XDG_STATE_HOME="${T}/state" XDG_CACHE_HOME="${T}/cache" LOG_COLOR=0 \
    zsh "${RUN_ZSH}" --host-definition "${DEF:-here}" --host "${DEF_HOST:-local}" --path-prefix '' --target %5 --no-run-log --no-wait \
    --cmd 'echo hi' --execute "$@" 2>"${T}/err")"; rc=$?
}

line_after_refused() {   # the line right after the first REFUSED: line of $out, or ''
  local -a lines=("${(@f)out}")
  local i
  for (( i = 1; i < ${#lines}; i++ )); do
    if [[ "${lines[i]}" == 'REFUSED: '* ]]; then print -r -- "${lines[i+1]}"; return 0; fi
  done
}

line_count() {   # <pattern>: how many lines of $out match it
  local -a matched=(${(M)${(f)out}:#${~1}})
  print -r -- "${#matched}"
}

typeset -a seen_kinds=()   # every kind a case below made run.zsh print, for the --refusal-kinds check
expect_kind() {   # <case> <exit code> <kind> <words the REFUSED: line keeps>
  seen_kinds+=("${3}")
  check "${1}: exits ${2}" "${2}" "${rc}"
  check "${1}: the line after REFUSED: is the kind" "REFUSED_KIND: ${3}" "$(line_after_refused)"
  check "${1}: one REFUSED_KIND line" 1 "$(line_count 'REFUSED_KIND: *')"
  contains "${1}: the REFUSED: words are unchanged" "${4}" "${out}"
  contains "${1}: the log names the kind" "kind='${3}'" "$(<"${T}/err")"
  check "${1}: nothing typed, no TYPED line" 0 "$(line_count 'TYPED: *')"
}

# --- one case per kind ---

run FAKE_OPT_IN=off --
expect_kind "not opted in" 77 not_opted_in "not opted in; Ari runs 'ari-driving on' in that pane"

run FAKE_MODE=1 --
expect_kind "copy mode" 75 copy_mode "in copy mode (press q there)"

run FAKE_SYNC=1 --
expect_kind "synchronized" 75 synchronized "synchronize-panes is on"

run FAKE_FG=vim --
expect_kind "not a shell" 75 not_a_shell "running vim, not a shell"

run 'FAKE_LAST=home ❯ git status' --
expect_kind "text on the line" 75 not_at_prompt "last line does not end in the prompt"

run 'FAKE_LAST=Compiling 3 of 9' --
expect_kind "a command running" 75 not_at_prompt "last line does not end in the prompt"

run FAKE_INPUT_FAILS=1 --
expect_kind "tmux cannot read the pane" 75 pane_gone "no such pane"

mkdir -p "${LOCK_DIR}"
date +%s > "${LOCK_DIR}/at"
run --
rm -rf "${LOCK_DIR}"
expect_kind "another caller holds the lock" 75 other_caller "another caller is typing into it"

DEF=remote DEF_HOST=fake@host run FAKE_FG=vim --
expect_kind "not a shell, over ssh into a zsh login shell" 75 not_a_shell "running vim, not a shell"

# --- the kind is the line after REFUSED:, never a stale one in the pane tail ---

run FAKE_MODE=1 'FAKE_EARLIER=REFUSED_KIND: not_a_shell' --
check "a stale kind in the tail: the line after REFUSED: still wins" "REFUSED_KIND: copy_mode" "$(line_after_refused)"
contains "a stale kind in the tail: the log names the real kind" "kind='copy_mode'" "$(<"${T}/err")"

run 'FAKE_EARLIER=REFUSED_KIND: copy_mode' --
check "a stale kind in an idle pane's tail: exits 0" 0 "${rc}"
lacks "a stale kind in an idle pane's tail: no kind is logged" "kind=" "$(<"${T}/err")"

# --- a pane that closed after it resolved is a 70 with the inventory, not a 77 ---

run FAKE_PANE_GONE=1 --
check "a pane gone during the gate: exits 70" 70 "${rc}"
contains "a pane gone during the gate: says no pane matches" "REFUSED: no pane matches %5" "${out}"
contains "a pane gone during the gate: prints the inventory" "PANES: every pane on the host" "${out}"
check "a pane gone during the gate: no REFUSED_KIND line" 0 "$(line_count 'REFUSED_KIND: *')"

# --- a pane the gate passes prints no kind ---

run --
check "an idle pane: exits 0" 0 "${rc}"
check "an idle pane: no REFUSED_KIND line" 0 "$(line_count 'REFUSED_KIND: *')"
check "an idle pane: the command was typed" 1 "$(line_count 'TYPED: echo hi')"

# --- no --execute: the gate runs, the keys do not go ---

rm -rf "${T}/state/ari-driving-remote/bindings"
out="$(env FAKE_PID="${FAKE_PID}" FAKE_STATE="${T}" PATH="${T}/bin:${PATH}" CLAUDE_CODE_SESSION_ID=test-session XDG_DATA_HOME="${T}/data" XDG_STATE_HOME="${T}/state" XDG_CACHE_HOME="${T}/cache" LOG_COLOR=0 \
  zsh "${RUN_ZSH}" --host-definition here --host local --path-prefix '' --target %5 --no-run-log --no-wait --cmd 'echo hi' 2>"${T}/err")"; rc=$?
check "a dry run exits 0" 0 "${rc}"
check "a dry run prints WOULD TYPE" 1 "$(line_count 'WOULD TYPE:')"
contains "a dry run prints the text under WOULD TYPE" $'WOULD TYPE:\necho hi' "${out}"
check "a dry run types nothing: no TYPED line" 0 "$(line_count 'TYPED: *')"
check "a dry run ends with the DRY RUN line" 1 "$(line_count 'DRY RUN: nothing was typed*')"
check "a dry run leaves no pane lock" "no" "$([[ -e "${LOCK_DIR}" ]] && print yes || print no)"
check "a dry run binds no pane" "" "$(ls "${T}/state/ari-driving-remote/bindings" 2>/dev/null)"
contains "a dry run names the rerun with --execute" "--execute" "$(<"${T}/err")"

out="$(env FAKE_OPT_IN=off FAKE_PID="${FAKE_PID}" FAKE_STATE="${T}" PATH="${T}/bin:${PATH}" CLAUDE_CODE_SESSION_ID=test-session XDG_DATA_HOME="${T}/data" XDG_STATE_HOME="${T}/state" XDG_CACHE_HOME="${T}/cache" LOG_COLOR=0 \
  zsh "${RUN_ZSH}" --host-definition here --host local --path-prefix '' --target %5 --no-run-log --no-wait --cmd 'echo hi' 2>"${T}/err")"; rc=$?
check "a dry run still hits the gate: not opted in exits 77" 77 "${rc}"

# --- every kind the lib's gate can give is named in --help, and run.zsh holds no reason-to-kind table ---

help_text="$(zsh "${RUN_ZSH}" --help 2>/dev/null)"
kinds=(${=$(. "${LIB_TMUX_PANE}"; print -r -- "${ARI_DRIVING_GATE_KINDS}")})
check "the lib's gate holds six kinds" 6 "${#kinds}"
for kind in "${kinds[@]}"; do
  contains "--help names the kind '${kind}'" "${kind}" "${help_text}"
done
contains "--help names the kind 'lock_unavailable'" lock_unavailable "${help_text}"
lacks "run.zsh keeps no reason-to-kind table" GATE_REASON_KINDS "$(<"${RUN_ZSH}")"
contains "--help names --refusal-kinds" "--refusal-kinds" "${help_text}"

# --- --refusal-kinds: every kind, one per line, read-only ---
# Its PATH holds a tmux and an ssh that only leave a mark, so a call to either shows; XDG dirs point at an empty tree.

mkdir -p "${T}/marking-bin" "${T}/rk"
for tool in tmux ssh; do
  print -r -- "#!/usr/bin/env zsh"$'\n'": > ${(qq)T}/rk/${tool}-called; exit 1" > "${T}/marking-bin/${tool}"
  chmod +x "${T}/marking-bin/${tool}"
done
out="$(env PATH="${T}/marking-bin:${PATH}" XDG_DATA_HOME="${T}/rk/data" XDG_STATE_HOME="${T}/rk/state" XDG_CACHE_HOME="${T}/rk/cache" LOG_COLOR=0 \
  zsh "${RUN_ZSH}" --refusal-kinds 2>"${T}/err")"; rc=$?
printed=(${(f)out})
check "--refusal-kinds exits 0" 0 "${rc}"
check "--refusal-kinds logs nothing" "" "$(<"${T}/err")"
not_kinds=(${(M)printed:#*[^a-z_]*})
unique=(${(u)printed})
check "--refusal-kinds prints only kinds, one per line" 0 "${#not_kinds}"
check "--refusal-kinds prints each kind once" "${#printed}" "${#unique}"
check "--refusal-kinds: not_opted_in, the 77, comes first" not_opted_in "${printed[1]:-}"
check "--refusal-kinds runs no tmux and no ssh" "" "$(ls "${T}/rk" | awk '/-called$/')"
check "--refusal-kinds writes no definition, binding or cache" "" "$(ls "${T}/rk" | awk '!/-called$/')"

# The kinds run.zsh can emit: its literal KIND_* constants (KIND_NOT_OPTED_IN is the lib's, so a '$' value is
# skipped) and the lib's gate kinds. The printed list is exactly that set.
own_kinds=(${(f)"$(awk '/^readonly KIND_[A-Z_]+=/ && !/\$/ { sub(/^readonly KIND_[A-Z_]+=/, ""); sub(/[ \t].*/, ""); print }' "${RUN_ZSH}")"})
check "the KIND_* scrape of run.zsh found constants" 1 "$(( ${#own_kinds} > 0 ))"
emitted=("${own_kinds[@]}" "${kinds[@]}")
check "--refusal-kinds is exactly run.zsh's KIND_* constants and the lib's gate kinds" \
  "${(j: :)${(@ou)emitted}}" "${(j: :)${(@o)printed}}"
for kind in ${(u)seen_kinds}; do
  check "--refusal-kinds lists '${kind}', which a case above made run.zsh print" 1 "$(( ${printed[(Ie)${kind}]} > 0 ))"
done
for kind in "${printed[@]}"; do
  contains "--help names '${kind}', which --refusal-kinds prints" "${kind}" "${help_text}"
done

out="$(env -i HOME="${HOME}" PATH="${T}/marking-bin:/usr/bin:/bin" zsh "${RUN_ZSH}" --refusal-kinds 2>"${T}/err")"; rc=$?
check "--refusal-kinds under env -i exits 0 with the same list" "0 ${(j: :)printed}" "${rc} ${(j: :)${(f)out}}"

# SKILL.md's gate table holds one row per kind: a kind without a row leaves Claude with no next action.
table_kinds=(${(f)"$(awk -F'|' '/^### The gate/ { on = 1; next } on && /^### / { on = 0 } on && $2 ~ /^ `[a-z_]+` $/ && $3 ~ /^ 7[57] $/ { gsub(/[ `]/, "", $2); print $2 }' "${SCRIPT_DIR:h}/SKILL.md")"})
check "SKILL.md's gate table has one row per --refusal-kinds kind" "${(j: :)${(@o)printed}}" "${(j: :)${(@o)table_kinds}}"

# Another argument is refused, in either order, with nothing on stdout: a stray --cmd is never dropped with exit 0.
for order in "--refusal-kinds --execute" "--execute --refusal-kinds" "--cmd x --refusal-kinds"; do
  out="$(env PATH="${T}/marking-bin:${PATH}" XDG_DATA_HOME="${T}/rk/data" XDG_STATE_HOME="${T}/rk/state" XDG_CACHE_HOME="${T}/rk/cache" LOG_COLOR=0 \
    zsh "${RUN_ZSH}" ${=order} 2>"${T}/err")"; rc=$?
  check "'${order}' exits 1" 1 "${rc}"
  check "'${order}' prints nothing on stdout" "" "${out}"
done

# A tmux-pane.sh that lost its gate kinds, or holds a malformed one: a non-zero exit and nothing on stdout, never part of a list.
mkdir -p "${T}/xdg-missing/claude/lib" "${T}/xdg-bad/claude/lib"
for lib_case in missing bad; do   # the logging lib loads its plugins from the same XDG_CONFIG_HOME
  ln -s "${XDG_CONFIG_HOME:-${HOME}/.config}/zsh" "${T}/xdg-${lib_case}/zsh"
done
awk '!/^ARI_DRIVING_GATE_KINDS=/' "${LIB_TMUX_PANE}" > "${T}/xdg-missing/claude/lib/tmux-pane.sh"
awk '{ print } /^ARI_DRIVING_GATE_KINDS=/ { print "ARI_DRIVING_GATE_KINDS=\"$ARI_DRIVING_GATE_KINDS Bad-Kind\"" }' "${LIB_TMUX_PANE}" > "${T}/xdg-bad/claude/lib/tmux-pane.sh"
for lib_case in missing bad; do
  out="$(env XDG_CONFIG_HOME="${T}/xdg-${lib_case}" XDG_DATA_HOME="${T}/rk/data" XDG_STATE_HOME="${T}/rk/state" XDG_CACHE_HOME="${T}/rk/cache" LOG_COLOR=0 \
    zsh "${RUN_ZSH}" --refusal-kinds 2>"${T}/err")"; rc=$?
  check "a lib with ${lib_case} gate kinds: --refusal-kinds fails" 1 "$(( rc != 0 ))"
  check "a lib with ${lib_case} gate kinds: nothing on stdout" "" "${out}"
done
contains "a malformed kind is named in the log" "Refusal kind list is broken" "$(<"${T}/err")"

print -- "${pass} passed, ${fail} failed"
if (( fail > 0 )); then print -u2 -- "--- run.zsh stdout and stderr of the last run:"; print -u2 -r -- "${out}"; cat "${T}/err" >&2; exit 1; fi
