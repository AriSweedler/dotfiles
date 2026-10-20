#!/usr/bin/env bash
# `--local git --edit`: the local tier's allowlist template edited as a draft, checked (starts
# '/*', no secret admitted, every '!' entry says why), put in place, installed as info/exclude only
# when this machine's copy matched it, and committed in the shared tier; `git ARGS` otherwise
# reaches git untouched (`git commit --edit` included), and the shared tier has no --edit.
set -u
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

world_new
seed_fake_repos
TEMPLATE="${ARI_DOTFILES_SHARED_DIR}/local-dotfiles-exclude"
EXCLUDE="${ARI_DOTFILES_LDF_GIT_DIR}/info/exclude"
DRAFT="${ARI_DOTFILES_STATE_DIR}/drafts/git/local-dotfiles-exclude"

EDITORS="${FIX}/editors"
mkdir -p "${EDITORS}"
# editor NAME AWK: rewrites the file it is given with AWK.
editor() { printf '#!/bin/sh\nawk %s "$1" > "$1.tmp" && mv "$1.tmp" "$1"\n' "'$2'" > "${EDITORS}/$1"; chmod +x "${EDITORS}/$1"; }
editor noop '{ print }'
editor add_zz '/^# Secrets live in/ { print "# A directory the test admits."; print "!/share/zz/" } { print }'
editor add_zz_bare '/^# Secrets live in/ { print "!/share/zz/" } { print }'
editor no_star '$0 != "/*" { print }'
editor no_secrets '$0 != "*.secret.zsh" { print }'
editor trailing_space '/^!\/share\/kuber\/$/ { print $0 "  "; next } { print }'
editor git_msg 'NR == 1 { $0 = $0 " (edited by git)" } { print }'
printf '#!/bin/sh\nexit 3\n' > "${EDITORS}/broken"; chmod +x "${EDITORS}/broken"

# run EDITOR ARGS...: `dotfiles ARGS` with that editor, no terminal.
run() {
  local ed="$1"; shift
  bump_now_secs 60
  hermetic_env
  HERMETIC_ENV+=("EDITOR=${EDITORS}/${ed}")
  RC=0
  env -i "${HERMETIC_ENV[@]}" "${FIX}/tools/zsh" "${ORIG_CONFIG_DIR}/bin/dotfiles" "$@" \
    < /dev/null > "${FIX}/nm.out" 2> "${FIX}/nm.err" || RC=$?
  OUT="$(cat "${FIX}/nm.out")"
  ERR="$(cat "${FIX}/nm.err")"
}
df_count() { df_git rev-list --count HEAD; }

# ── usage, and git's own --edit ──
run noop git --edit
assert_eq "shared tier --edit: usage" 64 "${RC}"
assert_contains "shared tier --edit: names the local form" "${ERR}" "fix='dotfiles --local git --edit'"
run noop --local git --edit --frob
assert_eq "an unknown argument: usage" 64 "${RC}"
run noop --local git --edit --help
assert_eq "--edit --help: exit 0" 0 "${RC}"
assert_contains "--edit --help: the git help" "${OUT}" "--local git --edit [--no-commit]"
df_before="$(df_count)"
run git_msg git commit --allow-empty -m "via git" --edit
assert_eq "git commit --edit reaches git: exit 0" 0 "${RC}"
assert_eq "git commit --edit reaches git: git ran the editor" "via git (edited by git)" "$(df_git log -1 --format=%s)"
assert_eq "git commit --edit reaches git: one commit" "$(( df_before + 1 ))" "$(df_count)"
run noop --local git status --short
assert_eq "--local git status: exit 0" 0 "${RC}"

# ── unchanged ──
template_before="$(cat "${TEMPLATE}")"
run noop --local git --edit
assert_eq "unchanged: exit 0" 0 "${RC}"
assert_contains "unchanged: says so" "${OUT}" "allowlist: no change"
assert_no_file "unchanged: no draft" "${DRAFT}"

# ── this machine's allowlist changed by hand: refused, with the diff ──
cp "${EXCLUDE}" "${FIX}/exclude.orig"
printf '!/share/extra/\n' >> "${EXCLUDE}"
run add_zz --local git --edit
assert_eq "hand-changed: exit 1" 1 "${RC}"
assert_contains "hand-changed: the diff" "${OUT}" "-!/share/extra/"
assert_contains "hand-changed: says nothing changed" "${ERR}" "this machine's allowlist has rules the template does not; nothing changed"
assert_eq "hand-changed: the template is untouched" "${template_before}" "$(cat "${TEMPLATE}")"
assert_no_file "hand-changed: no draft" "${DRAFT}"
# A copy that differs only in comments is no hand change.
{ printf '# a comment only this machine has\n'; cat "${FIX}/exclude.orig"; } > "${EXCLUDE}"
run noop --local git --edit
assert_eq "comments only: not refused" 0 "${RC}"
cp "${FIX}/exclude.orig" "${EXCLUDE}"

