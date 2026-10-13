#!/usr/bin/env bash
# `dotfiles push` ends with one table of what happened per repo, on a terminal only: the pure
# push::summary_tsv for every kind of row, then push runs in a world whose remotes are local bare
# repos (a gh stub that fails, so no personal push can reach the network) — dry-run and real —
# with the table absent from plain output and present, painted, when fancy.
set -u
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

PUSH_ZSH="${ORIG_CONFIG_DIR}/dotfiles/cmd/push.zsh"

# pz SCRIPT [ARG…]: the kernel plus cmd/push.zsh in the hermetic environment, then SCRIPT (zsh)
# with ARGs as its positional parameters; captures OUT, ERR, RC.
pz() {
  local script="$1"; shift
  hermetic_env
  RC=0
  env -i "${HERMETIC_ENV[@]}" "${FIX}/tools/zsh" -c 'for f in "$1"/*.zsh(N); do source "${f}"; done; source "$2"; s="$3"; shift 3; eval "${s}"' _ \
    "${ORIG_CONFIG_DIR}/dotfiles/lib" "${PUSH_ZSH}" "${script}" "$@" > "${FIX}/pz.out" 2> "${FIX}/pz.err" || RC=$?
  OUT="$(cat "${FIX}/pz.out")"
  ERR="$(cat "${FIX}/pz.err")"
}

world_new

# ── push::summary_tsv: pure ──────────────────────────────────────────────────

SHA=0123456789abcdef0123456789abcdef01234567
T=$'\t'
pz 'local -a PUSH_ROWS=()
  push::record local pushed "$1" 1.25 "${HOME}/.local/state/dotfiles/push/local.log"
  push::record shared "up to date" "$1"
  push::record .config/plugged failed "$1" 0.50 "${HOME}/.local/state/dotfiles/push/config-plugged.log"
  push::record .config/karabiner "skipped (not checked out)"
  push::record "plugged pointer" bumped "$1"
  push::record "odd${2}name" "failed (token)"
  push::summary_tsv "${PUSH_ROWS[@]}"' "${SHA}" $'\t'
assert_eq "summary_tsv: rc 0" 0 "${RC}"
assert_eq "summary_tsv: header, then one line per row" 7 "$(printf '%s\n' "${OUT}" | wc -l | tr -d ' ')"
L=(); while IFS= read -r line; do L+=("${line}"); done <<< "${OUT}"
assert_eq "summary_tsv: header" "repo${T}result${T}sha${T}took${T}log" "${L[0]}"
assert_eq "summary_tsv: pushed has sha, took and ~ log" "local${T}pushed${T}0123456${T}1.25s${T}~/.local/state/dotfiles/push/local.log" "${L[1]}"
assert_eq "summary_tsv: up to date has sha only" "shared${T}up to date${T}0123456${T}${T}" "${L[2]}"
assert_eq "summary_tsv: failed keeps took and log" ".config/plugged${T}failed${T}0123456${T}0.50s${T}~/.local/state/dotfiles/push/config-plugged.log" "${L[3]}"
assert_eq "summary_tsv: skipped names why, nothing else" ".config/karabiner${T}skipped (not checked out)${T}${T}${T}" "${L[4]}"
assert_eq "summary_tsv: a bump is '<name> pointer' bumped" "plugged pointer${T}bumped${T}0123456${T}${T}" "${L[5]}"
assert_eq "summary_tsv: a tab inside a field becomes a space" "odd name${T}failed (token)${T}${T}${T}" "${L[6]}"
pz 'push::summary_tsv'
assert_eq "summary_tsv: no rows is the header alone" "repo${T}result${T}sha${T}took${T}log" "${OUT}"

pz 'for r in pushed bumped "would push" "would bump" failed "failed (token)" "up to date" "skipped (no remote)"; do print -r -- "$(push::result_status "${r}")"; done'
assert_eq "result_status: done ok, plan warn, failed fail, no-op skip" "ok ok warn warn fail fail skip skip" "$(printf '%s' "${OUT}" | tr '\n' ' ')"

# ── A world: shared, local, three submodules, local bare repos as remotes ────

seed_fake_repos
seed_ldf_remote
# gh is a prerequisite of push; this one has no token, so a personal push fails before any network.
printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> "%s/gh.log"\nexit 1\n' "${BREW_SHIM_LOG_DIR}" > "${FIX}/shims/gh"
chmod +x "${FIX}/shims/gh"
FAKE_GUM="${FIX}/fakegum"
printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> "%s/gum.log"\n' "${BREW_SHIM_LOG_DIR}" > "${FAKE_GUM}"
chmod +x "${FAKE_GUM}"

