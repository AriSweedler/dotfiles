#!/usr/bin/env zsh
# Proves the session-actor claim guard against the real bd, in a throwaway workspace under mktemp:
# another session's claim, unclaim and close are refused, the same session's go through, a bare
# `claude` claim is nobody's session, a named release by a new session works, the prefix aborts with no
# session id. Never touches a real workspace.
# Run: zsh $HOME/.claude/skills/ari-bead-driven-development/tests/claim_actor.test.zsh
set -euo pipefail

readonly SCRIPT_DIR="${0:A:h}"
readonly SKILLS_DIR="${HOME}/.claude/skills"
readonly LIB_LOGGING="${SKILLS_DIR}/ari-skill-shellscripts/lib/logging.zsh"
if [[ ! -r "${LIB_LOGGING}" ]]; then
  print -u2 "[ERROR] missing shared logging lib | path='${LIB_LOGGING}'"
  exit 1
fi
source "${LIB_LOGGING}"

unset BEADS_DIR BEADS_DB BEADS_ACTOR BEADS_DOLT_SERVER_HOST 2>/dev/null || true
readonly SESSION_A="claude:6efd6194-3949-4fd7-9dc2-ce7b1287ad40"
readonly SESSION_B="claude:0b8f2c64-7d1e-4c3a-9a55-2f1d6e8b7c10"
readonly REASON="twenty or more characters of evidence"

typeset -i passed=0 failed=0

expect_rc() {
  local name="${1}" want="${2}" got="${3}"
  if [[ "${want}" == "${got}" ]]; then
    passed=$(( passed + 1 ))
    log::info "ok | test='${name}'"
    return 0
  fi
  failed=$(( failed + 1 ))
  log::err "FAIL | test='${name}' want_rc='${want}' got_rc='${got}'"
}

expect_assignee() {
  local name="${1}" want="${2}" got
  got="$(bd show "${3}" --json | jq -r '.[0].assignee // ""')"
  if [[ "${want}" == "${got}" ]]; then
    passed=$(( passed + 1 ))
    log::info "ok | test='${name}'"
    return 0
  fi
  failed=$(( failed + 1 ))
  log::err "FAIL | test='${name}' want_assignee='${want}' got_assignee='${got}'"
}

expect_count() {
  expect_rc "${1}" "${2}" "${3}"
}

as() {
  local actor="${1}"
  shift
  BEADS_ACTOR="${actor}" bd "$@" >/dev/null 2>&1 && return 0
  return $?
}

new_claimed_bead() {
  local actor="${1}" id
  id="$(BEADS_ACTOR="${actor}" bd create "claim test" -t task -p 2 --silent 2>/dev/null)"
  as "${actor}" update "${id}" --claim
  print -r -- "${id}"
}

main() {
  local missing=() cmd
  for cmd in bd git jq; do
    command -v "${cmd}" >/dev/null || missing+=("${cmd}")
  done
  if (( ${#missing} > 0 )); then
    log::err "Missing required commands | missing='${(j:, :)missing}'"
    return 1
  fi

  local work
  work="$(mktemp -d "${TMPDIR:-/tmp}/bead-claim-actor.XXXXXX")"
  trap "rm -rf '${work}'" EXIT
  cd "${work}"
  git init -q .
  as test-setup init --prefix clm --quiet || { log::err "bd init failed in the throwaway workspace | dir='${work}'"; return 1; }

  local id rc
  id="$(new_claimed_bead "${SESSION_A}")"
  expect_assignee "a claim as the session sets the assignee to its actor" "${SESSION_A}" "${id}"

  rc=0; as "${SESSION_A}" update "${id}" --claim || rc=$?
  expect_rc "the same session re-claiming is idempotent" 0 "${rc}"

  rc=0; as "${SESSION_B}" update "${id}" --claim || rc=$?
  expect_rc "another session's --claim is refused" 1 "${rc}"
  expect_assignee "the refused claim left the holder alone" "${SESSION_A}" "${id}"

  rc=0; as "${SESSION_B}" unclaim "${id}" --if-assignee "${SESSION_B}" || rc=$?
  expect_rc "another session's unclaim --if-assignee is refused" 1 "${rc}"
  expect_assignee "the refused unclaim left the holder alone" "${SESSION_A}" "${id}"

  rc=0; as "${SESSION_B}" update "${id}" --title "stolen" --if-assignee "${SESSION_B}" || rc=$?
  expect_rc "another session's update guard exits 13" 13 "${rc}"

  rc=0; as "${SESSION_B}" update "${id}" --title "renamed by another session" || rc=$?
  expect_rc "an unguarded update by another session goes through" 0 "${rc}"
  rc=0; as "${SESSION_B}" comment "${id}" "a comment" || rc=$?
  expect_rc "a comment by another session goes through" 0 "${rc}"

  rc=0; as "Ari Sweedler" close "${id}" --reason "${REASON}" || rc=$?
  expect_rc "a person's close of a session claim is refused" 1 "${rc}"


  rc=0; as "${SESSION_B}" close "${id}" --reason "${REASON}" || rc=$?
  expect_rc "another session's close is refused" 1 "${rc}"

  rc=0; as claude close "${id}" --reason "${REASON}" || rc=$?
  expect_rc "a bare claude close of a session claim is refused" 1 "${rc}"

  rc=0; as "${SESSION_A}" close "${id}" --reason "${REASON}" || rc=$?
  expect_rc "the holding session closes its own claim" 0 "${rc}"

  id="$(new_claimed_bead "${SESSION_A}")"
  rc=0; as "${SESSION_A}" unclaim "${id}" --if-assignee "${SESSION_A}" || rc=$?
  expect_rc "the holding session releases its own claim" 0 "${rc}"
  expect_assignee "the released bead has no assignee" "" "${id}"

  id="$(new_claimed_bead claude)"
  rc=0; as "${SESSION_A}" update "${id}" --claim || rc=$?
  expect_rc "a session cannot claim over a bare claude claim" 1 "${rc}"
  rc=0; as "${SESSION_A}" unclaim "${id}" --if-assignee "${SESSION_A}" || rc=$?
  expect_rc "a session's actor does not release a bare claude claim" 1 "${rc}"
  rc=0; as claude unclaim "${id}" --if-assignee claude || rc=$?
  expect_rc "the legacy form releases a bare claude claim" 0 "${rc}"

  id="$(new_claimed_bead "${SESSION_A}")"
  rc=0; as "${SESSION_B}" unclaim "${id}" --if-assignee "${SESSION_A}" || rc=$?
  expect_rc "a new session releases an old claim once it names the holder's string" 0 "${rc}"
  expect_assignee "the named release cleared the assignee" "" "${id}"

  id="$(new_claimed_bead "${SESSION_A}")"
  rc=0; as "Ari Sweedler" unclaim "${id}" --force || rc=$?
  expect_rc "a person's unclaim --force releases a session claim" 0 "${rc}"

  rc=0; env -u CLAUDE_CODE_SESSION_ID zsh -c 'BEADS_ACTOR="claude:${CLAUDE_CODE_SESSION_ID:?no session id}" bd create "never filed" -t task --silent' >/dev/null 2>&1 || rc=$?
  expect_rc "the prefix aborts with no session id" 1 "${rc}"
  expect_count "the aborted prefix filed nothing" 0 "$(bd list --title-contains 'never filed' --json 2>/dev/null | jq 'length' || print 0)"

  cat <<EOF
passed=${passed}
failed=${failed}
EOF
  (( failed == 0 ))
}

main "$@"
