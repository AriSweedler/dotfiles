#!/usr/bin/env bash
# `apply --edit [STEP..] | FILE`: every step opens in $EDITOR as a plan, in run order, with its
# description, group, needs, newest result and age, and check-only; the named steps (or, with
# none named, the failing ones that have an apply) start as apply; needs are checked against each
# step's newest result; a terminal confirms; the chosen steps run as one setup.
set -u
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

world_new
world_use_fixture satisfied
seed_fake_repos
seed_ldf_remote
seed_home_baseline
rm -f "${XDG_DATA_HOME}/dotfiles/machine-name"   # machine_name fails, with an apply
PLAN="${ARI_DOTFILES_STATE_DIR}/apply-plan.dfapply"
SEEN="${FIX}/seen.dfapply"
LOCKSEEN="${FIX}/lockseen"

EDITORS="${FIX}/editors"
mkdir -p "${EDITORS}"
editor() {
  printf '#!/bin/sh\n[ -e "%s" ] && echo held >> "%s"\ncp "$1" "%s"\nawk %s "$1" > "$1.tmp" && mv "$1.tmp" "$1"\n' \
    "${ARI_DOTFILES_STATE_DIR}/lock.d" "${LOCKSEEN}" "${SEEN}" "'$2'" > "${EDITORS}/$1"
  chmod +x "${EDITORS}/$1"
}
editor noop '{ print }'
editor add_claude '{ sub(/^skip +claude /, "apply  claude ") } { print }'
editor skip_all '{ sub(/^apply/, "skip ") } { print }'
editor bad 'END { print "apply"; print "apply claude" } { print }'

ed() {
  local e="$1"; shift
  bump_now_secs 60
  rm -f "${SEEN}"
  hermetic_env
  RC=0
  env -i "${HERMETIC_ENV[@]}" "EDITOR=${EDITORS}/${e}" "${FIX}/tools/zsh" "${ORIG_CONFIG_DIR}/bin/dotfiles" "$@" \
    > "${FIX}/ed.out" 2> "${FIX}/ed.err" || RC=$?
  OUT="$(cat "${FIX}/ed.out")"
  ERR="$(cat "${FIX}/ed.err")"
}
tty() {
  local e="$1"; shift
  bump_now_secs 60
  rm -f "${SEEN}"
  hermetic_env
  RC=0
  env -i "${HERMETIC_ENV[@]}" ARI_DOTFILES_UI=plain "EDITOR=${EDITORS}/${e}" \
    /usr/bin/script -q /dev/null "${FIX}/tools/zsh" "${ORIG_CONFIG_DIR}/bin/dotfiles" "$@" \
    < /dev/null > "${FIX}/tty.out" 2>&1 || RC=$?
  OUT="$(tr -d '\r' < "${FIX}/tty.out")"
}
# pl ACTION: how lib/plan.zsh's plan::line starts a line: the action, padded, then two spaces.
pl() { printf '%-14s  ' "$1"; }
last_setup_steps() { jq -r '[.steps[].step] | join(",")' "${ARI_DOTFILES_STATE_DIR}/last-setup.json" 2>/dev/null; }
clear_last_setup() { rm -f "${ARI_DOTFILES_STATE_DIR}/last-setup.json"; }
plan_line() { grep -E "^(apply|skip) +$1 " "${SEEN}"; }

# ── usage ──
nm apply --edit --json
assert_eq "--edit --json: usage error" 64 "${RC}"
nm apply --edit nosuch
assert_eq "--edit with an unknown step: usage error" 64 "${RC}"
nm apply
assert_eq "no --edit, no step: usage error" 64 "${RC}"

# A full check, then one of claude alone: last-check.json now holds claude only.
nm check
bump_now_secs 60
nm check --only claude

# ── no step named: the failing ones with an apply start as apply; unchanged applies nothing ──
ed noop apply --edit
assert_eq "unchanged, none named: exit 0" 0 "${RC}"
assert_contains "unchanged, none named: says so" "${OUT}" "apply: no change; nothing applied"
assert_eq "unchanged, none named: nothing applied" "" "$(last_setup_steps)"
registry_load
assert_eq "the plan: line 1 names its kind and actions (the dotfilesplan filetype reads it)" "# dotfiles-plan: apply · actions: apply | skip" "$(head -n 1 "${SEEN}")"
assert_eq "the plan: every step, in run order" "$(registry_steps | tr '\n' ',')" "$(grep -E '^(apply|skip) ' "${SEEN}" | awk '{ printf "%s,", $2 }')"
assert_contains "the plan: a failing step with an apply starts as apply, with its newest result" "$(plan_line machine_name)" \
  "$(pl apply)machine_name          # this machine's everyday name is set: one word in ~/.local/share/dotfiles/machine-name ('dotfiles machine-name NAME' or an edit renames it) · repo · last fail name_missing (2m ago)"
