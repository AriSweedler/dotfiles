#!/usr/bin/env zsh
# Regression: --help must print the help and exit 0 whatever the environment holds. The help heredoc expands
# the script's constants under set -u, and an example that read $SCRATCHPAD killed it with 'SCRATCHPAD:
# parameter not set' when the variable was unset (2026-11-03); an environment variable in the help is
# literal, never expanded, so the text is the same on every machine. No tmux, no ssh, no network.
# Run: zsh $HOME/.claude/skills/ari-driving-remote/tests/run-help.test.zsh

set -uo pipefail

readonly SCRIPT_DIR="${0:A:h}"
readonly RUN_ZSH="${SCRIPT_DIR:h}/bin/run.zsh"
readonly SENTINEL=/sentinel/scratchpad-that-must-not-appear

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
trap 'rm -rf "${T}"' EXIT

run() {   # <env…> -- <args…>; stdout on $out, exit code on $rc; every XDG dir points into the temp tree
  local -a env_args=()
  while [[ "${1}" != "--" ]]; do env_args+=("${1}"); shift; done
  shift
  out="$(env "${env_args[@]}" XDG_DATA_HOME="${T}/data" XDG_STATE_HOME="${T}/state" XDG_CACHE_HOME="${T}/cache" LOG_COLOR=0 \
    zsh "${RUN_ZSH}" "$@" 2>"${T}/err")"; rc=$?
}

# --- SCRATCHPAD unset: the case that died ---

run -u SCRATCHPAD -- --help
check "--help with SCRATCHPAD unset exits 0" 0 "${rc}"
contains "--help lists --put" "--put FILE" "${out}"
contains "--help lists --cmd" "--cmd TEXT" "${out}"
contains "--help lists --list" "--list " "${out}"
check "--help with SCRATCHPAD unset prints no 'parameter not set'" "" "$(awk '/parameter not set/ { print }' "${T}/err")"

run -u SCRATCHPAD -- -h
check "-h with SCRATCHPAD unset exits 0" 0 "${rc}"
contains "-h prints the same help" "--put FILE" "${out}"

# --- the environment variables in the examples are literal, never expanded ---

run SCRATCHPAD="${SENTINEL}" -- --help
check "--help with SCRATCHPAD set exits 0" 0 "${rc}"
lacks "--help does not expand SCRATCHPAD" "${SENTINEL}" "${out}"
contains "--help shows the \$SCRATCHPAD example literally" '--put "$SCRATCHPAD/body.md"' "${out}"
contains "--help shows the \$HOME invocation literally" 'zsh $HOME/.claude/skills/ari-driving-remote/bin/run.zsh --hosts' "${out}"
lacks "--help does not expand HOME" "${HOME}/.claude/skills/ari-driving-remote" "${out}"
contains "--help shows \$CLAUDE_CODE_SESSION_ID literally" '$CLAUDE_CODE_SESSION_ID' "${out}"
lacks "--help examples take a %N target, not 2.4" "--target 2.4" "${out}"
lacks "--help examples take a %N target, not 4.1" "--target 4.1" "${out}"

# --- an empty environment: the whole class of unset variables, not one ---

run -i HOME="${HOME}" PATH="${PATH}" -- --help
check "--help under env -i exits 0" 0 "${rc}"
check "--help under env -i prints no 'parameter not set'" "" "$(awk '/parameter not set/ { print }' "${T}/err")"
contains "--help under env -i lists --put" "--put FILE" "${out}"

print -- "${pass} passed, ${fail} failed"
if (( fail > 0 )); then print -u2 -- "--- run.zsh stderr of the last run:"; cat "${T}/err" >&2; exit 1; fi
