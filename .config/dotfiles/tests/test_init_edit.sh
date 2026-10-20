#!/usr/bin/env bash
# `init --edit`: the checks run first (side by side) and print; the steps with something to
# apply open in $EDITOR as a plan, `apply STEP  # reason: what the apply does`, the manual ones as
# comments and the rest for reference; the editor runs without the lock; bad lines are numbered and
# the plan kept for `--edit FILE`; then exactly the chosen steps run as init runs them, in a run
# directory of their own, and status.
set -u
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

world_new
world_use_fixture satisfied
seed_fake_repos
seed_ldf_remote
seed_home_baseline
# No neovim in use: bob_neovim fails with an apply. terminal_nerdfont warns, manual.
unset BOB_SHIM_LS
PLAN="${ARI_DOTFILES_STATE_DIR}/init-plan.dfinit"
SEEN="${FIX}/seen.dfinit"
LOCKSEEN="${FIX}/lockseen"

EDITORS="${FIX}/editors"
mkdir -p "${EDITORS}"
# editor NAME AWK: notes whether the lock is held or a spinner of the run's still spins (its
# sentinel, named for the run's pid, is there), keeps a copy of the plan in $SEEN, then rewrites
# it with AWK.
editor() {
  printf '#!/bin/sh\n[ -e "%s" ] && echo held >> "%s"\nls /tmp/dotfiles-spin.$PPID.* >/dev/null 2>&1 && echo spinning >> "%s"\ncp "$1" "%s"\nawk %s "$1" > "$1.tmp" && mv "$1.tmp" "$1"\n' \
    "${ARI_DOTFILES_STATE_DIR}/lock.d" "${LOCKSEEN}" "${LOCKSEEN}" "${SEEN}" "'$2'" > "${EDITORS}/$1"
  chmod +x "${EDITORS}/$1"
}
editor noop '{ print }'
editor skip_all '{ sub(/^apply/, "skip ") } { print }'
editor skip_brew '{ sub(/^apply  brew /, "skip   brew ") } { print }'
editor bad 'END { print "frobnicate bob_neovim"; print "apply nosuch"; print "apply bob_neovim extra"; print "skip bob_neovim"; print "apply brew" } { print }'

