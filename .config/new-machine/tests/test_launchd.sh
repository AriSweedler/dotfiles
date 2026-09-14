#!/usr/bin/env bash
# The weekly launchd job: rendered plist contents, install/uninstall through launchctl,
# idempotent bytes, dry-run, and the weekly_verify check around it.
set -u
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

world_new
world_use_fixture satisfied
LABEL="com.$(id -un).new-machine-verify"
PLIST="${HOME}/Library/LaunchAgents/${LABEL}.plist"
UID_NUM="$(id -u)"

zfn launchd.zsh launchd::render_plist
assert_eq "render_plist exits 0" 0 "${RC}"
printf '%s\n' "${OUT}" > "${FIX}/rendered.plist"
if plutil -lint -s "${FIX}/rendered.plist"; then pass "rendered plist lints"; else fail "rendered plist lints" "plutil rejected it"; fi
plutil -convert json -o "${FIX}/rendered.json" "${FIX}/rendered.plist"
J="${FIX}/rendered.json"
assert_json "Label" "${J}" '.Label' "${LABEL}"
assert_json "ProgramArguments" "${J}" '.ProgramArguments | join(" ")' "/bin/zsh ${HOME}/.config/new-machine/bin/new-machine verify"
assert_json "StartCalendarInterval Monday 10:05" "${J}" '.StartCalendarInterval | "\(.Weekday) \(.Hour) \(.Minute)"' "1 10 5"
assert_json "PATH starts with ~/.local/bin then Homebrew" "${J}" '.EnvironmentVariables.PATH | startswith("'"${HOME}"'/.local/bin:/opt/homebrew/bin:/opt/homebrew/sbin")' true
assert_json "PATH is absolute, no tilde" "${J}" '.EnvironmentVariables.PATH | contains("~")' false
assert_json "HOMEBREW_NO_AUTO_UPDATE" "${J}" '.EnvironmentVariables.HOMEBREW_NO_AUTO_UPDATE' 1
assert_json "HOMEBREW_NO_ANALYTICS" "${J}" '.EnvironmentVariables.HOMEBREW_NO_ANALYTICS' 1
assert_json "HOMEBREW_NO_INSTALL_CLEANUP" "${J}" '.EnvironmentVariables.HOMEBREW_NO_INSTALL_CLEANUP' 1
assert_json "GIT_TERMINAL_PROMPT" "${J}" '.EnvironmentVariables.GIT_TERMINAL_PROMPT' 0
assert_json "NEW_MACHINE_INVOKED_BY" "${J}" '.EnvironmentVariables.NEW_MACHINE_INVOKED_BY' launchd
assert_json "ProcessType Background" "${J}" '.ProcessType' Background
assert_json "LowPriorityIO" "${J}" '.LowPriorityIO' true
assert_json "RunAtLoad false" "${J}" '.RunAtLoad' false
assert_json "no HOME in the environment block" "${J}" '.EnvironmentVariables | has("HOME")' false
assert_json "StandardOutPath under the fake state dir" "${J}" '.StandardOutPath | startswith("'"${NEW_MACHINE_STATE_DIR}"'/")' true
assert_json "StandardErrorPath under the fake state dir" "${J}" '.StandardErrorPath | startswith("'"${NEW_MACHINE_STATE_DIR}"'/")' true

bump_now_secs 60
nm check --only weekly_verify --json
out_json > /dev/null
assert_eq "before install: fail" fail "$(step_get weekly_verify .status)"
assert_eq "reason not_installed" not_installed "$(step_get weekly_verify .reason)"

bump_now_secs 60
nm verify --install --dry-run
assert_eq "install --dry-run exits 0" 0 "${RC}"
assert_no_file "dry-run writes no plist" "${PLIST}"
assert_eq "dry-run touches launchctl not at all" "" "$(shim_log launchctl)"

bump_now_secs 60
nm verify --install
assert_eq "install exits 0" 0 "${RC}"
assert_file "plist written" "${PLIST}"
lc_log="$(shim_log launchctl)"
assert_contains "launchctl bootout first" "${lc_log}" "bootout gui/${UID_NUM}/${LABEL}"
assert_contains "launchctl bootstrap with the plist" "${lc_log}" "bootstrap gui/${UID_NUM} ${PLIST}"
bootout_line="$(grep -n '^bootout' "${BREW_SHIM_LOG_DIR}/launchctl.log" | head -n 1 | cut -d: -f1)"
bootstrap_line="$(grep -n '^bootstrap' "${BREW_SHIM_LOG_DIR}/launchctl.log" | head -n 1 | cut -d: -f1)"
if [[ -n "${bootout_line}" && -n "${bootstrap_line}" ]] && (( bootout_line < bootstrap_line )); then pass "bootout precedes bootstrap"
else fail "bootout precedes bootstrap" "${lc_log}"; fi
assert_file "job is loaded" "${LAUNCHCTL_SHIM_STATE}/${LABEL}"
if cmp -s "${FIX}/rendered.plist" "${PLIST}"; then pass "installed plist equals the rendered one"; else fail "installed plist equals the rendered one" "$(diff "${FIX}/rendered.plist" "${PLIST}")"; fi

cp "${PLIST}" "${FIX}/first.plist"
bump_now_secs 60
nm verify --install
assert_eq "second install exits 0" 0 "${RC}"
if cmp -s "${FIX}/first.plist" "${PLIST}"; then pass "second install writes identical bytes"; else fail "second install writes identical bytes" "$(diff "${FIX}/first.plist" "${PLIST}")"; fi

bump_now_secs 60
nm check --only weekly_verify --json
out_json > /dev/null
assert_eq "after install: ok" ok "$(step_get weekly_verify .status)"

plutil -replace StartCalendarInterval.Minute -integer 6 "${PLIST}"
bump_now_secs 60
nm check --only weekly_verify --json
out_json > /dev/null
assert_eq "edited plist → fail" fail "$(step_get weekly_verify .status)"
assert_eq "reason plist_drift" plist_drift "$(step_get weekly_verify .reason)"

rm -f "${LAUNCHCTL_SHIM_STATE}/${LABEL}"
cp "${FIX}/first.plist" "${PLIST}"
bump_now_secs 60
nm check --only weekly_verify --json
out_json > /dev/null
assert_eq "unloaded → fail" fail "$(step_get weekly_verify .status)"
assert_eq "reason not_loaded" not_loaded "$(step_get weekly_verify .reason)"

touch "${LAUNCHCTL_SHIM_STATE}/${LABEL}"
shim_logs_reset
bump_now_secs 60
nm verify --uninstall
assert_eq "uninstall exits 0" 0 "${RC}"
assert_contains "uninstall boots out" "$(shim_log launchctl)" "bootout gui/${UID_NUM}/${LABEL}"
assert_no_file "uninstall removes the plist" "${PLIST}"
assert_no_file "job unloaded" "${LAUNCHCTL_SHIM_STATE}/${LABEL}"

bump_now_secs 60
nm verify --status
assert_eq "--status exits 0" 0 "${RC}"
assert_contains "--status names the label" "${OUT}" "${LABEL}"

if (( FAIL > 0 )); then jq -c '.steps[] | {step, status, reason, detail}' "${FIX}/out.json" >&2; fi
report