assert_contains "the plan: the newest result is each step's own, not last-check.json's" "$(plan_line claude)" "last ok present (1m ago)"
assert_contains "the plan: a manual warn without an apply stays skip, check-only" "$(plan_line terminal_nerdfont)" "$(pl skip)terminal_nerdfont"
assert_contains "the plan: check-only" "$(plan_line terminal_nerdfont)" " · check-only"
assert_contains "the plan: needs" "$(plan_line claude_skills)" " · repo · needs dotfiles_repo · last skip no_registry"
assert_eq "the editor ran without the lock" "" "$(cat "${LOCKSEEN}" 2>/dev/null)"
assert_no_file "unchanged: no plan left" "${PLAN}"

# ── edited: the apply lines run as one setup, off a terminal without a confirm ──
ed add_claude apply --edit
assert_eq "edited: the chosen steps ran" "machine_name,claude" "$(last_setup_steps)"
assert_json "edited: a setup" "${ARI_DOTFILES_STATE_DIR}/last-setup.json" .mode setup
assert_no_file "edited: the plan is gone" "${PLAN}"

# ── named steps start as apply; unchanged, they run ──
clear_last_setup
ed noop apply --edit claude
assert_eq "named: exit 0" 0 "${RC}"
assert_contains "named: apply" "$(plan_line claude)" "$(pl apply)claude"
assert_contains "named: the failing ones are not prefilled" "$(plan_line machine_name)" "$(pl skip)machine_name"
assert_eq "named, unchanged: runs" claude "$(last_setup_steps)"

clear_last_setup
ed skip_all apply --edit claude
assert_contains "all skipped: says so" "${OUT}" "apply: every step skipped; nothing applied"
assert_eq "all skipped: nothing applied" "" "$(last_setup_steps)"

# ── on a terminal: one confirm; declined, nothing runs and the plan stays ──
tty noop apply --edit claude
assert_contains "terminal: the confirm" "${OUT}" "Apply claude? [y/N]"
assert_contains "terminal, declined: says so" "${OUT}" "apply: not confirmed; nothing applied"
assert_contains "terminal, declined: the resume" "${OUT}" "next: dotfiles apply --edit ${PLAN}"
assert_file "terminal, declined: the plan kept" "${PLAN}"
assert_eq "terminal, declined: nothing applied" "" "$(last_setup_steps)"

# ── bad lines; a need whose newest result failed ──
mv "${ARI_DOTFILES_DF_GIT_DIR}" "${FIX}/df.away"
nm check --only dotfiles_repo
ed bad apply --edit claude_skills
assert_eq "bad plan: exit 1" 1 "${RC}"
n="$(grep -c '' "${SEEN}")"
assert_contains "bad plan: an action alone" "${ERR}" "line $(( n + 1 )): expected one step after 'apply'"
assert_contains "bad plan: a step twice" "${ERR}" "line $(( n + 2 )): listed twice | item='claude'"
line="$(grep -nE '^apply +claude_skills ' "${SEEN}" | cut -d: -f1)"
assert_contains "bad plan: an applied step whose need failed" "${ERR}" "line ${line}: claude_skills needs dotfiles_repo, which ended fail missing_bare_repo and is not applied here; apply dotfiles_repo too, or skip claude_skills"
assert_contains "bad plan: the resume" "${ERR}" "fix='dotfiles apply --edit ${PLAN}'"
assert_file "bad plan: kept" "${PLAN}"
mv "${FIX}/df.away" "${ARI_DOTFILES_DF_GIT_DIR}"

printf 'skip   claude_skills\napply  claude  # resumed\n' > "${PLAN}"
ed noop apply --edit "${PLAN}"
assert_eq "resumed: exit 0" 0 "${RC}"
assert_eq "resumed: the plan's apply steps" claude "$(last_setup_steps)"
assert_no_file "resumed: the plan is gone" "${PLAN}"

report
