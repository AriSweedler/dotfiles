#!/usr/bin/env bash
# bootstrap.sh from an empty HOME with no Command Line Tools: waits out the CLT dialog, clones
# over https with an ssh pushurl and main tracking, checks HOME out, and hands off to
# `new-machine setup`. A second run installs and applies nothing; a conflicting file stops it
# before new-machine runs; both one-liner forms (argv string, stdin pipe) behave the same.
set -u
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

BOOTSTRAP="${REPO_DIR}/bin/bootstrap.sh"
clt_calls() { shim_log xcode-select | tr '\n' ' '; }

# ── lint and budget ──────────────────────────────────────────────────────────
if /bin/sh -n "${BOOTSTRAP}"; then pass "sh -n"; else fail "sh -n" "syntax error"; fi
if [[ -x /bin/dash ]]; then
  if /bin/dash -n "${BOOTSTRAP}"; then pass "dash -n"; else fail "dash -n" "syntax error"; fi
fi
SHELLCHECK="$(PATH="${ORIG_PATH}" bash -c 'type -P shellcheck' 2>/dev/null || true)"
if [[ -n "${SHELLCHECK}" ]]; then
  if out="$("${SHELLCHECK}" -s sh "${BOOTSTRAP}" 2>&1)"; then pass "shellcheck -s sh"; else fail "shellcheck -s sh" "${out}"; fi
fi
lines="$(wc -l < "${BOOTSTRAP}" | tr -d ' ')"
if (( lines <= 30 )); then pass "budget: ${lines} lines <= 30"; else fail "budget" "${lines} lines > 30"; fi

world_new
world_use_fixture satisfied
world_empty_home
seed_df_remote
export ARI_DOTFILES_REMOTE="${FIX}/remotes/dotfiles.git"
export BREW_SHIM_ALLOW_MUTATION=1
export BOB_SHIM_LS="Installed: v0.11.2 Used"

# ── fresh Mac: no CLT, empty HOME ────────────────────────────────────────────
bs --json
assert_eq "bootstrap exits 0" 0 "${RC}"
f="$(out_json)"
assert_eq "CLT: probe, install, probe" "-p --install -p " "$(clt_calls)"
assert_contains "asks for the dialog click" "${ERR}" "click Install"
assert_file "bare repo cloned" "${ARI_DOTFILES_DF_GIT_DIR}/HEAD"
assert_eq "fetch url is ARI_DOTFILES_REMOTE" "${ARI_DOTFILES_REMOTE}" "$(df_git remote get-url origin)"
assert_eq "push url is ssh" "git@github.com:AriSweedler/dotfiles.git" "$(df_git remote get-url --push origin)"
assert_eq "main tracks origin" "origin" "$(df_git config --local --get branch.main.remote)"
assert_eq "main merges refs/heads/main" "refs/heads/main" "$(df_git config --local --get branch.main.merge)"
assert_file "HOME checked out" "${HOME}/.zshenv"
assert_file "worktree has the log lib" "${HOME}/.config/zsh/plugins/log.zsh"
assert_file "worktree has the bootstrap itself" "${HOME}/.config/new-machine/bin/bootstrap.sh"
assert_eq "df hooksPath set by new-machine" "${ARI_DOTFILES_DF_HOOKS}" "$(df_git config --local --get core.hooksPath)"
assert_json "setup status ok or warn" "${f}" '.status == "ok" or .status == "warn"' true
assert_json "no step failed or errored" "${f}" '[.steps[] | select(.status=="fail" or .status=="error") | .step + "=" + .reason] | join(",")' ""
assert_json "dotfiles_repo converged" "${f}" '.steps[] | select(.step=="dotfiles_repo") | .status' ok
assert_json "dotfiles_jobs converged" "${f}" '.steps[] | select(.step=="dotfiles_jobs") | .status' ok
assert_eq "curl never called" "" "$(shim_log curl)"
if (( FAIL > 0 )); then jq -c '.steps[] | {step, status, reason, detail, applied}' "${f}" >&2; printf '%s\n' "${ERR}" | tail -n 20 >&2; fi

# ── second run on the converged machine ──────────────────────────────────────
head_before="$(df_git rev-parse HEAD)"
shim_logs_reset
bump_now_secs 60
bs --json
assert_eq "second run exits 0" 0 "${RC}"
f="$(out_json)"
assert_eq "CLT: probe only" "-p " "$(clt_calls)"
assert_eq "HEAD unchanged" "${head_before}" "$(df_git rev-parse HEAD)"
assert_no_mutation "second run mutates nothing"
assert_json "no step applied" "${f}" '[.steps[] | select(.applied == true or .applied == "would_apply")] | length' 0

# ── a file the checkout would overwrite ──────────────────────────────────────
world_empty_home
printf 'mine, not yours\n' > "${HOME}/.zshenv"
bs
assert_eq "conflict exits 1" 1 "${RC}"
assert_eq "conflicting file intact" "mine, not yours" "$(cat "${HOME}/.zshenv")"
assert_contains "conflict names the file" "${ERR}" ".zshenv"
assert_file "clone kept for the re-run" "${ARI_DOTFILES_DF_GIT_DIR}/HEAD"
assert_no_file "new-machine never ran" "${ARI_DOTFILES_STATE_DIR}"
rm -f "${HOME}/.zshenv"
bump_now_secs 60
bs --json
assert_eq "re-run after removing the conflict exits 0" 0 "${RC}"

# ── the two one-liner forms ──────────────────────────────────────────────────
world_empty_home
bump_now_secs 60
bs_pipe
assert_eq "curl | sh form exits 0" 0 "${RC}"
assert_file "curl | sh form checked HOME out" "${HOME}/.zshenv"

world_empty_home
bump_now_secs 60
bs_argv --dry-run
if (( RC == 0 || RC == 1 )); then pass "sh -c form passes flags through (rc=${RC})"; else fail "sh -c form passes flags through" "rc=${RC}"; fi
assert_contains "flag reached new-machine" "${ERR}" "dry-run: no changes will be made"
assert_file "clone and checkout are not dry-run aware" "${HOME}/.zshenv"

report
