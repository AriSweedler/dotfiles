#!/usr/bin/env zsh
# Automated tests for bin/watch-merge.zsh with a stubbed gh and sleep on PATH: no network, no waiting.
# Cases: a refused merge logs "Merge refused" and never "parameter not set"; a dry run logs "would run"
# and never calls gh pr merge; a merge that lands counts both its mutations.
# Run: zsh $HOME/.claude/skills/ari-parallel-play/tests/watch-merge.test.zsh
set -uo pipefail

readonly SCRIPT="${HOME}/.claude/skills/ari-parallel-play/bin/watch-merge.zsh"
readonly T="$(mktemp -d "${TMPDIR:-/tmp}/watch-merge-test.XXXXXX")"
trap 'rm -rf "${T}"' EXIT
mkdir -p "${T}/bin"

cat > "${T}/bin/gh" <<'STUB'
#!/usr/bin/env zsh
args="$*"
print -r -- "${args}" >> "${STUB_LOG}"
case "${args}" in
  "auth token"*)                  print tok ;;
  "pr list"*)                     print 7 ;;
  "pr view"*"--json state"*)      if [[ -e "${STUB_MERGED_FLAG}" ]]; then print MERGED; else print OPEN; fi ;;
  "pr view"*"--json mergeable"*)  print CONFLICTING ;;
  "pr merge"*)
    if [[ "${STUB_MERGE}" == "ok" ]]; then touch "${STUB_MERGED_FLAG}"
    else print -u2 "Pull request is not mergeable"; exit 1; fi ;;
  "api -X DELETE"*)               ;;
  api*)                           print abc123 ;;
  "run list"*)                    print "99 completed success" ;;
  "run watch"*)                   ;;
  "run view"*)                    printf 'success\tci-ok:success\n' ;;
esac
STUB
printf '#!/bin/sh\nexit 0\n' > "${T}/bin/sleep"
chmod +x "${T}/bin/gh" "${T}/bin/sleep"

typeset -i pass=0 fail=0
check() {   # <name> <want> <got>
  if [[ "${2}" == "${3}" ]]; then (( pass++ )); print -- "ok      ${1}"
  else (( fail++ )); print -- "FAIL    ${1} | want='${2}' got='${3}'"; fi
}
contains() {   # <name> <needle> <haystack>
  if [[ "${3}" == *"${2}"* ]]; then (( pass++ )); print -- "ok      ${1}"
  else (( fail++ )); print -- "FAIL    ${1} | needle='${2}' in='${3}'"; fi
}
lacks() {   # <name> <needle> <haystack>
  if [[ "${3}" != *"${2}"* ]]; then (( pass++ )); print -- "ok      ${1}"
  else (( fail++ )); print -- "FAIL    ${1} | unwanted='${2}' in='${3}'"; fi
}

typeset -g out="" rc=0 calls=""
run_watcher() {   # <merge outcome: ok|refuse> [extra watcher flags]
  local merge="${1}"; shift
  rm -f "${T}/merged" "${T}/calls"
  out="$(PATH="${T}/bin:${PATH}" LOG_COLOR=0 DRY_RUN= STUB_LOG="${T}/calls" STUB_MERGED_FLAG="${T}/merged" STUB_MERGE="${merge}" \
    zsh "${SCRIPT}" --branch b --read-user u --repo o/r "$@" 2>&1)"
  rc=$?
  calls="$(cat "${T}/calls" 2>/dev/null || true)"
}

run_watcher refuse --execute
check "refused merge: the watcher ends in failure" 1 "${rc}"
contains "refused merge: logs Merge refused" "Merge refused" "${out}"
contains "refused merge: carries the merge output" "Pull request is not mergeable" "${out}"
lacks "refused merge: no unset parameter" "parameter not set" "${out}"

run_watcher refuse
check "dry run: exits 0" 0 "${rc}"
contains "dry run: logs would run for the merge" "would run | cmd=" "${out}"
lacks "dry run: gh pr merge never called" "pr merge" "${calls}"
contains "dry run: dry_run=1" "dry_run=1" "${out}"
contains "dry run: counts the merge and the branch delete" "changes=2" "${out}"

run_watcher ok --execute
check "executed merge: exits 0" 0 "${rc}"
contains "executed merge: merged=true" "merged=true" "${out}"
contains "executed merge: counts the merge in the caller and the delete" "changes=2" "${out}"

print -- "summary  pass=${pass} fail=${fail}"
(( fail == 0 ))