# sub_new PATH: a submodule checkout at ~/PATH with one commit, published to a local bare repo
# whose state is origin/main; origin's URL is the github one push_target wants (never contacted).
sub_new() {
  local dir="${HOME}/$1" bare="${FIX}/remotes/${1//\//-}.git"
  git init -q --initial-branch=main "${dir}"
  printf 'one\n' > "${dir}/f"
  git -C "${dir}" add f && git -C "${dir}" commit -q -m one
  git init -q --bare --initial-branch=main "${bare}"
  git -C "${dir}" push -q "${bare}" main
  git -C "${dir}" fetch -q "${bare}" main:refs/remotes/origin/main
  git -C "${dir}" remote add origin "https://github.com/push-summary-test/${1##*/}.git"
}
# sub_commit PATH [publish]: one more commit; published, it is in the bare repo and origin/main too.
sub_commit() {
  local dir="${HOME}/$1" bare="${FIX}/remotes/${1//\//-}.git"
  printf 'more %s\n' "${RANDOM}" >> "${dir}/f"
  git -C "${dir}" commit -q -am more
  if [[ "${2:-}" == publish ]]; then
    git -C "${dir}" push -q "${bare}" main
    git -C "${dir}" fetch -q "${bare}" main:refs/remotes/origin/main
  fi
}

sub_new .config/ahead
sub_new .config/even
printf '[submodule "ahead"]\n\tpath = .config/ahead\n[submodule "even"]\n\tpath = .config/even\n[submodule "gone"]\n\tpath = .config/gone\n' > "${HOME}/.gitmodules"
# The shared tier records both pointers at their first commit, then publishes to its bare remote.
df_git update-index --add --cacheinfo "160000,$(git -C "${HOME}/.config/ahead" rev-parse HEAD),.config/ahead"
df_git update-index --add --cacheinfo "160000,$(git -C "${HOME}/.config/even" rev-parse HEAD),.config/even"
df_git add "${HOME}/.gitmodules"
df_git -c core.hooksPath=/dev/null commit -q -m "submodules"
git init -q --bare --initial-branch=main "${FIX}/remotes/shared.git"
df_git push -q "${FIX}/remotes/shared.git" main
df_git fetch -q "${FIX}/remotes/shared.git" main:refs/remotes/origin/main
df_git remote add origin "https://github.com/push-summary-test/dotfiles.git"
# ahead: a commit origin lacks. even: a commit origin has, past its pointer. shared and local: ahead.
sub_commit .config/ahead
sub_commit .config/even publish
printf 'shared\n' > "${HOME}/.config/push-summary.txt"
df_git add "${HOME}/.config/push-summary.txt" && df_git -c core.hooksPath=/dev/null commit -q -m "shared change"
mkdir -p "${HOME}/.local/push"
printf 'local\n' > "${HOME}/.local/push/summary.txt"
ldf_git add -f "${HOME}/.local/push/summary.txt" && ldf_git -c core.hooksPath=/dev/null commit -q -m "local change"
AHEAD_SHA="$(git -C "${HOME}/.config/ahead" rev-parse --short=7 HEAD)"
EVEN_SHA="$(git -C "${HOME}/.config/even" rev-parse --short=7 HEAD)"
LOCAL_SHA="$(ldf_git rev-parse --short=7 HEAD)"
SHARED_SHA="$(df_git rev-parse --short=7 HEAD)"

# table_after PATTERN: the lines of ERR after the one matching PATTERN, colour escapes stripped.
table_after() { printf '%s\n' "${ERR}" | awk -v pat="$1" 'f { gsub(/\033\[[0-9;]*m/, ""); print } $0 ~ pat { f = 1 }'; }
# row PATTERN: TABLE's line starting with PATTERN, runs of spaces squeezed.
row() { printf '%s\n' "${TABLE}" | grep -E "^$1 " | tr -s ' '; }

# ── Dry run, plain: the log lines alone ──────────────────────────────────────

shim_logs_reset
nm push --dry-run
assert_eq "dry-run plain: exit 0" 0 "${RC}"
assert_eq "dry-run plain: stdout empty" "" "${OUT}"
assert_contains "dry-run plain: would push a submodule" "${ERR}" "dry-run, would push | repo='.config/ahead'"
assert_not_contains "dry-run plain: no table header" "${ERR}" "result"
assert_eq "dry-run plain: gh never called" "" "$(shim_log gh)"

# ── Dry run, fancy: the table after the last log line ───────────────────────

