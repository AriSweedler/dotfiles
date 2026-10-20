#!/usr/bin/env bash
# `pull --edit`: after the pull, the affected steps open in $EDITOR as a plan, one
# `apply|skip STEP  # paths` line each, all apply; an unchanged plan runs, an empty one aborts,
# bad lines are numbered and the plan kept for `--edit FILE`, and the chosen steps run in a fresh
# `dotfiles apply`. A terminal only: the runs here get one from script(1).
set -u
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

world_new
world_use_fixture satisfied
seed_fake_repos
seed_ldf_remote
seed_home_baseline
REMOTE="${FIX}/remotes/dotfiles.git"
CLONE="${FIX}/clone"
git clone -q --bare "${ARI_DOTFILES_DF_GIT_DIR}" "${REMOTE}"
df_git remote add origin "${REMOTE}"
df_git fetch -q origin
df_git branch -q --set-upstream-to=origin/main main
git clone -q "${REMOTE}" "${CLONE}"
PLAN="${ARI_DOTFILES_STATE_DIR}/pull-plan.dfpull"
SEEN="${FIX}/seen.dfpull"

# remote_change FILE: a line appended to FILE on origin, pushed (hooks off).
remote_change() {
  mkdir -p "${CLONE}/$(dirname "$1")"; printf 'x\n' >> "${CLONE}/$1"
  git -C "${CLONE}" add "$1" && git -C "${CLONE}" -c core.hooksPath=/dev/null commit -q -m "edit $1"
  git -C "${CLONE}" push -q origin main
}

EDITORS="${FIX}/editors"
mkdir -p "${EDITORS}"
# editor NAME AWK: keeps a copy of the plan it is given in $SEEN, then rewrites it with AWK.
editor() { printf '#!/bin/sh\ncp "$1" "%s"\nawk %s "$1" > "$1.tmp" && mv "$1.tmp" "$1"\n' "${SEEN}" "'$2'" > "${EDITORS}/$1"; chmod +x "${EDITORS}/$1"; }
editor noop '{ print }'
editor skip_karabiner '{ sub(/^apply  karabiner/, "skip   karabiner") } { print }'
editor skip_all '{ sub(/^apply/, "skip ") } { print }'
editor empty '/^#/ || /^$/ { print }'
editor bad 'END { print "frobnicate karabiner"; print "apply nosuch"; print "apply karabiner extra"; print "skip karabiner" } { print }'

# tty ED ARGS...: `dotfiles ARGS` on a pseudo-terminal (script(1)) with EDITOR=ED, plain output,
# stdin at EOF (so a confirm prompt answers no). OUT holds both streams, carriage returns
# stripped; RC the exit code.
tty() {
  local ed="$1"; shift
  bump_now_secs 60
  rm -f "${SEEN}"
  hermetic_env
  RC=0
  env -i "${HERMETIC_ENV[@]}" ARI_DOTFILES_UI=plain "EDITOR=${EDITORS}/${ed}" \
    /usr/bin/script -q /dev/null "${FIX}/tools/zsh" "${ORIG_CONFIG_DIR}/bin/dotfiles" "$@" \
    < /dev/null > "${FIX}/tty.out" 2>&1 || RC=$?
  OUT="$(tr -d '\r' < "${FIX}/tty.out")"
}
last_setup_steps() { jq -r '[.steps[].step] | join(",")' "${ARI_DOTFILES_STATE_DIR}/last-setup.json" 2>/dev/null; }
clear_last_setup() { rm -f "${ARI_DOTFILES_STATE_DIR}/last-setup.json"; }

# ── a terminal only ──
nm pull --edit
assert_eq "no terminal: usage error" 64 "${RC}"
assert_contains "no terminal: says why" "${ERR}" "pull --edit opens \$EDITOR: it needs a terminal"
nm pull --edit "${FIX}/no-such.dfpull"
assert_eq "no terminal, with FILE: usage error" 64 "${RC}"

# ── nothing to pull: no plan, no editor ──
tty noop pull --edit
assert_eq "up to date: exit 0" 0 "${RC}"
assert_contains "up to date: says so" "${OUT}" "up to date: nothing to pull"
assert_contains "up to date: no plan" "${OUT}" "pull: no step to plan"
assert_no_file "up to date: the editor never opened" "${SEEN}"

