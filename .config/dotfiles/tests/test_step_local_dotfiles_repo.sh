#!/usr/bin/env bash
# local_dotfiles_repo: init + allowlist + hooksPath, the manual remote step, allowlist drift,
# unpushed commits.
set -u
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

world_new
world_use_fixture satisfied
TEMPLATE="${ARI_DOTFILES_SHARED_DIR}/local-dotfiles-exclude"
EXCLUDE="${ARI_DOTFILES_LDF_GIT_DIR}/info/exclude"
rules() { grep -vE '^[[:space:]]*(#|$)' "$1" || true; }

check_ldf() { bump_now_secs 60; nm check --only local_dotfiles_repo --json; out_json > /dev/null; }
step_json() { jq -c '.steps[] | select(.step=="local_dotfiles_repo")' "${FIX}/out.json"; }

check_ldf
assert_eq "no repo → fail" fail "$(step_get local_dotfiles_repo .status)"
assert_eq "reason missing_bare_repo" missing_bare_repo "$(step_get local_dotfiles_repo .reason)"

bump_now_secs 60
nm apply local_dotfiles_repo
assert_eq "apply exits 0" 0 "${RC}"
assert_file "bare repo created" "${ARI_DOTFILES_LDF_GIT_DIR}/HEAD"
assert_eq "info/exclude rules == template rules" "$(rules "${TEMPLATE}")" "$(rules "${EXCLUDE}")"
assert_eq "hooksPath set" "${ARI_DOTFILES_LDF_HOOKS}" "$(git --git-dir="${ARI_DOTFILES_LDF_GIT_DIR}" config --local --get core.hooksPath)"

check_ldf
assert_eq "no remote → warn" warn "$(step_get local_dotfiles_repo .status)"
assert_eq "reason no_remote" no_remote "$(step_get local_dotfiles_repo .reason)"
assert_eq "no_remote is manual" true "$(step_get local_dotfiles_repo .manual)"
assert_contains "manual step: remote add" "$(step_json)" "git ldf remote add origin"
assert_contains "manual step: first push" "$(step_json)" "git ldf push --set-upstream origin main"

printf '!/share/extra/\n' >> "${EXCLUDE}"
check_ldf
assert_eq "edited exclude → warn" warn "$(step_get local_dotfiles_repo .status)"
assert_eq "reason allowlist_differs" allowlist_differs "$(step_get local_dotfiles_repo .reason)"
assert_contains "fix is a diff" "$(step_get local_dotfiles_repo .fix)" "diff "
assert_eq "allowlist_differs is manual" true "$(step_get local_dotfiles_repo .manual)"

# What fires on this machine until its info/exclude learns the new-machine rule.
grep -vF '!/share/new-machine/' "${TEMPLATE}" > "${EXCLUDE}"
check_ldf
assert_eq "live copy lacking !/share/new-machine/ → warn" warn "$(step_get local_dotfiles_repo .status)"
assert_eq "reason allowlist_differs (migration)" allowlist_differs "$(step_get local_dotfiles_repo .reason)"
cp "${TEMPLATE}" "${EXCLUDE}"

seed_ldf_remote
mkdir -p "${HOME}/.local/share/new-machine"
printf '# local tier\n' > "${HOME}/.local/share/new-machine/Brewfile"
ldf_git add -- "${HOME}/.local/share/new-machine/Brewfile"
ldf_git commit -q -m "first local commit"
ldf_git push -q origin main
check_ldf
assert_eq "remote set, nothing unpushed → ok" ok "$(step_get local_dotfiles_repo .status)"

printf 'brew "x"\n' >> "${HOME}/.local/share/new-machine/Brewfile"
ldf_git add -- "${HOME}/.local/share/new-machine/Brewfile"
ldf_git commit -q -m "second local commit"
check_ldf
assert_eq "one unpushed commit → warn" warn "$(step_get local_dotfiles_repo .status)"
assert_eq "reason unpushed" unpushed "$(step_get local_dotfiles_repo .reason)"
assert_contains "detail counts 1" "$(step_get local_dotfiles_repo .detail)" "1"

if (( FAIL > 0 )); then jq -c '.steps[] | {step, status, reason, detail, fix}' "${FIX}/out.json" >&2; fi
report
