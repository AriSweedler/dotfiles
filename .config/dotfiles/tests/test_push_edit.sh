#!/usr/bin/env bash
# `dotfiles push --edit`: a plan file of 'skip  <repo>  <sha>' lines, one per repo in scope with
# something to push, under its unpushed commits and the pointer bumps; on save every line is
# checked (action, repo, sha still HEAD, push shared not over a skipped submodule's bump), then
# the push runs for exactly the repos marked push. The world is test_push_summary's: local bare
# repos as remotes, and git's url.insteadOf sending each github.com URL to its bare repo, so a
# personal push lands locally. A pty (script(1)) covers the terminal path: editor, confirm.
set -u
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

PUSH_ZSH="${ORIG_CONFIG_DIR}/dotfiles/cmd/push.zsh"

# pz SCRIPT [ARG…]: the kernel plus cmd/push.zsh in the hermetic environment, then SCRIPT (zsh).
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

seed_fake_repos
seed_ldf_remote
export ARI_DOTFILES_GITHUB_LOGIN=push-edit-test
# gh answers the token and whose it is; the URLs it would authenticate never leave this machine.
printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> "%s/gh.log"\ncase "$1 $2" in\n  "auth token") echo test-token ;;\n  "api user") echo push-edit-test ;;\n  *) exit 1 ;;\nesac\n' \
  "${BREW_SHIM_LOG_DIR}" > "${FIX}/shims/gh"
chmod +x "${FIX}/shims/gh"

# sub_new PATH: a submodule checkout at ~/PATH with one commit, published to its bare repo, whose
# github URL git rewrites to that bare repo.
sub_new() {
  local dir="${HOME}/$1" bare="${FIX}/remotes/${1//\//-}.git" url="https://github.com/push-edit-test/${1##*/}.git"
  git init -q --initial-branch=main "${dir}"
  printf 'one\n' > "${dir}/f"
  git -C "${dir}" add f && git -C "${dir}" commit -q -m one
  git init -q --bare --initial-branch=main "${bare}"
  git -C "${dir}" push -q "${bare}" main
  git -C "${dir}" fetch -q "${bare}" main:refs/remotes/origin/main
  git -C "${dir}" remote add origin "${url}"
  git config --file "${HOME}/.config/git/config" "url.${bare}.pushInsteadOf" "${url}"
}
# sub_commit PATH MESSAGE [publish]: one more commit; published, it is in the bare repo and origin/main.
sub_commit() {
  local dir="${HOME}/$1" bare="${FIX}/remotes/${1//\//-}.git"
  printf '%s\n' "$2" >> "${dir}/f"
  git -C "${dir}" commit -q -am "$2"
  if [[ "${3:-}" == publish ]]; then
    git -C "${dir}" push -q "${bare}" main
    git -C "${dir}" fetch -q "${bare}" main:refs/remotes/origin/main
  fi
}

sub_new .config/ahead
sub_new .config/even
printf '[submodule "ahead"]\n\tpath = .config/ahead\n[submodule "even"]\n\tpath = .config/even\n[submodule "gone"]\n\tpath = .config/gone\n' > "${HOME}/.gitmodules"
df_git update-index --add --cacheinfo "160000,$(git -C "${HOME}/.config/ahead" rev-parse HEAD),.config/ahead"
df_git update-index --add --cacheinfo "160000,$(git -C "${HOME}/.config/even" rev-parse HEAD),.config/even"
df_git add "${HOME}/.gitmodules"
df_git -c core.hooksPath=/dev/null commit -q -m "submodules"
git init -q --bare --initial-branch=main "${FIX}/remotes/shared.git"
df_git push -q "${FIX}/remotes/shared.git" main
df_git fetch -q "${FIX}/remotes/shared.git" main:refs/remotes/origin/main
df_git remote add origin "https://github.com/push-edit-test/dotfiles.git"
git config --file "${HOME}/.config/git/config" "url.${FIX}/remotes/shared.git.pushInsteadOf" "https://github.com/push-edit-test/dotfiles.git"
# ahead: a commit origin lacks. even: published past its pointer. shared and local: one commit each.
sub_commit .config/ahead "ahead work"
sub_commit .config/even "even work" publish
printf 'shared\n' > "${HOME}/.config/push-edit.txt"
df_git add "${HOME}/.config/push-edit.txt" && df_git -c core.hooksPath=/dev/null commit -q -m "shared change"
mkdir -p "${HOME}/.local/push"
printf 'local\n' > "${HOME}/.local/push/edit.txt"
ldf_git add -f "${HOME}/.local/push/edit.txt" && ldf_git -c core.hooksPath=/dev/null commit -q -m "local change"

