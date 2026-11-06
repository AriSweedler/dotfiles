#!/usr/bin/env zsh
# Tests for the per-skill claim (lib/claim.zsh) and its callers: init.zsh takes
# it, record_blobs.zsh and commit_blobs.zsh refuse while another live driver
# holds it. Everything runs against a throwaway investigation root
# (SKILL_UPDATE_ROOT); the real skills are read, never written.
# Not covered here: a real commit releasing the claim (it needs a tier repo);
# release_claim's calls are covered through claim_release.

set -euo pipefail

readonly SCRIPT_DIR="${0:A:h}"
readonly SKILLS_DIR="${HOME}/.claude/skills"
readonly BIN="${SCRIPT_DIR:h}/bin"
readonly LIB_LOGGING="${SKILLS_DIR}/ari-skill-shellscripts/lib/logging.zsh"
if [[ ! -r "${LIB_LOGGING}" ]]; then
  print -u2 "[ERROR] missing shared logging lib | path='${LIB_LOGGING}'"
  exit 1
fi
source "${LIB_LOGGING}"

TEST_ROOT="$(mktemp -d)"; readonly TEST_ROOT="${TEST_ROOT:A}"
trap 'rm -rf -- "${TEST_ROOT}"' EXIT
export SKILL_UPDATE_ROOT="${TEST_ROOT}"
export SKILL_UPDATE_CLAIM_STALE_SECONDS=3600
unset DRY_RUN

source "${SCRIPT_DIR:h}/lib/blobs.zsh"
source "${SCRIPT_DIR:h}/lib/claim.zsh"

PASS=0
FAIL=0

#######################################
# Record one check.
# Arguments:
#   $1 - name
#   $2 - expected
#   $3 - actual
#######################################
expect() {
  local name="${1}" want="${2}" got="${3}"
  if [[ "${want}" == "${got}" ]]; then
    PASS=$(( PASS + 1 ))
    print -- "PASS  ${name}"
    return
  fi
  FAIL=$(( FAIL + 1 ))
  print -- "FAIL  ${name}  want='${want}' got='${got}'"
}

#######################################
# Run a command, print its exit code.
# Arguments: the command
#######################################
rc_of() {
  local rc=0
  "$@" >/dev/null 2>&1 || rc=$?
  print -r -- "${rc}"
}

#######################################
# Make a driver's investigation folder holding one file, print its path.
# Arguments:
#   $1 - skill
#   $2 - driver name
#######################################
mk_driver() {
  local dir="${TEST_ROOT}/${1}/${2}"
  mkdir -p "${dir}"
  print -r -- x > "${dir}/scratchpad.md"
  print -r -- "${dir}"
}

#######################################
# Age a path (and, for a folder, its files) to N seconds ago.
# Arguments:
#   $1 - target
#   $2 - seconds
#######################################
age() {
  local target="${1}" seconds="${2}" stamp
  stamp="$(date -r $(( EPOCHSECONDS - seconds )) +%Y%m%d%H%M.%S)"
  find "${target}" -exec touch -h -t "${stamp}" {} +
}

# --- lib: take, hold, refuse ---
a="$(mk_driver s1 a)"; b="$(mk_driver s1 b)"
expect "take on a free skill" "taken" "$(claim_take s1 "${a}" false)"
expect "owner is the taker" "${a}" "$(claim_owner s1)"
expect "retake by the owner renews" "renewed" "$(claim_take s1 "${a}" false)"
expect "a second live driver is refused" "held ${a}" "$(claim_take s1 "${b}" false || true)"
expect "refusal exit code" "1" "$(rc_of claim_take s1 "${b}" false)"
expect "blocker for the other driver" "${a}" "$(claim_blocker s1 "${b}")"
expect "no blocker for the owner" "" "$(claim_blocker s1 "${a}")"
expect "a skill's claim does not block another skill" "" "$(claim_blocker s2 "${b}")"

# --- lib: takeover, release ---
expect "takeover from a live driver" "taken-over" "$(claim_take s1 "${b}" true)"
expect "owner after takeover" "${b}" "$(claim_owner s1)"
claim_release s1 "${a}"
expect "release by a non-owner keeps the claim" "${b}" "$(claim_owner s1)"
claim_release s1 "${b}"
expect "release by the owner removes it" "" "$(claim_owner s1)"
expect "release with no claim is fine" "0" "$(rc_of claim_release s1 "${b}")"

