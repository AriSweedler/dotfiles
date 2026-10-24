#!/usr/bin/env bash
# The end of a run names what needs attention and the command that fixes it. Plain: main's table
# and status line unchanged, then `fix    <step>  <fix>` per step that failed or errored, warned
# with a fix, or is manual; the manual WARN blocks stay on stderr. Fancy (the ARI_DOTFILES_UI seam
# and a fake gum): one box titled with the count, the manual details inside it and not on stderr;
# an all-ok run gets one green line. --json stays summary.json.
set -u
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

world_new
world_use_fixture satisfied
seed_fake_repos
seed_ldf_remote
seed_home_baseline
export BOB_SHIM_LS="Installed: v0.11.2 Used"
ONLY="dotfiles_repo,local_dotfiles_repo,bob_neovim,claude"

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
# main's run::print_human with each detail's paths as ui::paths shows them.
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
fix_lines() { grep '^fix    ' <<< "${OUT}" || true; }

# ── All ok: no fix line, stdout is main's table byte for byte ──
nm healthcheck --only "${ONLY}"
RUN="$(newest_run_dir)"
assert_eq "all-ok run exits 0" 0 "${RC}"
assert_eq "all-ok: stdout is main's table, nothing added" "$(old_table "${RUN}/summary.json")" "${OUT}"
assert_eq "all-ok: no fix line" "" "$(fix_lines)"

# ── A fail with a fix and a warn with a fix: one line each, after the status line, in run order ──
export BOB_SHIM_LS="v0.11.2"
TRACKED="${HOME}/$(df_git ls-files | head -n 1)"
printf '\n# local edit\n' >> "${TRACKED}"
bump_now_secs 60
nm healthcheck --only "${ONLY}"
RUN="$(newest_run_dir)"
assert_eq "a fail exits 1" 1 "${RC}"
assert_eq "plain stdout is main's table, then the fix lines" \
  "$(old_table "${RUN}/summary.json")"$'\n'"fix    dotfiles_repo  git df status"$'\n'"fix    bob_neovim  dotfiles apply bob_neovim" "${OUT}"
assert_contains "the fail's fix is its verdict's" "$(fix_lines)" "fix    bob_neovim  dotfiles apply bob_neovim"
assert_contains "a warn with a fix gets a line" "$(fix_lines)" "fix    dotfiles_repo  git df status"
assert_not_contains "an ok step gets none" "$(fix_lines)" "claude"
assert_not_contains "fix lines are stdout only" "${ERR}" "fix    "

# --json is summary.json and nothing else.
bump_now_secs 60
nm healthcheck --only "${ONLY}" --json
RUN="$(newest_run_dir)"
assert_eq "--json is summary.json, byte for byte" "$(cat "${RUN}/summary.json")" "${OUT}"

# ── init --dry-run: the fix lines come before the status output init prints last ──
bump_now_secs 60
nm init --dry-run --only bob_neovim,claude
RUN="$(newest_run_dir)"
TABLE="$(old_table "${RUN}/summary.json")"
N="$(printf '%s\n' "${TABLE}" | wc -l | tr -d ' ')"
assert_eq "init: main's table, then the fix line" "${TABLE}"$'\n'"fix    bob_neovim  dotfiles apply bob_neovim" "$(head -n $((N + 1)) "${FIX}/nm.out")"
assert_contains "init still ends with status" "${OUT}" "tiers"
df_git checkout -q -- "${TRACKED}"
export BOB_SHIM_LS="Installed: v0.11.2 Used"

# ── A manual item without a fix: done by hand, its WARN block still on stderr ──
bump_now_secs 60
nm healthcheck --only brew,terminal_nerdfont
RUN="$(newest_run_dir)"
assert_eq "manual_font is the manual warn" manual_font "$(jq -r '.steps[] | select(.step=="terminal_nerdfont") | .reason' "${RUN}/summary.json")"
assert_eq "plain: main's table, then the manual line" "$(old_table "${RUN}/summary.json")"$'\n'"fix    terminal_nerdfont  by hand" "${OUT}"
assert_contains "plain keeps the manual WARN block on stderr" "${ERR}" "Manual step (terminal_nerdfont manual_font)"

# ── Fancy: the box, the manual detail inside it, the run directory last ──
FAKE_GUM="${FIX}/fakegum"
printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> "%s/gum.log"\n' "${FIX}" > "${FAKE_GUM}"
chmod +x "${FAKE_GUM}"
export ARI_DOTFILES_UI=fancy ARI_DOTFILES_GUM="${FAKE_GUM}"
export BOB_SHIM_LS="v0.11.2"
rm -f "${FIX}/gum.log"
bump_now_secs 60
nm healthcheck --only "brew,terminal_nerdfont,bob_neovim,claude"
RUN="$(newest_run_dir)"
BOX="$(grep '^style ' "${FIX}/gum.log" 2>/dev/null | strip_ansi)"
assert_eq "fancy: one box" 1 "$(grep -c '^style ' <<< "${BOX}")"
assert_contains "the box is rounded" "${BOX}" "--border rounded"
assert_contains "bordered in the roll-up colour (fail = red 196)" "${BOX}" "--border-foreground 196"
assert_contains "titled with the count" "${BOX}" "2 need attention"
assert_contains "an entry: glyph, step, reason" "${BOX}" "✗ bob_neovim  nvim_missing"
assert_contains "its fix" "${BOX}" "fix: dotfiles apply bob_neovim"
assert_contains "the manual item is in the box" "${BOX}" "! terminal_nerdfont  manual_font"
assert_contains "with its detail lines" "${BOX}" "no Terminal.app preferences yet"
RUN_SHOWN="run: \$XDG_STATE_HOME${RUN#"${XDG_STATE_HOME}"}"
assert_contains "the run directory, unclipped, as ui::paths shows it" "${BOX}" "${RUN_SHOWN}"
assert_eq "the run directory is the last line" "${RUN_SHOWN}" "${BOX: -${#RUN_SHOWN}}"
assert_not_contains "fancy: no manual WARN block on stderr" "${ERR}" "Manual step"
assert_not_contains "fancy: no plain fix lines" "${OUT}" "fix    "
assert_contains "fancy still ends with the status line" "$(printf '%s' "${OUT}" | strip_ansi)" "status: fail"

# ── Fancy, all ok: one green line, no box ──
export BOB_SHIM_LS="Installed: v0.11.2 Used"
rm -f "${FIX}/gum.log"
bump_now_secs 60
nm healthcheck --only "${ONLY}"
PLAIN_OUT="$(printf '%s' "${OUT}" | strip_ansi)"
assert_eq "fancy all-ok ends with one line" "✓ all 4 steps ok" "$(tail -n 1 <<< "${PLAIN_OUT}")"
assert_contains "painted green (71)" "$(tail -n 1 <<< "${OUT}")" $'\e[38;5;71m'
assert_eq "no box" "" "$(grep '^style ' "${FIX}/gum.log" 2>/dev/null)"
unset ARI_DOTFILES_UI ARI_DOTFILES_GUM
assert_no_file "lock released" "${ARI_DOTFILES_STATE_DIR}/lock.d"

report
