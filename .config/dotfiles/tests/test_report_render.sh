#!/usr/bin/env bash
# report::render against the golden files under fixtures/GOLDEN_ENV, and report::fingerprint's
# invariants (permutation-proof, item-sensitive, warn-blind, empty on a pass).
#
#   ARI_DOTFILES_BLESS_GOLDEN=1 bash tests/test_report_render.sh   # rewrite the goldens from the renderer
set -u
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

world_new
world_use_fixture satisfied
FX="${TESTS_DIR}/fixtures"

genv=()
while IFS= read -r line || [[ -n "${line}" ]]; do
  [[ -n "${line}" && "${line}" != \#* ]] && genv+=("${line}")
done < "${FX}/GOLDEN_ENV"

# render <summary> <log> [render flags] → $FIX/render.out under the pinned golden environment
render() {
  RC=0
  env "${genv[@]}" zsh -c 'for f in "$1"/*.zsh(N); do source "${f}"; done; source "$2"; shift 2; "$@"' _ \
    "${ORIG_CONFIG_DIR}/dotfiles/lib" "${ORIG_CONFIG_DIR}/dotfiles/cmd/verify/report.zsh" report::render "$@" > "${FIX}/render.out" 2> "${FIX}/render.err" || RC=$?
  ERR="$(cat "${FIX}/render.err")"
}

check_golden() {
  local name="$1" golden="$2"
  if (( RC == 0 )); then pass "${name}: render exits 0"; else fail "${name}: render exits 0" "rc=${RC} ${ERR}"; fi
  if [[ "${ARI_DOTFILES_BLESS_GOLDEN:-0}" == 1 ]]; then
    cp "${FIX}/render.out" "${golden}"
    pass "${name}: golden blessed at ${golden}"
    return
  fi
  if [[ ! -f "${golden}" ]]; then
    fail "${name}: golden present" "missing ${golden} (create it with ARI_DOTFILES_BLESS_GOLDEN=1 once the render is reviewed)"
    return
  fi
  if cmp -s "${golden}" "${FIX}/render.out"; then pass "${name}: byte-for-byte equal to the golden"
  else fail "${name}: byte-for-byte equal to the golden" "$(diff "${golden}" "${FIX}/render.out" | head -n 40)"; fi
}

render "${FX}/summary-fail.json" "${FX}/log.txt"
check_golden "fail report" "${FX}/report-golden.md"
out="$(cat "${FIX}/render.out")"
assert_contains "fail: marker line" "$(head -n 1 "${FIX}/render.out")" "<!-- new-machine-report v1 fingerprint="
assert_contains "fail: marker kind" "$(head -n 1 "${FIX}/render.out")" "kind=fail"
assert_contains "fail: title" "${out}" "# new-machine weekly check FAILED — testhost, 2026-09-10 00:26"
assert_contains "fail: What failed" "${out}" "## What failed"
assert_contains "fail: a row per item" "${out}" "| dotfiles_jobs | job sync | no description line | local |"
assert_contains "fail: a row for a step without items" "${out}" "| claude | — | claude_missing — claude not on PATH | — |"
assert_not_contains "fail: no brew sections" "${out}" "brew items"
assert_contains "fail: also noted" "${out}" "## Also noted"
assert_contains "fail: raw log tail" "${out}" "## Raw log (last 40 lines)"
assert_contains "fail: feed to Claude" "${out}" "## How to feed this to Claude"
assert_contains "fail: the Claude line reads the report" "${out}" 'claude "Read /tmp/nmtest/home/Desktop/new-machine-FAILED.md'
assert_contains "fail: prior-fix grep recipe" "${out}" "git df log --oneline --grep='fix(new-machine/<step>)'"
assert_contains "fail: commit header rule" "${out}" 'fix(new-machine/<step>): <what was wrong, one line>'
assert_contains "fail: the Claude line points at the rules" "${out}" 'check prior fixes with git df log first'
assert_contains "fail: fixed section" "${out}" '## What "fixed" looks like'

# The manual font instructions never reach the weekly notes.
assert_not_contains "manual_font never reaches the weekly notes" "${out}" "terminal_nerdfont:"

render "${FX}/summary-error.json" "${FX}/log.txt"
check_golden "error report" "${FX}/report-error-golden.md"
out="$(cat "${FIX}/render.out")"
assert_contains "error: marker kind" "$(head -n 1 "${FIX}/render.out")" "kind=error"
assert_contains "error: title" "${out}" "# new-machine weekly check COULD NOT RUN — testhost, 2026-09-10 00:26"
assert_contains "error: section" "${out}" "## The check itself could not run"
assert_contains "error: neovim row" "${out}" "| neovim | timed_out |"
assert_contains "error: Claude task" "${out}" "Diagnose why 'dotfiles healthcheck' cannot run on this machine and fix it; do not silence the check."

# ── fingerprint ───────────────────────────────────────────────────────────────
fp() { zfn report.zsh report::fingerprint "$@"; printf '%s' "${OUT}"; }
base="$(fp "${FX}/summary-fail.json")"
if [[ "${base}" =~ ^[0-9a-f]{16}$ ]]; then pass "fingerprint is 16 hex chars"; else fail "fingerprint is 16 hex chars" "'${base}'"; fi

jq '.steps |= reverse | .steps[].items |= (if . == null then . else reverse end)' "${FX}/summary-fail.json" > "${FIX}/permuted.json"
assert_eq "identical under permuted steps and items" "${base}" "$(fp "${FIX}/permuted.json")"

jq '(.steps[] | select(.step=="dotfiles_jobs") | .items[0].name) = "sync2"' "${FX}/summary-fail.json" > "${FIX}/changed.json"
changed="$(fp "${FIX}/changed.json")"
if [[ "${changed}" != "${base}" && -n "${changed}" ]]; then pass "changes when one item changes"; else fail "changes when one item changes" "'${changed}'"; fi

jq '(.steps[] | select(.step=="local_dotfiles_repo") | .detail) = "7 unpushed commits"
    | (.steps[] | select(.step=="karabiner") | .items) = [{kind: "formula", name: "x", problem: "y"}]' "${FX}/summary-fail.json" > "${FIX}/warned.json"
assert_eq "unchanged when only a warn step changes" "${base}" "$(fp "${FIX}/warned.json")"

jq '.steps |= map(if .status == "fail" then .status = "ok" | .items = [] else . end) | .status = "ok"' "${FX}/summary-fail.json" > "${FIX}/passing.json"
assert_eq "empty when nothing failed" "" "$(fp "${FIX}/passing.json")"

error_fp="$(fp "${FX}/summary-error.json" error)"
if [[ "${error_fp}" =~ ^[0-9a-f]{16}$ ]]; then pass "error fingerprint is 16 hex chars"; else fail "error fingerprint is 16 hex chars" "'${error_fp}'"; fi
jq '(.steps[] | select(.step=="neovim") | .reason) = "crashed"' "${FX}/summary-error.json" > "${FIX}/error2.json"
if [[ "$(fp "${FIX}/error2.json" error)" != "${error_fp}" ]]; then pass "error fingerprint follows the reason"; else fail "error fingerprint follows the reason" "unchanged"; fi

report