# --- lib: stale handling ---
c="$(mk_driver s3 c)"; d="$(mk_driver s3 d)"
claim_take s3 "${c}" false >/dev/null
age "${c}" 7200
age "$(claim_path s3)" 7200
expect "an idle owner's claim is stale" "0" "$(rc_of claim_is_stale s3)"
expect "a stale claim blocks nobody" "" "$(claim_blocker s3 "${d}")"
expect "take over a stale claim" "taken-stale" "$(claim_take s3 "${d}" false)"
expect "owner after stale take" "${d}" "$(claim_owner s3)"
expect "a fresh claim is not stale" "1" "$(rc_of claim_is_stale s3)"

e="$(mk_driver s4 e)"; f="$(mk_driver s4 f)"
claim_take s4 "${e}" false >/dev/null
age "$(claim_path s4)" 7200
touch "${e}/scratchpad.md"
expect "recent work in the owner's folder keeps the claim live" "${e}" "$(claim_blocker s4 "${f}")"
rm -rf "${e}"
expect "a claim whose folder is gone is stale" "0" "$(rc_of claim_is_stale s4)"
expect "no owner reads as stale" "0" "$(rc_of claim_is_stale s-none)"

# --- lib: races and bad claims ---
g="$(mk_driver s5 g)"; h="$(mk_driver s5 h)"; i="$(mk_driver s5 i)"; j="$(mk_driver s5 j)"
claim_take s5 "${g}" false >/dev/null
age "${g}" 7200
age "$(claim_path s5)" 7200
for w in h i j; do ( claim_take s5 "${(P)w}" false >"${TEST_ROOT}/s5.${w}" 2>&1 || true ) & done
wait
expect "parallel stale steals: exactly one winner" "1" "$(cat "${TEST_ROOT}"/s5.[hij] | grep -c "^taken-stale$" || true)"
expect "parallel stale steals: the claim names a winner" "1" "$(print -l "${h:A}" "${i:A}" "${j:A}" | grep -cx "$(claim_owner s5)" || true)"
mkdir -p "${TEST_ROOT}/s6/.claim"
expect "a claim that is a directory is refused" "1" "$(rc_of claim_take s6 "${g}" false)"
expect "a relative owner is stored absolute" "${g:A}" "$(cd "${g:h}" && claim_take s7 "${g:t}" false >/dev/null; claim_owner s7)"

# --- init.zsh ---
out="$(zsh "${BIN}/init.zsh" --skill ari-skill-update 2>/dev/null)"
inv="$(print -r -- "${out}" | awk -F= '$1 == "investigation_dir" { print $2 }')"
expect "init takes the claim" "taken" "$(print -r -- "${out}" | awk -F= '$1 == "claim" { print $2 }')"
expect "init's folder owns the skill" "${inv:A}" "$(claim_owner ari-skill-update | { read -r p; print -r -- "${p:A}"; })"
expect "a second init is refused" "1" "$(rc_of zsh "${BIN}/init.zsh" --skill ari-skill-update)"
expect "the refusal creates no folder" "1" "$(ls -d "${TEST_ROOT}/ari-skill-update"/*(/N) | wc -l | tr -d ' ')"
expect "refusal names the holder" "1" "$(zsh "${BIN}/init.zsh" --skill ari-skill-update 2>&1 >/dev/null | grep -c "owner='${inv}'" || true)"
sleep 1
out2="$(zsh "${BIN}/init.zsh" --skill ari-skill-update --takeover 2>/dev/null)"
expect "--takeover claims it" "taken-over" "$(print -r -- "${out2}" | awk -F= '$1 == "claim" { print $2 }')"

# --- init.zsh over a stale claim ---
age "$(claim_path ari-skill-update)" 7200
age "$(claim_owner ari-skill-update)" 7200
sleep 1
out3="$(zsh "${BIN}/init.zsh" --skill ari-skill-update 2>/dev/null)"
expect "init takes a stale claim" "taken-stale" "$(print -r -- "${out3}" | awk -F= '$1 == "claim" { print $2 }')"
out2="${out3}"

# --- record_blobs.zsh and commit_blobs.zsh ---
inv2="$(print -r -- "${out2}" | awk -F= '$1 == "investigation_dir" { print $2 }')"
record=(zsh "${BIN}/record_blobs.zsh" --skill ari-skill-update --tier df --message m)
expect "record by the owner passes the claim check (dry run)" "0" "$(rc_of "${record[@]}" --investigation-dir "${inv2}" --dry-run)"
expect "record in a dry run takes no claim change" "${inv2:A}" "$(claim_owner ari-skill-update | { read -r p; print -r -- "${p:A}"; })"
expect "record by another driver is refused, even as a dry run" "1" "$(rc_of "${record[@]}" --investigation-dir "${inv}" --dry-run)"
expect "record by another driver is refused under --execute" "1" "$(rc_of "${record[@]}" --investigation-dir "${inv}" --execute)"
expect "the refused record wrote nothing" "0" "$(print -l "${inv}"/*.commit.md(N) | awk "NF" | wc -l | tr -d ' ')"