# ── each bad draft: kept, nothing installed or committed ──
df_before="$(df_count)"
check_kept() {  # NAME EXPECTED-ERR
  assert_eq "$1: exit 1" 1 "${RC}"
  assert_contains "$1: named" "${ERR}" "$2"
  assert_contains "$1: the resume" "${ERR}" "fix='dotfiles --local git --edit'"
  assert_eq "$1: the template is untouched" "${template_before}" "$(cat "${TEMPLATE}")"
  assert_eq "$1: info/exclude is untouched" "$(cat "${FIX}/exclude.orig")" "$(cat "${EXCLUDE}")"
  assert_file "$1: the draft is kept" "${DRAFT}"
  assert_eq "$1: nothing committed" "${df_before}" "$(df_count)"
  rm -f "${DRAFT}"
}
run add_zz_bare --local git --edit
check_kept "an entry without a why" "undocumented: '!/share/zz/' has no '# why' comment on the line above it"
run no_star --local git --edit
check_kept "no leading /*" "not '/*': an allowlist starts by excluding everything"
run no_secrets --local git --edit
check_kept "secrets admitted" "x.secret.zsh' would be tracked"
run trailing_space --local git --edit
check_kept "trailing whitespace" "'!/share/kuber/  ' ends in whitespace"
run broken --local git --edit
assert_eq "a failing editor: exit 1" 1 "${RC}"
assert_contains "a failing editor: says so" "${ERR}" "editor exited non-zero; draft kept"
rm -f "${DRAFT}"

# A dry run checks the draft and keeps it; nothing is put in place.
run add_zz --dry-run --local git --edit
assert_eq "dry run: exit 0" 0 "${RC}"
assert_contains "dry run: says what it would do" "${OUT}" "would put the draft in place, install it and commit it; draft kept"
assert_eq "dry run: the template is untouched" "${template_before}" "$(cat "${TEMPLATE}")"
assert_file "dry run: the draft is kept" "${DRAFT}"

# Resumed and good: in place, installed, the new admission visible, committed in the shared tier.
mkdir -p "${HOME}/.local/share/zz"
printf 'hello\n' > "${HOME}/.local/share/zz/notes.txt"
printf 'export X=1\n' > "${HOME}/.local/share/zz/zz.secret.zsh"
run noop --local git --edit
assert_eq "a good edit: exit 0" 0 "${RC}"
assert_contains "a good edit: resumed the draft" "${ERR}" "resuming the draft a failed edit left"
assert_contains "a good edit: in the template" "$(cat "${TEMPLATE}")" $'# A directory the test admits.\n!/share/zz/'
assert_eq "a good edit: installed" "$(cat "${TEMPLATE}")" "$(cat "${EXCLUDE}")"
assert_contains "a good edit: status shows what it admits" "${OUT}" "?? share/zz/notes.txt"
rc=0; ldf_git check-ignore -q share/zz/zz.secret.zsh || rc=$?
assert_eq "a good edit: the secret beside it stays out" 0 "${rc}"
assert_eq "a good edit: one df commit" "$(( df_before + 1 ))" "$(df_count)"
assert_eq "a good edit: the subject" "dotfiles: edit the local tier's allowlist" "$(df_git log -1 --format=%s)"
assert_eq "a good edit: the template is what was committed" "" "$(df_git status --porcelain -- "${TEMPLATE}")"
assert_contains "a good edit: next" "${OUT}" "next: dotfiles --local git add -A"
assert_no_file "a good edit: no draft left" "${DRAFT}"
bump_now_secs 60
nm check --only local_dotfiles_repo --json; out_json > /dev/null
assert_eq "the step after the edit: ok" ok "$(step_get local_dotfiles_repo .status)"

# --no-commit: installed, the template left uncommitted.
df_before="$(df_count)"
editor drop_zz '$0 != "# A directory the test admits." && $0 != "!/share/zz/" { print }'
run drop_zz --local git --edit --no-commit
assert_eq "--no-commit: exit 0" 0 "${RC}"
assert_contains "--no-commit: says so" "${OUT}" "not committed | file="
assert_eq "--no-commit: nothing committed" "${df_before}" "$(df_count)"
assert_not_contains "--no-commit: installed" "$(cat "${EXCLUDE}")" "!/share/zz/"

# No local tier: nothing to install into.
mv "${ARI_DOTFILES_LDF_GIT_DIR}" "${FIX}/ldf.away"
run add_zz --local git --edit
assert_eq "no local tier: exit 1" 1 "${RC}"
assert_contains "no local tier: the fix" "${ERR}" "fix='dotfiles apply local_dotfiles_repo'"
mv "${FIX}/ldf.away" "${ARI_DOTFILES_LDF_GIT_DIR}"

report
