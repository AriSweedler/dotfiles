#!/usr/bin/env bash
# `jobs edit`: a plugin or dep edited as a draft in $EDITOR, checked (syntax, header lines, the
# documentation rule), then put in place and committed in its tier; a draft that fails is kept for
# the next edit and the live file never changes. Then the doc rule as the dotfiles_jobs step sees it.
set -u
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

world_new
JOBS_DF="${HOME}/.config/dotfiles/jobs"
JOBS_LDF="${XDG_DATA_HOME}/dotfiles/jobs"
DEPS_LDF="${XDG_DATA_HOME}/dotfiles/deps"
DRAFTS="${XDG_STATE_HOME}/dotfiles/jobs/drafts"
mkdir -p "${JOBS_DF}" "${JOBS_LDF}" "${DEPS_LDF}"
printf '#!/usr/bin/env zsh\n# cron: 0 * * * *\n# Hourly: says it ticked.\nprint -r -- tick\n' > "${JOBS_DF}/ticker"
chmod +x "${JOBS_DF}/ticker"
seed_fake_repos
seed_ldf_remote

EDITORS="${FIX}/editors"
mkdir -p "${EDITORS}"
# editor NAME AWK: rewrites the file it is given with AWK.
editor() { printf '#!/bin/sh\nawk %s "$1" > "$1.tmp" && mv "$1.tmp" "$1"\n' "'$2'" > "${EDITORS}/$1"; chmod +x "${EDITORS}/$1"; }
editor noop '{ print }'
editor describe '/^# TODO/ { print "# Says hello, to prove the jobs framework runs."; next } { print }'
editor describe_dep '/^# TODO/ { print "# Provides GREETING for the plugins that name it."; next } { print }'
editor bad_cron '/^# cron:/ { print "# cron: 61 * * * *"; next } { print }'
editor good_cron '/^# cron:/ { print "# cron: 30 * * * *"; next } { print }'
editor undocument '/^# Hourly/ { next } { print }'
editor bad_header '/^# cron:/ { print; print "# triggers: lunch"; print "# timeout: soon"; print "# deps: nothere"; next } { print }'
editor bad_syntax 'END { print "print -r -- \x27unterminated" } { print }'
editor comment 'END { print "# a later note" } { print }'

# edit EDITOR ARGS...: `dotfiles jobs edit ARGS` with that editor, no terminal.
edit() {
  local ed="$1"; shift
  bump_now_secs 60
  hermetic_env
  HERMETIC_ENV+=("EDITOR=${EDITORS}/${ed}")
  RC=0
  env -i "${HERMETIC_ENV[@]}" "${FIX}/tools/zsh" "${ORIG_CONFIG_DIR}/bin/dotfiles" jobs "$@" \
    < /dev/null > "${FIX}/nm.out" 2> "${FIX}/nm.err" || RC=$?
  OUT="$(cat "${FIX}/nm.out")"
  ERR="$(cat "${FIX}/nm.err")"
}
ldf_count() { ldf_git rev-list --count HEAD 2>/dev/null || echo 0; }
df_count() { df_git rev-list --count HEAD; }

# ── usage ──
edit noop edit
assert_eq "no NAME is a usage error" 64 "${RC}"
edit noop edit nobody
assert_eq "an unknown plugin: exit 1" 1 "${RC}"
assert_contains "an unknown plugin names --new" "${ERR}" "fix='dotfiles jobs edit nobody --new'"
edit noop edit ticker --local
assert_eq "--local without --new is a usage error" 64 "${RC}"
edit noop edit ../ticker
assert_eq "a path is not a name" 64 "${RC}"

# ── --new: the template alone is no change and creates nothing ──
edit noop edit hello --new
assert_eq "unchanged template: exit 0" 0 "${RC}"
assert_contains "unchanged template: says so" "${OUT}" "jobs: no change; nothing created"
assert_no_file "unchanged template: no plugin" "${JOBS_LDF}/hello"