head12() { git -C "${HOME}/$1" rev-parse --short=12 HEAD; }
AHEAD="$(head12 .config/ahead)"
EVEN7="$(git -C "${HOME}/.config/even" rev-parse --short=7 HEAD)"
LOCAL="$(ldf_git rev-parse --short=12 HEAD)"
SHARED="$(df_git rev-parse --short=12 HEAD)"
PLAN="${XDG_STATE_HOME}/dotfiles/push-plan.dfpush"
remote_head() { git --git-dir="${FIX}/remotes/$1.git" rev-parse main; }
SHARED_REMOTE0="$(remote_head shared)"
LOCAL_REMOTE0="$(git --git-dir="${FIX}/remotes/local-dotfiles.git" rev-parse -q --verify main || true)"

# ── The plan: what it lists, under which comments ────────────────────────────

pz 'push::edit_plan "${(@f)$(push::edit_candidates)}"'
assert_eq "plan: rc 0" 0 "${RC}"
assert_eq "plan: line 1 names the plan type for the editor" "# dotfiles-plan: push · actions: push | skip" "${OUT%%$'\n'*}"
assert_eq "plan: one skip line per repo with something to push, in run order" \
  "skip            local  # ${LOCAL}|skip            .config/ahead  # ${AHEAD}|skip            shared  # ${SHARED}|" \
  "$(printf '%s\n' "${OUT}" | grep -v '^#' | grep . | tr "\n" "|")"
assert_contains "plan: a repo's header counts what origin lacks" "${OUT}" "# .config/ahead  main  1 commit origin/main lacks"
assert_contains "plan: the unpushed commit, as a comment" "${OUT}" "#   ${AHEAD:0:7} ahead work"
assert_contains "plan: the local tier's commit" "${OUT}" "local change"
assert_contains "plan: shared names the bump that waits on a submodule" "${OUT}" "#   pointer bump: ahead "
assert_contains "plan: ... and that it waits" "${OUT}" "-> ${AHEAD:0:7} (once .config/ahead is pushed)"
assert_contains "plan: shared names the bump of a published submodule" "${OUT}" "-> ${EVEN7}"$'\n'
assert_not_contains "plan: an up-to-date submodule has no line" "${OUT}" "skip            .config/even"
assert_not_contains "plan: a missing checkout has no line" "${OUT}" ".config/gone"
pz 'PUSH_SCOPE=(submodules); push::edit_candidates'
assert_eq "candidates: --submodules lists the submodules alone" ".config/ahead" "${OUT}"
pz 'PUSH_SCOPE=(local shared); push::edit_candidates'
assert_eq "candidates: no submodules in scope, so no bump makes shared a candidate unless it is ahead" "local shared" "$(printf '%s' "${OUT}" | tr '\n' ' ')"

# ── Usage: --edit needs a terminal or a FILE ─────────────────────────────────

nm push --edit
assert_eq "no terminal, no FILE: exit 64" 64 "${RC}"
assert_contains "no terminal: says why and the fix" "${ERR}" "needs a terminal"
assert_no_file "no terminal: no plan written" "${PLAN}"
nm push --edit "${FIX}/no-such.dfpush"
assert_eq "missing FILE: exit 64" 64 "${RC}"
assert_contains "missing FILE: named" "${ERR}" "no such plan file"
nm push --edit --dry-run
assert_eq "--edit then a flag is no FILE: exit 64" 64 "${RC}"