blob="100644:$(printf '0%.0s' {1..40}):x"
commit=(zsh "${BIN}/commit_blobs.zsh" --skill ari-skill-update --tier df --base-tree none --message m --blob "${blob}" --dry-run)
refused="$("${commit[@]}" --claim-dir "${inv}" 2>/dev/null || true)"
expect "commit by another driver is refused" "result=refused" "$(print -r -- "${refused}" | awk 'NR == 1')"
expect "commit refusal names the holder" "claim_holder=${inv2}" "$(print -r -- "${refused}" | awk 'NR == 2')"

# --- shared lib files in a proposal ---
# A throwaway HOME holds a dotfiles repo with one skill and two lib files; the real
# registry and logging libs are linked in. Every script runs against it via env.
FAKE="${TEST_ROOT}/home"
mkdir -p "${FAKE}/.claude/skills" "${FAKE}/.config/claude/skills/tskill" "${FAKE}/.config/claude/lib" "${FAKE}/.config/claude/other"
ln -s "${SKILLS_DIR}/ari-skill-shellscripts" "${FAKE}/.claude/skills/ari-skill-shellscripts"
ln -s "${SKILLS_DIR}/ari-dotfiles-skill-registry" "${FAKE}/.claude/skills/ari-dotfiles-skill-registry"
ln -s "${SCRIPT_DIR:h}" "${FAKE}/.claude/skills/ari-skill-update"
ln -s "${FAKE}/.config/claude/skills/tskill" "${FAKE}/.claude/skills/tskill"
print -r -- '[user]
	name = t
	email = t@example.com
[alias]
	df = dotfiles
	dotfiles = !git --git-dir="$HOME/dotfiles.git/" --work-tree="$HOME"' > "${FAKE}/.gitconfig"
fenv=(env -u DRY_RUN HOME="${FAKE}" SKILL_UPDATE_ROOT="${TEST_ROOT}")
"${fenv[@]}" git init -q --bare "${FAKE}/dotfiles.git"
print -r -- one > "${FAKE}/.config/claude/skills/tskill/SKILL.md"
print -r -- one > "${FAKE}/.config/claude/lib/a.sh"
print -r -- one > "${FAKE}/.config/claude/lib/b.sh"
print -r -- one > "${FAKE}/.config/claude/other/y.sh"
"${fenv[@]}" git -C "${FAKE}" df add .config/claude
"${fenv[@]}" git -C "${FAKE}" df commit -q -m init

#######################################
# Record a proposal for tskill with the given extra record flags; print the
# recorded Commit command as one line-continued command.
# Arguments:
#   $1 - investigation folder
#   $@ - extra record_blobs.zsh flags
#######################################
record_t() {
  local inv="${1}"
  shift
  "${fenv[@]}" zsh "${BIN}/record_blobs.zsh" --skill tskill --tier df --message tmsg --investigation-dir "${inv}" --execute "$@" >/dev/null 2>&1
  awk '!/^```/' "${inv}/tskill.commit.md"
}

#######################################
# Run a recorded command string against the fake home; print its result= line.
# Arguments:
#   $1 - the command
#######################################
run_cmd() {
  "${fenv[@]}" zsh -c "${1}" 2>/dev/null | awk -F= '$1 == "result" { print $2 }'
}

head_of() { "${fenv[@]}" git -C "${FAKE}" df rev-parse HEAD; }

t1="$(mk_driver tskill t1)"
print -r -- two >> "${FAKE}/.config/claude/skills/tskill/SKILL.md"
print -r -- two >> "${FAKE}/.config/claude/lib/a.sh"
cmd1="$(record_t "${t1}" --edited SKILL.md --shared "${FAKE}/.config/claude/lib/a.sh")"
expect "record: one command per tier, skill and shared blobs both named" "1 1 1" "$(print -r -- "${cmd1}" | awk '/--blob/ { b += 1 } /--shared / { s += 1 } /commit_blobs.zsh/ { c += 1 } END { print c, b, s }')"
expect "record: the diff names the lib file" "1" "$(grep -c '^diff --git a/.config/claude/lib/a.sh' "${t1}/tskill.diff.patch" || true)"
before="$(head_of)"
expect "commit without --execute is a dry run" "dry-run" "$(run_cmd "${cmd1%--execute}")"
expect "the dry run committed nothing" "${before}" "$(head_of)"
expect "commit lands skill and lib together" "committed" "$(run_cmd "${cmd1}")"
expect "one commit holds both files" "2" "$("${fenv[@]}" git -C "${FAKE}" df show --name-only --format= HEAD | wc -l | tr -d ' ')"
expect "the lib file is committed as recorded" "" "$("${fenv[@]}" git -C "${FAKE}" df status --short -- .config/claude/lib/a.sh .config/claude/skills/tskill)"
expect "a re-run reports already-committed" "already-committed" "$(run_cmd "${cmd1}")"

