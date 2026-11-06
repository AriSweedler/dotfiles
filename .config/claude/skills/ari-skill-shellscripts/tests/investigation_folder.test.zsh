#!/usr/bin/env zsh
# Tests for lib/investigation_folder.zsh: a fresh folder per call, even within one second.
# zsh $HOME/.claude/skills/ari-skill-shellscripts/tests/investigation_folder.test.zsh

set -euo pipefail

readonly SCRIPT_DIR="${0:A:h}"
source "${SCRIPT_DIR:h}/lib/investigation_folder.zsh"

TEST_ROOT="$(mktemp -d)"; readonly TEST_ROOT
trap 'rm -rf -- "${TEST_ROOT}"' EXIT

typeset -i pass=0 fail=0
check() {   # <name> <want> <got>
  if [[ "${2}" == "${3}" ]]; then (( pass += 1 )); print -- "ok      ${1}"
  else (( fail += 1 )); print -- "FAIL    ${1} | want='${2}' got='${3}'"; fi
}

# A frozen clock forces every call into the same second.
readonly STAMP=20260101T000000Z
date() { print -r -- "${STAMP}"; }

typeset -a dirs=()
for i in 1 2 3; do
  dirs+=("$(mk_investigation_dir "${TEST_ROOT}" demo)")
done
check "first call keeps the bare stamp" "${STAMP}" "${dirs[1]:t}"
check "second call in the same second gets -2" "${STAMP}-2" "${dirs[2]:t}"
check "third call gets -3" "${STAMP}-3" "${dirs[3]:t}"
check "every folder exists" 3 "$(ls -d "${dirs[@]}" | wc -l | tr -d ' ')"

mkdir -p "${TEST_ROOT}/hand/${STAMP}"
check "a hand-made stamp folder is skipped, not reused" "${STAMP}-2" "$(basename "$(mk_investigation_dir "${TEST_ROOT}" hand)")"

typeset -a pids=()
for i in 1 2 3 4 5 6; do
  mk_investigation_dir "${TEST_ROOT}" par >"${TEST_ROOT}/out.${i}" &
  pids+=($!)
done
typeset -i bad=0
for p in "${pids[@]}"; do wait "${p}" || bad+=1; done
check "six concurrent calls all succeed" 0 "${bad}"
check "six concurrent calls make six folders" 6 "$(cat "${TEST_ROOT}"/out.* | sort -u | wc -l | tr -d ' ')"

touch "${TEST_ROOT}/blocked"
err="$(mk_investigation_dir "${TEST_ROOT}/blocked" s 2>&1 >/dev/null)" && rc=0 || rc=$?
check "a file in the way fails with 1" 1 "${rc}"
check "the failure names the parent" 1 "$([[ "${err}" == *"[ERROR] cannot create parent"* ]] && print 1 || print 0)"

date() { return 1; }
rc=0; mk_investigation_dir "${TEST_ROOT}" nodate >/dev/null 2>&1 || rc=$?
check "a failing date fails with 1" 1 "${rc}"

print -- "summary  pass=${pass} fail=${fail}"
(( fail == 0 ))