# plan FILE LINE…: a plan file holding those lines.
plan() { local f="$1"; shift; printf '%s\n' "$@" > "${f}"; }

# ── Bad lines: every one reported by number, nothing pushed ──────────────────

BAD="${FIX}/bad.dfpush"
plan "${BAD}" "# a comment" \
  "pusj  local  # ${LOCAL}" \
  "push  .config/nope  # ${AHEAD}" \
  "push  .config/ahead" \
  "push  shared  # 0000000000ab" \
  "skip  local  # later" \
  "skip  local" \
  "push  local  ${LOCAL}  extra" \
  ""
nm push --edit "${BAD}"
assert_eq "bad plan: exit 1" 1 "${RC}"
assert_contains "bad plan: an unknown action" "${ERR}" "line 2: unknown action; use push, skip"
assert_contains "bad plan: a repo with nothing to push here" "${ERR}" "line 3: not a repo with something to push in this scope (repos: local, .config/ahead, shared) | item='.config/nope'"
assert_contains "bad plan: a push line without its sha" "${ERR}" "line 4: a push line needs the sha the plan recorded"
assert_contains "bad plan: a sha that is not HEAD" "${ERR}" "line 5: shared moved since the plan was written | planned='0000000000ab'"
assert_contains "bad plan: a repo listed twice" "${ERR}" "line 7: listed twice | item='local'"
assert_contains "bad plan: too many words" "${ERR}" "line 8: expected one repo after 'push' | line='push  local  ${LOCAL}  extra'"
assert_not_contains "bad plan: a trailing comment is fine" "${ERR}" "line 6:"
assert_contains "bad plan: the fix resumes the file" "${ERR}" "fix='dotfiles push --edit ${BAD}'"
assert_eq "bad plan: gh never called" "" "$(shim_log gh)"
assert_eq "bad plan: shared remote untouched" "${SHARED_REMOTE0}" "$(remote_head shared)"
assert_eq "bad plan: no bump committed" "${SHARED}" "$(df_git rev-parse --short=12 HEAD)"
assert_eq "bad plan: the file is kept as written" "pusj  local  # ${LOCAL}" "$(awk "NR == 2" "${BAD}")"

# push shared over a skipped submodule whose pointer it would bump.
SH="${FIX}/shared-only.dfpush"
plan "${SH}" "skip  local  # ${LOCAL}" "skip  .config/ahead  # ${AHEAD}" "push  shared  # ${SHARED}"
nm push --edit "${SH}"
assert_eq "push shared, ahead skipped: exit 1" 1 "${RC}"
assert_contains "push shared, ahead skipped: refused on the shared line" "${ERR}" "line 3: push shared while .config/ahead is skipped; the shared tier would carry its unpublished pointer"
plan "${SH}" "skip  local  # ${LOCAL}" "push  shared  # ${SHARED}"
nm push --edit "${SH}"
assert_eq "push shared, ahead's line deleted: refused the same" 1 "${RC}"
assert_contains "push shared, ahead's line deleted: names it" "${ERR}" "while .config/ahead is skipped"
nm push --edit "${SH}" --no-submodules --dry-run
assert_eq "push shared with the submodules out of scope: no bump to protect" 0 "${RC}"

# All skip: nothing to do.
plan "${SH}" "skip  local  # ${LOCAL}" "skip  .config/ahead  # ${AHEAD}" "skip  shared  # ${SHARED}"
nm push --edit "${SH}"
assert_eq "all skip: exit 0" 0 "${RC}"
assert_contains "all skip: says so" "${OUT}" "every line is skip; nothing pushed"
assert_eq "all skip: gh never called" "" "$(shim_log gh)"

# ── --dry-run combines: would-push lines for the chosen repos only ───────────