# ── an unchanged plan runs as written (a dry run: nothing merged, the apply a dry run) ──
remote_change .config/karabiner/notes.txt
head_before="$(df_git rev-parse HEAD)"
clear_last_setup
tty noop --timing pull --dry-run --edit
assert_eq "unchanged plan: exit 0" 0 "${RC}"
assert_contains "the plan: one apply line per step, with its paths" "$(cat "${SEEN}")" "apply  karabiner     # .config/karabiner/notes.txt"
assert_contains "the plan: raycast_sync too" "$(cat "${SEEN}")" "apply  raycast_sync  # .config/karabiner/notes.txt"
assert_contains "the plan: names the actions" "$(cat "${SEEN}")" "#   skip    leave it"
assert_contains "unchanged plan: hands over to apply" "${OUT}" "running: dotfiles apply karabiner raycast_sync"
assert_eq "unchanged plan: the apply ran both" "karabiner,raycast_sync" "$(last_setup_steps)"
assert_eq "dry run: HEAD unchanged" "${head_before}" "$(df_git rev-parse HEAD)"
assert_no_file "a plan that ran is not kept" "${PLAN}"
took=""
[[ "${OUT}" =~ name=\'pull_changes\'\ took=\'([0-9.]+)s\' ]] && took="${BASH_REMATCH[1]}"
assert_eq "the analysis within 0.5 s, as without --edit (took ${took:-?}s)" 1 "$(awk -v t="${took:-9}" 'BEGIN { print (t <= 0.5) ? 1 : 0 }')"

# ── bad lines: numbered, the plan kept, the resume named ──
clear_last_setup
tty bad pull --dry-run --edit
assert_eq "bad plan: exit 1" 1 "${RC}"
n="$(grep -c '' "${SEEN}")"
assert_contains "bad plan: an unknown action" "${OUT}" "line $(( n + 1 )): unknown action; use apply or skip | line='frobnicate karabiner'"
assert_contains "bad plan: an unknown step" "${OUT}" "line $(( n + 2 )): not a step here (dotfiles steps) | step='nosuch'"
assert_contains "bad plan: two words after the action" "${OUT}" "line $(( n + 3 )): expected one step after the action"
assert_contains "bad plan: a step twice" "${OUT}" "line $(( n + 4 )): listed twice | step='karabiner'"
assert_contains "bad plan: the resume" "${OUT}" "fix='dotfiles pull --edit ${PLAN}'"
assert_file "bad plan: kept" "${PLAN}"
assert_eq "bad plan: nothing applied" "" "$(last_setup_steps)"

# Resumed: no second pull; this plan skips karabiner.
printf 'skip   karabiner\napply  raycast_sync  # resumed\n' > "${PLAN}"
tty noop --dry-run pull --edit "${PLAN}"
assert_eq "resumed: exit 0" 0 "${RC}"
assert_not_contains "resumed: no pull" "${OUT}" "would pull"
assert_contains "resumed: only the apply steps" "${OUT}" "running: dotfiles apply raycast_sync"
assert_eq "resumed: the apply ran raycast_sync alone" "raycast_sync" "$(last_setup_steps)"

# ── for real: every step skipped, then an empty plan, then an unchanged one ──
clear_last_setup
tty skip_all pull --edit
assert_eq "all skipped: exit 0" 0 "${RC}"
assert_eq "all skipped: pulled" "$(git -C "${CLONE}" rev-parse HEAD)" "$(df_git rev-parse HEAD)"
assert_contains "all skipped: says so" "${OUT}" "pull: every step skipped; nothing applied"
assert_contains "all skipped: the apply for later" "${OUT}" "next: dotfiles apply karabiner raycast_sync"
assert_eq "all skipped: nothing applied" "" "$(last_setup_steps)"

remote_change .config/karabiner/notes.txt
tty empty pull --edit
assert_eq "empty plan: exit 0" 0 "${RC}"
assert_contains "empty plan: aborted" "${OUT}" "pull: the plan has no step line; aborted, nothing applied"
assert_eq "empty plan: nothing applied" "" "$(last_setup_steps)"

remote_change .config/karabiner/notes.txt
tty skip_karabiner pull --edit
assert_eq "one skipped: exit 0" 0 "${RC}"
assert_contains "one skipped: the rest applied" "${OUT}" "running: dotfiles apply raycast_sync"
assert_eq "one skipped: the apply ran raycast_sync" "raycast_sync" "$(last_setup_steps)"
assert_eq "one skipped: setup mode, for real" setup "$(jq -r .mode "${ARI_DOTFILES_STATE_DIR}/last-setup.json")"

report
