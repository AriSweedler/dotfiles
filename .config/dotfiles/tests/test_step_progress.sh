#!/usr/bin/env bash
# How a run is shown. Plain (no tty): the runner's log lines on stderr and the table on stdout,
# exactly as before, and the same log lines in $RUN_DIR/run.log. Fancy (the ARI_DOTFILES_UI seam
# and a fake gum): a header, one line per step, the roll-up, the log lines only in run.log, gum
# only for spinners, never in a step; --json stays summary.json.
set -u
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

world_new
world_use_fixture satisfied
seed_fake_repos
seed_ldf_remote
seed_home_baseline
export BOB_SHIM_LS="Installed: v0.11.2 Used"
ONLY="dotfiles_repo,local_dotfiles_repo,bob_neovim,claude,karabiner"

# Timestamps, run ids and durations are the only bytes allowed to differ between two renderings.
mask() { /usr/bin/sed -E 's/\[[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:.]+Z\]/[TS]/g; s/[0-9]{8}T[0-9]{6}/RUNID/g'; }
strip_ansi() { /usr/bin/sed -E $'s/\x1b\\[[0-9;?]*[a-zA-Z]//g'; }
# Paths as human lines show them (ui::paths, in this world): each XDG base, then the home directory.
show_paths() {
  local s="$1" v d
  for v in XDG_DATA_HOME XDG_STATE_HOME XDG_CACHE_HOME XDG_CONFIG_HOME HOME; do
    for d in / "'" '"' ' '; do s="${s//"${!v}${d}"/"\$${v}${d}"}"; done
    [[ "${s}" != *"${!v}" ]] || s="${s%"${!v}"}\$${v}"
  done
  printf '%s' "${s}"
}
# main's run::print_human with each detail's paths as ui::paths shows them: the plain table.
old_table() {
  local step_status step reason detail applied
  while IFS=$'\t' read -r step_status step reason applied detail; do
    detail="$(show_paths "${detail}")"
    if [[ "${applied}" == would_apply ]]; then
      printf '%-6s %-22s %-26s would run apply::%s  %s\n' "${step_status}" "${step}" "${reason}" "${step}" "${detail}"
    else
      printf '%-6s %-22s %-26s %s\n' "${step_status}" "${step}" "${reason}" "${detail}"
    fi
  done < <(jq -r '.steps[] | [.status, .step, .reason, (.applied|tostring), (.detail | split("\n")[0])] | @tsv' "$1")
  printf 'status: %s (%s)\n' "$(jq -r '.status' "$1")" "$(jq -r '.counts | to_entries | map("\(.key)=\(.value)") | join(" ")' "$1")"
}