DRY="${FIX}/dry.dfpush"
plan "${DRY}" "push  local  # ${LOCAL}" "skip  .config/ahead  # ${AHEAD}" "skip  shared  # ${SHARED}"
nm push --edit "${DRY}" --dry-run
assert_eq "dry-run, local only: exit 0" 0 "${RC}"
assert_contains "dry-run, local only: would push local" "${ERR}" "dry-run, would push | repo='local'"
assert_not_contains "dry-run, local only: not ahead" "${ERR}" "would push | repo='.config/ahead'"
assert_not_contains "dry-run, local only: not shared" "${ERR}" "would push | repo='shared'"
assert_not_contains "dry-run, local only: shared skipped, so no bump of even" "${ERR}" "would bump"
assert_contains "dry-run: the plan line" "${OUT}" "plan: push local"
assert_contains "dry-run: next runs the plan for real" "${OUT}" "next: dotfiles push --edit ${DRY}"
plan "${DRY}" "push  .config/ahead  # ${AHEAD}" "push  shared  # ${SHARED}"
nm push --edit "${DRY}" --dry-run
assert_eq "dry-run, ahead and shared: exit 0" 0 "${RC}"
assert_contains "dry-run, ahead and shared: would push ahead" "${ERR}" "would push | repo='.config/ahead'"
assert_contains "dry-run, ahead and shared: would bump even" "${ERR}" "would bump | repo='.config/even'"
assert_contains "dry-run, ahead and shared: would push shared" "${ERR}" "would push | repo='shared'"
assert_not_contains "dry-run, ahead and shared: local's line deleted, so not local" "${ERR}" "would push | repo='local'"
assert_eq "dry-run: gh never called" "" "$(shim_log gh)"
assert_eq "dry-run: shared remote untouched" "${SHARED_REMOTE0}" "$(remote_head shared)"

# ── A repo that moved since the plan ─────────────────────────────────────────

MOVED="${FIX}/moved.dfpush"
plan "${MOVED}" "push  .config/ahead  # ${AHEAD}"
sub_commit .config/ahead "ahead more"
nm push --edit "${MOVED}" --submodules
assert_eq "moved: exit 1" 1 "${RC}"
assert_contains "moved: planned and now named" "${ERR}" "line 1: .config/ahead moved since the plan was written | planned='${AHEAD}' now='$(head12 .config/ahead)'"
assert_eq "moved: ahead's remote untouched" 1 "$(git --git-dir="${FIX}/remotes/.config-ahead.git" rev-list --count main)"
AHEAD="$(head12 .config/ahead)"

# ── A real push of the chosen repos: ahead alone, then shared ────────────────

shim_logs_reset
REAL="${FIX}/real.dfpush"
plan "${REAL}" "skip  local  # ${LOCAL}" "push  .config/ahead  # ${AHEAD}" "skip  shared  # ${SHARED}"
nm push --edit "${REAL}"
assert_eq "ahead only: exit 0" 0 "${RC}"
assert_eq "ahead only: its remote has HEAD" "$(git -C "${HOME}/.config/ahead" rev-parse HEAD)" "$(git --git-dir="${FIX}/remotes/.config-ahead.git" rev-parse main)"
assert_eq "ahead only: its bump is committed, as --submodules commits it" "ahead: bump to ${AHEAD:0:7} (2 commits, latest: ahead more)" "$(df_git log -1 --format=%s)"
assert_eq "ahead only: even's bump waits for the shared push" "" "$(df_git log --format=%s "${SHARED}..HEAD" | grep '^even:' || true)"
assert_eq "ahead only: shared remote untouched" "${SHARED_REMOTE0}" "$(remote_head shared)"
assert_eq "ahead only: local remote untouched" "${LOCAL_REMOTE0}" "$(git --git-dir="${FIX}/remotes/local-dotfiles.git" rev-parse -q --verify main || true)"
assert_contains "ahead only: authenticated as the login" "$(shim_log gh)" "api user"
assert_contains "ahead only: next" "${OUT}" "next: dotfiles status"