# ── --new, described: in place, executable, committed and pushed in the local tier ──
ldf_before="$(ldf_count)"
edit describe edit hello --new
assert_eq "new plugin: exit 0" 0 "${RC}"
assert_eq "new plugin: executable" 1 "$([[ -x "${JOBS_LDF}/hello" ]] && echo 1 || echo 0)"
assert_contains "new plugin: the template's trigger line" "$(cat "${JOBS_LDF}/hello")" "# triggers: unlock load"
assert_eq "new plugin: one ldf commit" "$(( ldf_before + 1 ))" "$(ldf_count)"
assert_eq "new plugin: the subject" "dotfiles: add job hello (local)" "$(ldf_git log -1 --format=%s)"
assert_eq "new plugin: pushed" "$(ldf_git rev-parse HEAD)" "$(git --git-dir="${FIX}/remotes/local-dotfiles.git" rev-parse main)"
assert_contains "new plugin: the next step" "${OUT}" "next: dotfiles jobs run hello"
assert_no_file "new plugin: no draft left" "${DRAFTS}/plugin-hello"
edit noop edit hello --new
assert_eq "--new on an existing plugin: exit 1" 1 "${RC}"

# ── a draft that fails: reported, kept, the live file untouched, nothing committed ──
df_before="$(df_count)"
live_before="$(cat "${JOBS_DF}/ticker")"
edit bad_cron edit ticker
assert_eq "bad cron: exit 1" 1 "${RC}"
assert_contains "bad cron: named" "${ERR}" "'# cron: 61 * * * *' is not five valid fields"
assert_contains "bad cron: the resume" "${ERR}" "fix='dotfiles jobs edit ticker'"
assert_eq "bad cron: the live file is untouched" "${live_before}" "$(cat "${JOBS_DF}/ticker")"
assert_file "bad cron: the draft is kept" "${DRAFTS}/plugin-ticker"
assert_eq "bad cron: nothing committed" "${df_before}" "$(df_count)"

# Resumed from the draft and fixed: in place, committed in the shared tier, never pushed.
edit good_cron edit ticker
assert_eq "fixed: exit 0" 0 "${RC}"
assert_contains "fixed: resumed the draft" "${ERR}" "resuming the draft a failed edit left"
assert_contains "fixed: the new cron line is live" "$(cat "${JOBS_DF}/ticker")" "# cron: 30 * * * *"
assert_eq "fixed: one df commit" "$(( df_before + 1 ))" "$(df_count)"
assert_eq "fixed: the subject" "dotfiles: edit job ticker (shared)" "$(df_git log -1 --format=%s)"
assert_contains "fixed: the shared tier waits for dotfiles push" "${OUT}" 'Run `dotfiles push` when ready.'
rm -f "${DRAFTS}/plugin-ticker"

# ── each header problem, and the doc rule ──
edit bad_header edit ticker
assert_eq "bad header: exit 1" 1 "${RC}"
assert_contains "bad header: a trigger word" "${ERR}" "'# triggers:' takes unlock and load, not 'lunch'"
assert_contains "bad header: the timeout" "${ERR}" "'# timeout:' takes seconds, not 'soon'"
assert_contains "bad header: an unknown dep" "${ERR}" "'# deps:' names 'nothere', which is no dep"
rm -f "${DRAFTS}/plugin-ticker"
edit undocument edit ticker
assert_eq "undocumented: exit 1" 1 "${RC}"
assert_contains "undocumented: the doc rule" "${ERR}" "undocumented: no line saying what it does"
rm -f "${DRAFTS}/plugin-ticker"
edit bad_syntax edit ticker
assert_eq "syntax error: exit 1" 1 "${RC}"
assert_contains "syntax error: zsh -n's complaint" "${ERR}" "syntax: "
rm -f "${DRAFTS}/plugin-ticker"

