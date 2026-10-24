#!/usr/bin/env bash
# `healthcheck --edit [FILE]`: the checks and their table as healthcheck prints them; then, when a
# step has something to apply, a plan of `skip STEP  # reason: …` lines (the healthcheck applies
# nothing on its own), manual fixes as comments that never run; a confirm; the lock let go; then a
# fresh `dotfiles apply` of the chosen steps. FILE resumes against last-check.json. A terminal
# only, unless FILE is given; never with --json.
set -u
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

world_new
world_use_fixture satisfied
seed_fake_repos
seed_ldf_remote
seed_home_baseline
unset BOB_SHIM_LS   # bob_neovim fails, with an apply; terminal_nerdfont warns, manual
PLAN="${ARI_DOTFILES_STATE_DIR}/healthcheck-plan.dfcheck"
SEEN="${FIX}/seen.dfcheck"
LOCKSEEN="${FIX}/lockseen"

EDITORS="${FIX}/editors"
mkdir -p "${EDITORS}"
editor() {
  printf '#!/bin/sh\n[ -e "%s" ] && echo held >> "%s"\ncp "$1" "%s"\nawk %s "$1" > "$1.tmp" && mv "$1.tmp" "$1"\n' \
    "${ARI_DOTFILES_STATE_DIR}/lock.d" "${LOCKSEEN}" "${SEEN}" "'$2'" > "${EDITORS}/$1"
  chmod +x "${EDITORS}/$1"
}
editor noop '{ print }'
editor apply_bob '{ sub(/^skip +bob_neovim /, "apply  bob_neovim ") } { print }'
editor skip_bob '/^skip/ { print "# dropped: " $0; next } { print }'
editor manual 'END { print "apply terminal_nerdfont" } { print }'

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
# tty ED ANSWER ARGS...: on a pseudo-terminal (script(1)), plain output; ANSWER is typed once a
# confirm asks (empty: stdin at EOF, so a confirm answers no). OUT holds both streams.
tty() {
  local e="$1" answer="$2"; shift 2
  bump_now_secs 60
  rm -f "${SEEN}"
  : > "${FIX}/tty.out"
  hermetic_env
  RC=0
  answer_when_asked "${answer}" | env -i "${HERMETIC_ENV[@]}" ARI_DOTFILES_UI=plain "EDITOR=${EDITORS}/${e}" \
    /usr/bin/script -q /dev/null "${FIX}/tools/zsh" "${ORIG_CONFIG_DIR}/bin/dotfiles" "$@" \
    > "${FIX}/tty.out" 2>&1 || RC=$?
  OUT="$(tr -d '\r' < "${FIX}/tty.out")"
}
# Typed into the terminal only once the prompt is on it, so nothing earlier reads it; then held
# open until the run hands over, so the end of input does not reach the prompt first.
answer_when_asked() {
  [[ -n "$1" ]] || return 0
  local i
  for (( i = 0; i < 300; i++ )); do grep -q '\[y/N\]' "${FIX}/tty.out" 2>/dev/null && break; sleep 0.1; done
  printf '%s\n' "$1"
  for (( i = 0; i < 300; i++ )); do grep -q -e 'running:' -e 'not confirmed' "${FIX}/tty.out" 2>/dev/null && break; sleep 0.1; done
}
# pl ACTION: how lib/plan.zsh's plan::line starts a line: the action, padded, then two spaces.
pl() { printf '%-14s  ' "$1"; }
last_setup_steps() { jq -r '[.steps[].step] | join(",")' "${ARI_DOTFILES_STATE_DIR}/last-setup.json" 2>/dev/null; }
clear_last_setup() { rm -f "${ARI_DOTFILES_STATE_DIR}/last-setup.json"; }
run_count() { local n=0 d; for d in "${ARI_DOTFILES_STATE_DIR}"/runs/*/; do [[ -d "${d}" ]] && n=$((n + 1)); done; printf '%s' "${n}"; }

# ── usage ──
nm check --edit
assert_eq "no terminal, no FILE: usage error" 64 "${RC}"
assert_contains "no terminal: says why" "${ERR}" "healthcheck --edit opens \$EDITOR: it needs a terminal"
nm check --edit --json
assert_eq "--edit --json: usage error" 64 "${RC}"
nm check --edit a.dfcheck b.dfcheck
assert_eq "--edit with two files: usage error" 64 "${RC}"
nm check extra
assert_eq "no --edit: a positional is still a usage error" 64 "${RC}"
mkdir -p "${ARI_DOTFILES_STATE_DIR}"
printf 'apply  bob_neovim\n' > "${PLAN}"
ed noop healthcheck --edit "${PLAN}"
assert_eq "FILE before any check: exit 1" 1 "${RC}"
assert_contains "FILE before any check: says so" "${ERR}" "no check to read the plan against"
rm -f "${PLAN}"

# ── the table, then a plan where every line is skip; unchanged applies nothing ──
tty noop "" healthcheck --edit
assert_eq "unchanged: the healthcheck's exit code" 1 "${RC}"
assert_contains "the table as healthcheck prints it" "${OUT}" "fail   bob_neovim             nvim_missing"
assert_contains "the roll-up" "${OUT}" "status: fail (fail=1"
plan="$(cat "${SEEN}")"
assert_eq "the plan: line 1 names its kind and actions (the dotfilesplan filetype reads it)" "# dotfiles-plan: healthcheck · actions: apply | skip" "$(head -n 1 "${SEEN}")"
assert_contains "the plan: the actionable step starts as skip" "${plan}" \
  "$(pl skip)bob_neovim            # nvim_missing: installs the latest neovim with bob and makes it the one in use"
assert_contains "the plan: a manual fix is a comment" "${plan}" "#   warn   terminal_nerdfont     manual_font:"
assert_contains "the plan: says the healthcheck applies nothing by itself" "${plan}" "every line starts as skip"
assert_contains "unchanged: says so" "${OUT}" "healthcheck: no change; nothing applied"
assert_contains "unchanged: the apply for later" "${OUT}" "next: dotfiles apply bob_neovim"
assert_eq "the editor ran without the lock" "" "$(cat "${LOCKSEEN}" 2>/dev/null)"
assert_eq "unchanged: nothing applied" "" "$(last_setup_steps)"

# ── a manual fix is never executed ──
tty manual "" healthcheck --edit
assert_eq "apply of a manual step: exit 1" 1 "${RC}"
assert_contains "apply of a manual step: refused" "${OUT}" "nothing to apply for terminal_nerdfont in this check (warn manual_font)"
assert_contains "apply of a manual step: the resume" "${OUT}" "fix='dotfiles healthcheck --edit ${PLAN}'"
assert_contains "terminal: another edit offered" "${OUT}" "Edit the plan again? [y/N]"
assert_file "bad plan: kept" "${PLAN}"

# ── chosen, declined at the confirm: the plan stays ──
tty apply_bob "" healthcheck --edit
assert_contains "the confirm names the apply" "${OUT}" "Run dotfiles apply bob_neovim? [y/N]"
assert_contains "declined: says so" "${OUT}" "healthcheck: not confirmed; nothing applied"
assert_contains "declined: the resume" "${OUT}" "next: dotfiles healthcheck --edit ${PLAN}"
assert_eq "declined: nothing applied" "" "$(last_setup_steps)"
assert_file "declined: kept" "${PLAN}"

# ── chosen and confirmed: a fresh apply of exactly those steps ──
tty apply_bob y healthcheck --edit
assert_contains "confirmed: hands over" "${OUT}" "running: dotfiles apply bob_neovim"
assert_eq "confirmed: the apply ran bob_neovim" bob_neovim "$(last_setup_steps)"
assert_contains "confirmed: bob's apply ran" "$(shim_log bob)" "install latest"
assert_no_file "confirmed: the plan is gone" "${PLAN}"
assert_no_file "lock released" "${ARI_DOTFILES_STATE_DIR}/lock.d"

# ── every step line dropped: nothing to run ──
clear_last_setup
tty skip_bob "" healthcheck --edit
assert_contains "no step line: says so" "${OUT}" "healthcheck: the plan has no step line; nothing applied"
assert_eq "no step line: nothing applied" "" "$(last_setup_steps)"

# ── FILE: no checks, read against last-check.json; off a terminal no confirm ──
printf 'apply  bob_neovim  # resumed\n' > "${PLAN}"
before="$(run_count)"
ed noop healthcheck --dry-run --edit "${PLAN}"
assert_eq "resumed: exit as the apply does" 1 "${RC}"
assert_eq "resumed: the apply is the only new run" "$(( before + 1 ))" "$(run_count)"
assert_contains "resumed, --dry-run: the apply is a dry run" "${OUT}" "running: dotfiles apply --dry-run bob_neovim"
assert_json "resumed, --dry-run: would apply" "${ARI_DOTFILES_STATE_DIR}/last-setup.json" '.steps[0].applied' would_apply

# ── nothing actionable: no plan, no editor, the healthcheck's exit ──
export BOB_SHIM_LS="Installed: v0.11.2 Used"
tty noop "" healthcheck --edit
assert_eq "nothing actionable: exit 0" 0 "${RC}"
assert_contains "nothing actionable: says so" "${OUT}" "healthcheck: nothing to apply"
assert_no_file "nothing actionable: the editor never opened" "${SEEN}"

report