export ARI_DOTFILES_UI=fancy ARI_DOTFILES_GUM="${FAKE_GUM}" COLUMNS=200
shim_logs_reset
nm push --dry-run
assert_eq "dry-run fancy: exit 0" 0 "${RC}"
assert_eq "dry-run fancy: stdout empty" "" "${OUT}"
assert_eq "dry-run fancy: the table draws no gum" "" "$(shim_log gum)"
assert_eq "dry-run fancy: gh never called" "" "$(shim_log gh)"
TABLE="$(table_after 'push done')"
assert_contains "dry-run fancy: the table follows 'push done'" "$(printf '%s\n' "${ERR}" | tail -n 9 | head -n 1)" "push done"
assert_eq "dry-run fancy: header then seven rows" 8 "$(printf '%s\n' "${TABLE}" | wc -l | tr -d ' ')"
assert_eq "dry-run fancy: header" "repo" "$(printf '%s\n' "${TABLE}" | head -n 1 | awk '{print $1}')"
assert_eq "dry-run fancy: local would push" "local would push ${LOCAL_SHA}" "$(row local)"
assert_eq "dry-run fancy: ahead would push" ".config/ahead would push ${AHEAD_SHA}" "$(row '\.config/ahead')"
assert_eq "dry-run fancy: even up to date" ".config/even up to date ${EVEN_SHA}" "$(row '\.config/even')"
assert_eq "dry-run fancy: gone skipped" ".config/gone skipped (not checked out)" "$(row '\.config/gone')"
assert_eq "dry-run fancy: ahead pointer would bump" "ahead pointer would bump ${AHEAD_SHA}" "$(row 'ahead pointer')"
assert_eq "dry-run fancy: even pointer would bump" "even pointer would bump ${EVEN_SHA}" "$(row 'even pointer')"
assert_eq "dry-run fancy: shared would push" "shared would push ${SHARED_SHA}" "$(row shared)"
assert_contains "dry-run fancy: results painted (would = yellow 178)" "${ERR}" $'\e[38;5;178mwould push\e[0m'
assert_contains "dry-run fancy: header bold" "${ERR}" $'\e[1mrepo'

# ── Real push, fancy: local to its bare remote; personal pushes fail on the token ──

shim_logs_reset
nm push
assert_eq "push fancy: exit 1 (a submodule failed)" 1 "${RC}"
assert_eq "push fancy: local reached its bare remote" "$(ldf_git rev-parse HEAD)" "$(git --git-dir="${FIX}/remotes/local-dotfiles.git" rev-parse main)"
assert_eq "push fancy: nothing reached ahead's remote" 1 "$(git --git-dir="${FIX}/remotes/.config-ahead.git" rev-list --count main)"
TABLE="$(table_after 'push failed [|] scope')"
assert_eq "push fancy: header then six rows" 7 "$(printf '%s\n' "${TABLE}" | wc -l | tr -d ' ')"
assert_eq "push fancy: ahead failed on the token" ".config/ahead failed (token)" "$(row '\.config/ahead')"
assert_eq "push fancy: even up to date" ".config/even up to date ${EVEN_SHA}" "$(row '\.config/even')"
assert_eq "push fancy: gone skipped" ".config/gone skipped (not checked out)" "$(row '\.config/gone')"
assert_contains "push fancy: even pointer bumped" "$(row 'even pointer')" "even pointer bumped ${EVEN_SHA}"
assert_eq "push fancy: shared skipped behind the failure" "shared skipped (a submodule failed)" "$(row shared)"
assert_contains "push fancy: local pushed, with took and log" "$(row local)" "local pushed ${LOCAL_SHA} "
assert_contains "push fancy: local's log under ~" "$(row local)" "s ~/.local/state/dotfiles/push/local.log"
assert_contains "push fancy: failed painted red" "${ERR}" $'\e[38;5;196mfailed (token)\e[0m'
assert_contains "push fancy: pushed painted green" "${ERR}" $'\e[38;5;71mpushed\e[0m'
assert_eq "push fancy: the bump is committed" "even: bump to ${EVEN_SHA} (more)" "$(df_git log -1 --format=%s)"

# ── The same failure, plain: no table ────────────────────────────────────────

unset ARI_DOTFILES_UI ARI_DOTFILES_GUM COLUMNS
sub_commit .config/even publish
ldf_git commit -q --allow-empty -m "local again"
nm push
assert_eq "push plain: exit 1" 1 "${RC}"
assert_contains "push plain: the last line is the verdict" "$(printf '%s\n' "${ERR}" | tail -n 1)" "push failed | scope="
assert_not_contains "push plain: no table row" "${ERR}" "skipped (a submodule failed)"

report