# ed ED ARGS...: `dotfiles ARGS` with EDITOR=ED, no terminal; OUT, ERR, RC.
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
# tty ED ARGS...: the same on a pseudo-terminal (script(1)), plain output, stdin at EOF (so a
# confirm answers no); OUT holds both streams.
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
last_setup_steps() { jq -r '[.steps[].step] | join(",")' "${ARI_DOTFILES_STATE_DIR}/last-setup.json" 2>/dev/null; }
clear_last_setup() { rm -f "${ARI_DOTFILES_STATE_DIR}/last-setup.json"; }
run_count() { local n=0 d; for d in "${ARI_DOTFILES_STATE_DIR}"/runs/*/; do [[ -d "${d}" ]] && n=$((n + 1)); done; printf '%s' "${n}"; }

# ── usage ──
nm init --edit --json
assert_eq "--edit --json: usage error" 64 "${RC}"
nm init --edit a.dfinit b.dfinit
assert_eq "--edit with two files: usage error" 64 "${RC}"
nm init --edit "${FIX}/x.dfinit" --only brew
assert_eq "--edit FILE --only: usage error" 64 "${RC}"
nm init extra
assert_eq "no --edit: a positional is still a usage error" 64 "${RC}"

# ── an unchanged plan runs as written ──
ed noop init --edit
assert_eq "unchanged: exit 1 (bob's apply does not converge under the shim)" 1 "${RC}"
plan="$(cat "${SEEN}")"
assert_contains "the plan: the actionable step, apply, with its reason and what the apply does" "${plan}" \
  "apply  bob_neovim            # nvim_missing: installs the latest neovim with bob and makes it the one in use"
assert_contains "the plan: names the actions" "${plan}" "#   skip    leave it as it is"
assert_contains "the plan: a manual step is a comment with its fix" "${plan}" "#   warn   terminal_nerdfont     manual_font:"
assert_contains "the plan: the ok steps for reference" "${plan}" "#   ok     brew                  present"
assert_not_contains "the plan: a manual step is never a line" "${plan}" $'\napply  terminal_nerdfont'
assert_eq "the editor ran without the lock" "" "$(cat "${LOCKSEEN}" 2>/dev/null)"
assert_contains "the checks printed first" "${OUT}" "fail   bob_neovim             nvim_missing"
assert_contains "then the setup run" "${OUT}" "fail   bob_neovim             apply_did_not_converge"
assert_contains "then status" "${OUT}" "tiers"
assert_eq "the setup ran exactly the chosen step" bob_neovim "$(last_setup_steps)"
assert_json "the setup applied it" "${ARI_DOTFILES_STATE_DIR}/last-setup.json" '.steps[0].applied' true
assert_contains "bob's apply ran" "$(shim_log bob)" "install latest"
assert_steps_are_registry "the checks were every step" "${ARI_DOTFILES_STATE_DIR}/last-check.json"
check_id="$(jq -r .run_id "${ARI_DOTFILES_STATE_DIR}/last-check.json")"
setup_id="$(jq -r .run_id "${ARI_DOTFILES_STATE_DIR}/last-setup.json")"
if [[ "${check_id}" != "${setup_id}" ]]; then pass "the setup has a run id of its own (${check_id} then ${setup_id})"
else fail "the setup has a run id of its own" "both ${check_id}"; fi
assert_json "the checks' run directory survives the setup" "${ARI_DOTFILES_STATE_DIR}/runs/${check_id}/summary.json" .mode check
assert_no_file "a plan that ran is not kept" "${PLAN}"
assert_no_file "lock released" "${ARI_DOTFILES_STATE_DIR}/lock.d"

# ── fancy: the spinner is gone before the editor opens; each run has its header ──
FAKE_GUM="${FIX}/fakegum"
printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> "%s/gum.log"\n' "${FIX}" > "${FAKE_GUM}"
chmod +x "${FAKE_GUM}"
ARI_DOTFILES_UI=fancy ARI_DOTFILES_GUM="${FAKE_GUM}" ed noop init --edit
assert_eq "fancy: the editor ran with no spinner and no lock" "" "$(cat "${LOCKSEEN}" 2>/dev/null)"
assert_contains "fancy: the checks' header" "${OUT}" "init · $(registry_step_count) steps"
assert_contains "fancy: the setup's header" "${OUT}" "init · 1 step"
assert_contains "fancy: a spinner did spin" "$(cat "${FIX}/gum.log")" "spin "

# ── every step skipped: nothing applied ──
clear_last_setup
ed skip_all init --edit
assert_eq "all skipped: the checks' exit code" 1 "${RC}"
assert_contains "all skipped: says so" "${OUT}" "init: every step skipped; nothing applied"
assert_contains "all skipped: the apply for later" "${OUT}" "next: dotfiles apply bob_neovim"
assert_eq "all skipped: nothing applied" "" "$(last_setup_steps)"
assert_no_file "all skipped: the plan is not kept" "${PLAN}"

# ── bad lines: numbered, the plan kept, the resume named ──
ed bad init --edit
assert_eq "bad plan: exit 1" 1 "${RC}"
n="$(grep -c '' "${SEEN}")"
assert_contains "bad plan: an unknown action" "${ERR}" "line $(( n + 1 )): unknown action; use apply or skip | line='frobnicate bob_neovim'"
assert_contains "bad plan: an unknown step" "${ERR}" "line $(( n + 2 )): not a step here (dotfiles steps) | step='nosuch'"
assert_contains "bad plan: two words after the action" "${ERR}" "line $(( n + 3 )): expected one step after the action"
assert_contains "bad plan: a step twice" "${ERR}" "line $(( n + 4 )): listed twice | step='bob_neovim'"
assert_contains "bad plan: a step with nothing to apply" "${ERR}" "line $(( n + 5 )): nothing to apply for brew in this check (ok present)"
assert_contains "bad plan: the resume" "${ERR}" "fix='dotfiles init --edit ${PLAN}'"
assert_file "bad plan: kept" "${PLAN}"
assert_eq "bad plan: nothing applied" "" "$(last_setup_steps)"

# Resumed: no checks, read against last-check.json; the setup is the only new run.
printf 'apply  bob_neovim  # resumed\n' > "${PLAN}"
before="$(run_count)"
ed noop init --edit "${PLAN}"
assert_eq "resumed: the setup is the only new run" "$(( before + 1 ))" "$(run_count)"
assert_not_contains "resumed: no checks first" "${OUT}" "nvim_missing"
assert_eq "resumed: the chosen step ran" bob_neovim "$(last_setup_steps)"
assert_no_file "resumed: the plan is gone" "${PLAN}"

# ── on a terminal, a bad plan is offered for another edit ──
tty bad init --edit
assert_eq "terminal, bad plan, declined: exit 1" 1 "${RC}"
assert_contains "terminal: another edit offered" "${OUT}" "Edit the plan again? [y/N]"
assert_file "terminal: the plan kept" "${PLAN}"

# ── a need that failed: its dependent cannot run without it ──
shim_remove brew
ed skip_brew init --edit
assert_eq "need skipped: exit 1" 1 "${RC}"
assert_contains "need skipped: the plan offers the unchecked step" "$(cat "${SEEN}")" "apply  brew_pkgs             # not checked (prerequisite_fail):"
line="$(grep -n '^apply  brew_pkgs' "${SEEN}" | cut -d: -f1)"
assert_contains "need skipped: an error naming the need" "${ERR}" "line ${line}: brew_pkgs needs brew, which ended fail brew_missing and is not applied here; apply brew too, or skip brew_pkgs"
shim_add brew

# ── nothing to apply: no plan, no editor ──
export BOB_SHIM_LS="Installed: v0.11.2 Used"
ed noop init --edit
assert_contains "nothing actionable: says so" "${OUT}" "init: nothing to apply"
assert_no_file "nothing actionable: the editor never opened" "${SEEN}"
assert_eq "nothing actionable: exit 0" 0 "${RC}"

report