# ── unchanged; --no-commit; a plugin turned off stays off; the --edit spelling ──
edit noop edit ticker
assert_eq "unchanged: exit 0" 0 "${RC}"
assert_contains "unchanged: says so" "${OUT}" "jobs: no change | plugin=ticker"
chmod -x "${JOBS_DF}/ticker"
df_before="$(df_count)"
edit comment --edit ticker --no-commit
assert_eq "--edit, --no-commit: exit 0" 0 "${RC}"
assert_contains "--no-commit: says so" "${OUT}" "not committed | file="
assert_eq "--no-commit: nothing committed" "${df_before}" "$(df_count)"
assert_eq "a plugin turned off stays off" 0 "$([[ -x "${JOBS_DF}/ticker" ]] && echo 1 || echo 0)"
chmod +x "${JOBS_DF}/ticker"

# ── --dep --new ──
edit describe_dep edit greet --dep --new
assert_eq "new dep: exit 0" 0 "${RC}"
assert_eq "new dep: in the local deps, executable" 1 "$([[ -x "${DEPS_LDF}/greet" ]] && echo 1 || echo 0)"
assert_eq "new dep: the subject" "dotfiles: add job dep greet (local)" "$(ldf_git log -1 --format=%s)"

# ── both tiers: refused ──
cp "${JOBS_DF}/ticker" "${JOBS_LDF}/ticker"
edit noop edit ticker
assert_eq "both tiers: exit 1" 1 "${RC}"
assert_contains "both tiers: says so" "${ERR}" "plugin in both tiers; remove one first"
rm -f "${JOBS_LDF}/ticker"

# ── the doc rule in the dotfiles_jobs step: a manual fail naming the edit ──
JOBS_LABEL="com.$(id -un).dotfiles-jobs"
jq -n --arg label "${JOBS_LABEL}" '{Label: $label, ProgramArguments: ["/bin/zsh", "dotfiles", "jobs", "tick"], StartInterval: 300}' \
  | plutil -convert xml1 - -o "${HOME}/Library/LaunchAgents/${JOBS_LABEL}.plist"
touch "${LAUNCHCTL_SHIM_STATE}/${JOBS_LABEL}"
status_of() { step_get "$1" .status; }
reason_of() { step_get "$1" .reason; }
check_jobs() { bump_now_secs 60; nm check --only dotfiles_jobs --json; out_json > /dev/null; }
check_jobs
assert_eq "documented: ok" ok "$(status_of dotfiles_jobs)"
printf '#!/usr/bin/env zsh\nprint -r -- quiet\n' > "${JOBS_LDF}/quiet"
chmod +x "${JOBS_LDF}/quiet"
check_jobs
assert_eq "undocumented plugin: fail" fail "$(status_of dotfiles_jobs)"
assert_eq "undocumented plugin: reason" undocumented "$(reason_of dotfiles_jobs)"
assert_json "undocumented plugin: manual, never applied" "${FIX}/out.json" '.steps[] | select(.step=="dotfiles_jobs") | .manual' true
assert_json "undocumented plugin: the fix" "${FIX}/out.json" '.steps[] | select(.step=="dotfiles_jobs") | .fix' "dotfiles jobs edit quiet"
assert_contains "undocumented plugin: what it lacks" "$(jq -r '.steps[] | select(.step=="dotfiles_jobs") | .detail' "${FIX}/out.json")" \
  "plugin quiet: no line saying what it does, no '# triggers:' or '# cron:' line"
rm -f "${JOBS_LDF}/quiet"
printf '#!/usr/bin/env zsh\nprint -r -- X=1\n' > "${DEPS_LDF}/bare"
chmod +x "${DEPS_LDF}/bare"
check_jobs
assert_json "undocumented dep: the fix names --dep" "${FIX}/out.json" '.steps[] | select(.step=="dotfiles_jobs") | .fix' "dotfiles jobs edit bare --dep"

report