# ── Plain healthcheck: stdout is main's table, stderr is the runner's lines, run.log holds them ──
nm healthcheck --only "${ONLY}"
RUN="$(newest_run_dir)"
assert_eq "plain healthcheck exits 0" 0 "${RC}"
assert_eq "plain stdout is main's table, byte for byte" "$(old_table "${RUN}/summary.json")" "${OUT}"
assert_contains "plain table: an XDG path as its variable" "${OUT}" "file='\$XDG_CONFIG_HOME/karabiner/karabiner.json'"
assert_contains "plain table: a home path as \$HOME" "${OUT}" "git_dir='\$HOME/dotfiles.git'"
assert_contains "summary.json keeps the raw path" "$(cat "${RUN}/summary.json")" "${HOME}/.config/karabiner/karabiner.json"
assert_file "the run writes run.log" "${RUN}/run.log"
assert_eq "plain stderr is exactly run.log, timestamps masked" "$(mask < "${RUN}/run.log")" "$(printf '%s' "${ERR}" | mask)"
LOG="$(cat "${RUN}/run.log")"
assert_contains "run.log has the run header" "${LOG}" "run | mode='check'"
for s in ${ONLY//,/ }; do
  assert_contains "run.log has ==> ${s}" "${LOG}" "==> ${s}"
  assert_contains "run.log has check | step='${s}'" "${LOG}" "check | step='${s}' status="
done
assert_not_contains "run.log is plain text" "${LOG}" $'\e['
assert_contains "run.log keeps raw paths" "${LOG}" "run_dir='${ARI_DOTFILES_STATE_DIR}/runs/"
assert_not_contains "a plain run has no glyphs" "${OUT}" "✓"

# ── Plain init --dry-run: the table first, then status; the dry-run warning still on stderr ──
bump_now_secs 60
nm init --dry-run --only bob_neovim,claude
RUN="$(newest_run_dir)"
assert_eq "plain init --dry-run exits 0" 0 "${RC}"
TABLE="$(old_table "${RUN}/summary.json")"
assert_eq "plain init --dry-run starts with main's table" "${TABLE}" "$(head -n "$(printf '%s\n' "${TABLE}" | wc -l)" "${FIX}/nm.out")"
assert_contains "dry-run warning stays on stderr" "${ERR}" "dry-run: no changes will be made"
assert_contains "and lands in run.log" "$(cat "${RUN}/run.log")" "dry-run: no changes will be made"
assert_eq "every run.log line is on stderr, in order" "$(mask < "${RUN}/run.log")" \
  "$(printf '%s\n' "${ERR}" | mask | grep -F -x -f <(mask < "${RUN}/run.log"))"

# ── Fancy (seam + fake gum, no tty): one line per step, no table, logs only in run.log ──
FAKE_GUM="${FIX}/fakegum"
printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> "%s/gum.log"\n' "${FIX}" > "${FAKE_GUM}"
chmod +x "${FAKE_GUM}"
export ARI_DOTFILES_UI=fancy ARI_DOTFILES_GUM="${FAKE_GUM}"
bump_now_secs 60
nm healthcheck --only "${ONLY}"
RUN="$(newest_run_dir)"
PLAIN_OUT="$(printf '%s' "${OUT}" | strip_ansi)"
assert_eq "fancy healthcheck exits as plain does" 0 "${RC}"
assert_eq "fancy header: verb and step count" "healthcheck · 5 steps" "$(head -n 1 <<< "${PLAIN_OUT}")"
assert_contains "fancy groups get a heading" "${PLAIN_OUT}" $'\nrepo\n'
assert_contains "fancy line for a step" "${PLAIN_OUT}" "✓ dotfiles_repo"
assert_contains "fancy step line: paths as ui::paths shows them, before the clip" "${PLAIN_OUT}" "git_dir='\$HOME/dotfiles.git' hooks='\$XDG_CON"
assert_eq "one line per step" 5 "$(grep -v '^✓ all ' <<< "${PLAIN_OUT}" | grep -c -E '^(✓|!|✗|‼|–) ')"
assert_contains "fancy ends with the roll-up" "$(tail -n 2 <<< "${PLAIN_OUT}" | head -n 1)" "status: ok (ok=5)"
assert_eq "then the all-ok line (test_fix_rollup.sh)" "✓ all 5 steps ok" "$(tail -n 1 <<< "${PLAIN_OUT}")"
assert_not_contains "fancy prints no table" "${PLAIN_OUT}" "ok     dotfiles_repo"
assert_not_contains "fancy stderr has no runner lines" "${ERR}" "==> "
assert_contains "fancy run.log still has them" "$(cat "${RUN}/run.log")" "==> claude"
GUMS="$(cat "${FIX}/gum.log" 2>/dev/null)"
assert_eq "gum is only ever a spinner" "" "$(grep -E '^(style|join|choose|format|table|log|input|confirm) ' <<< "${GUMS}")"
# Side by side, a check already done when its turn comes has its spinner stopped (gum TERMed)
# before a fake gum can log, so here it is at most one per check; the serial run below counts.
assert_eq "side by side: every spinner names a check" "" \
  "$(grep '^spin ' <<< "${GUMS}" | grep -v -E -- '--title (dotfiles_repo|local_dotfiles_repo|bob_neovim|claude|karabiner) · checking ')"
assert_eq "side by side: no more than a spinner per check" 1 "$(( $(grep -c '^spin ' <<< "${GUMS}") <= 5 ))"
cp "${RUN}/summary.json" "${FIX}/fancy-summary.json"
assert_json "summary.json unchanged in shape" "${FIX}/fancy-summary.json" '.steps|length' 5
FANCY_OUT="$(printf '%s' "${OUT}" | strip_ansi | /usr/bin/sed -E 's/[0-9]+\.[0-9]+s$/Ns/')"

# One at a time, each check outlasts the fake gum's start, so each spinner is logged.
rm -f "${FIX}/gum.log"
bump_now_secs 60
ARI_DOTFILES_SERIAL=1 nm healthcheck --only "${ONLY}"
GUMS="$(cat "${FIX}/gum.log" 2>/dev/null)"
assert_contains "a spinner per check" "${GUMS}" "--title claude · checking"
assert_eq "a spinner per check, no more" 5 "$(grep -c '^spin ' <<< "${GUMS}")"
assert_eq "serial fancy lines are the side-by-side ones" "${FANCY_OUT}" \
  "$(printf '%s' "${OUT}" | strip_ansi | /usr/bin/sed -E 's/[0-9]+\.[0-9]+s$/Ns/')"

# --json under the fancy seam: stdout is summary.json and nothing else, no spinner.
rm -f "${FIX}/gum.log"
bump_now_secs 60
nm healthcheck --only "${ONLY}" --json
RUN="$(newest_run_dir)"
assert_eq "--json is summary.json, byte for byte" "$(cat "${RUN}/summary.json")" "${OUT}"
assert_contains "--json keeps raw paths" "${OUT}" "${HOME}/.config/karabiner/karabiner.json"
assert_not_contains "--json has no \$XDG_" "${OUT}" '$XDG_'
assert_contains "--json keeps the log lines on stderr" "${ERR}" "==> claude"
assert_no_file "--json runs no gum" "${FIX}/gum.log"

# init --dry-run under the fancy seam: the header names the dry run.
bump_now_secs 60
nm init --dry-run --only bob_neovim,claude
PLAIN_OUT="$(printf '%s' "${OUT}" | strip_ansi)"
assert_eq "fancy init header says dry-run" "init · 2 steps · dry-run" "$(head -n 1 <<< "${PLAIN_OUT}")"
unset ARI_DOTFILES_UI ARI_DOTFILES_GUM
assert_no_file "lock released" "${ARI_DOTFILES_STATE_DIR}/lock.d"

report