t2="$(mk_driver tskill t2)"
print -r -- three >> "${FAKE}/.config/claude/lib/a.sh"
cmd2="$(record_t "${t2}" --shared "${FAKE}/.config/claude/lib/a.sh")"
print -r -- four >> "${FAKE}/.config/claude/lib/a.sh"
claim_release tskill "${t2}"
before="$(head_of)"
expect "a lib file changed after recording is refused" "refused" "$(run_cmd "${cmd2}")"
expect "the refusal committed nothing" "${before}" "$(head_of)"
expect "the refusal names the lib file" "1" "$("${fenv[@]}" zsh -c "${cmd2}" 2>/dev/null | grep -c '^mismatched=@shared:.config/claude/lib/a.sh$' || true)"

t3="$(mk_driver tskill t3)"
"${fenv[@]}" git -C "${FAKE}" df checkout -q -- .config/claude/lib/a.sh
print -r -- five >> "${FAKE}/.config/claude/lib/b.sh"
cmd3="$(record_t "${t3}" --shared "${FAKE}/.config/claude/lib/b.sh")"
print -r -- six > "${FAKE}/.config/claude/lib/b.sh"
"${fenv[@]}" git -C "${FAKE}" df add .config/claude/lib/b.sh
"${fenv[@]}" git -C "${FAKE}" df commit -q -m moved
print -r -- one > "${FAKE}/.config/claude/lib/b.sh"
print -r -- five >> "${FAKE}/.config/claude/lib/b.sh"
before="$(head_of)"
expect "a lib file HEAD changed since recording is refused" "refused" "$(run_cmd "${cmd3}")"
expect "that refusal committed nothing" "${before}" "$(head_of)"

claim_release tskill "${t3}"
t4="$(mk_driver tskill t4)"
print -r -- two >> "${FAKE}/.config/claude/other/y.sh"
expect "record refuses a shared file outside the allowed roots" "1" "$(rc_of "${fenv[@]}" zsh "${BIN}/record_blobs.zsh" --skill tskill --tier df --message m --investigation-dir "${t4}" --execute --shared "${FAKE}/.config/claude/other/y.sh")"
expect "record refuses a path that escapes the root" "1" "$(rc_of "${fenv[@]}" zsh "${BIN}/record_blobs.zsh" --skill tskill --tier df --message m --investigation-dir "${t4}" --execute --shared "${FAKE}/.config/claude/lib/../other/y.sh")"
forged="zsh ${BIN}/commit_blobs.zsh --skill tskill --tier df --base-tree none --message m --shared none:100644:$(printf '1%.0s' {1..40}):.config/claude/other/y.sh --execute"
expect "commit refuses a hand-written shared path outside the roots" "1" "$(rc_of "${fenv[@]}" zsh -c "${forged}")"
expect "record refuses --shared for the local tier (it has no shared root)" "1" "$(rc_of "${fenv[@]}" zsh "${BIN}/record_blobs.zsh" --skill tskill --tier ldf --message m --investigation-dir "${t4}" --shared "${FAKE}/.config/claude/lib/b.sh")"

t5="$(mk_driver tskill t5)"
print -r -- new > "${FAKE}/.config/claude/lib/c.sh"
cmd5="$(record_t "${t5}" --shared .config/claude/lib/c.sh --shared "${FAKE}/.config/claude/lib/c.sh")"
expect "record: a HOME-relative new lib file, named twice, becomes one --shared" "1" "$(print -r -- "${cmd5}" | grep -c -- '--shared ' || true)"
expect "commit lands a new lib file" "committed" "$(run_cmd "${cmd5}")"
expect "the new lib file is in HEAD" "1" "$("${fenv[@]}" git -C "${FAKE}" df ls-tree HEAD .config/claude/lib/c.sh | wc -l | tr -d ' ')"
expect "commit refuses a malformed --shared value" "1" "$(rc_of "${fenv[@]}" zsh "${BIN}/commit_blobs.zsh" --skill tskill --tier df --base-tree none --message m --shared .config/claude/lib/c.sh --execute)"

print -- "summary  pass=${PASS} fail=${FAIL}"
(( FAIL == 0 ))