SHARED="$(df_git rev-parse --short=12 HEAD)"
pz 'push::edit_candidates'
assert_eq "after ahead: local and shared remain" "local shared" "$(printf '%s' "${OUT}" | tr '\n' ' ')"
plan "${REAL}" "skip  local  # ${LOCAL}" "push  shared  # ${SHARED}"
nm push --edit "${REAL}"
assert_eq "shared: exit 0" 0 "${RC}"
assert_eq "shared: even's bump committed before the push" "even: bump to ${EVEN7} (even work)" "$(df_git log -1 --format=%s)"
assert_eq "shared: its remote has HEAD, bumps included" "$(df_git rev-parse HEAD)" "$(remote_head shared)"
assert_eq "shared: local still unpushed" "${LOCAL_REMOTE0}" "$(git --git-dir="${FIX}/remotes/local-dotfiles.git" rev-parse -q --verify main || true)"

# ── On a terminal: the editor, then one confirmation ─────────────────────────

SCRIPT_BIN=/usr/bin/script
if [[ -x "${SCRIPT_BIN}" ]]; then
  EDITORS="${FIX}/editors"
  mkdir -p "${EDITORS}"
  printf '%s\n' '#!/bin/sh' "cp \"\$1\" \"${FIX}/plan.given\"" \
    "awk '{ sub(/^skip +local /, \"push  local \"); print }' \"\$1\" > \"\$1.tmp\" && mv \"\$1.tmp\" \"\$1\"" > "${EDITORS}/choose"
  printf '#!/bin/sh\nexit 0\n' > "${EDITORS}/keep"
  chmod +x "${EDITORS}"/*
  # tty_push EDITOR ANSWER ARGS…: `dotfiles push ARGS` on a pty. Input typed before the prompt is
  # lost, so ANSWER is typed once the editor has run (it leaves plan.given), a beat later; then
  # stdin closes. An empty ANSWER types nothing.
  tty_push() {
    local ed="$1" answer="$2"; shift 2
    hermetic_env
    RC=0
    rm -f "${FIX}/plan.given"
    {
      if [[ -n "${answer}" ]]; then
        for (( i = 0; i < 100; i++ )); do [[ -f "${FIX}/plan.given" ]] && break; sleep 0.1; done
        sleep 0.5; printf '%s\n' "${answer}"; sleep 0.5
      fi
    } | "${SCRIPT_BIN}" -q /dev/null env -i "${HERMETIC_ENV[@]}" "EDITOR=${EDITORS}/${ed}" \
      "${FIX}/tools/zsh" "${ORIG_CONFIG_DIR}/bin/dotfiles" push "$@" > "${FIX}/tty.out" 2>&1 || RC=$?
    OUT="$(tr -d '\r' < "${FIX}/tty.out")"
  }
  tty_push keep "" --edit
  assert_eq "tty, saved unchanged: exit 0" 0 "${RC}"
  assert_contains "tty, saved unchanged: no change" "${OUT}" "no change; nothing pushed"
  assert_file "tty: the plan is written to the state dir" "${PLAN}"
  tty_push choose n --edit
  assert_eq "tty, declined: exit 1" 1 "${RC}"
  assert_contains "tty: the editor got the plan" "$(cat "${FIX}/plan.given")" "skip            local  # ${LOCAL}"
  assert_contains "tty: one confirmation" "${OUT}" "Push 1 repo? [y/N]"
  assert_contains "tty, declined: says so" "${OUT}" "declined; nothing pushed"
  assert_eq "tty, declined: local remote untouched" "${LOCAL_REMOTE0}" "$(git --git-dir="${FIX}/remotes/local-dotfiles.git" rev-parse -q --verify main || true)"
  tty_push choose y --edit
  assert_eq "tty, confirmed: exit 0" 0 "${RC}"
  assert_eq "tty, confirmed: local pushed" "$(ldf_git rev-parse HEAD)" "$(git --git-dir="${FIX}/remotes/local-dotfiles.git" rev-parse main)"
  tty_push keep "" --edit
  assert_contains "tty: everything at origin, nothing to plan" "${OUT}" "nothing to push: every repo in scope is at origin"
else
  pass "tty cases skipped: no ${SCRIPT_BIN}"
fi

report
