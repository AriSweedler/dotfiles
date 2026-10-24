#!/usr/bin/env bash
# `help --edit [VERB]`: a verb's file (or lib/dispatch.zsh) opened in $EDITOR at its help function
# as a draft, checked (zsh -n, the help rule, a render under set -euo pipefail in a fresh zsh -f),
# then put in place and committed in the shared tier; a draft that fails is kept and the live file
# never changes; a verb without a help gets a stub.
set -u
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

world_new
# The program as real files under HOME, so an edit lands in the world's shared tier and never in
# the checkout under test.
CODE="${HOME}/.config"
rm -f "${CODE}/dotfiles/lib" "${CODE}/dotfiles/cmd" "${CODE}/dotfiles/steps" "${CODE}/bin/dotfiles"
cp -R "${ORIG_CONFIG_DIR}/dotfiles/lib" "${ORIG_CONFIG_DIR}/dotfiles/cmd" "${ORIG_CONFIG_DIR}/dotfiles/steps" "${CODE}/dotfiles/"
cp "${ORIG_CONFIG_DIR}/bin/dotfiles" "${CODE}/bin/dotfiles"
CMD="${CODE}/dotfiles/cmd"
DISPATCH="${CODE}/dotfiles/lib/dispatch.zsh"
DRAFTS="${ARI_DOTFILES_STATE_DIR}/drafts/help"
# A draft is named for its live file (edit::draft): the path under $HOME, / as %.
draft_of() { printf '%s/%s' "${DRAFTS}" "${1//\//%}"; }
VERIFY_DRAFT="$(draft_of .config/dotfiles/cmd/verify.zsh)"
# A verb with no help: the stub's case.
cat > "${CMD}/zz.zsh" <<'EOF'
# dotfiles/cmd/zz.zsh — a verb the test owns.

cmd_zz() {
  case "${1:-}" in
    --frob) print -r -- frobbed ;;
    *) print -r -- zz ;;
  esac
}
EOF
seed_fake_repos

EDITORS="${FIX}/editors"
mkdir -p "${EDITORS}"
# editor NAME AWK: records the line argument (+N), then rewrites the file with AWK. It is named
# nvim (in a directory of its own) so it is given +N, as a real one is.
editor() {
  mkdir -p "${EDITORS}/$1"
  printf '#!/bin/sh\nprintf "%%s\\n" "$1" > "%s/opened-at"\nawk %s "$2" > "$2.tmp" && mv "$2.tmp" "$2"\n' \
    "${EDITORS}" "'$2'" > "${EDITORS}/$1/nvim"
  chmod +x "${EDITORS}/$1/nvim"
  chmod +x "${EDITORS}/$1"
}
editor noop '{ print }'
# verify is a declared verb (lib/verb.zsh): each editor breaks one part of the declaration rule.
editor no_description '/^verb::define verify / { print "verb::define verify \047\047"; next } { print }'
editor no_flag_desc '/^verb::flag verify .--show. / { print "verb::flag verify \047--show\047 \047\047"; next } { print }'
editor bad_syntax 'END { print "help_verify() {" } { print }'
editor unset_var '/^verb::about verify / { print; print "${NO_SUCH_VAR_IN_HELP}"; next } { print }'
editor hand_parsed '/^cmd_verify\(\) \{/ { print; print "  case \"${1:-}\" in"; print "    --shown) ;;"; print "  esac"; next } { print }'
editor reword '{ sub(/the weekly check: /, "the weekly check, edited: ") } { print }'
editor top_reword '{ sub(/the two-tier dotfiles, and/, "the two-tier dotfiles (edited), and") } { print }'
editor top_drop_dir '/^help\(\) \{/ { h = 1 } h { gsub(/--dir/, "--dirx") } /^}/ { h = 0 } { print }'
editor stub_para '{ sub(/in a paragraph\./, "frobs.") } { print }'
# Fills the declaration and moves cmd_zz onto verb::parse, as converting a verb does.
editor stub_fill '
  /^verb::define zz / { print "verb::define zz \047frob the zz\047"; next }
  /^verb::flag zz / { print "verb::flag zz \047--frob\047 \047print frobbed\047"; next }
  /^verb::edit zz --none/ { print "verb::edit zz --none \047zz has nothing to edit\047"; next }
  /^cmd_zz\(\) \{/ { print; print "  local -A opts; local -a args"; print "  verb::parse zz \"$@\""
                     print "  if (( ${+opts[--frob]} )); then print -r -- frobbed; else print -r -- zz; fi"; skip = 1; next }
  skip && /^}/ { skip = 0 }
  !skip { print }'
printf '#!/bin/sh\nexit 3\n' > "${EDITORS}/broken"; chmod +x "${EDITORS}/broken"

# edit EDITOR ARGS...: `dotfiles help ARGS` from the world's copy of the program, no terminal.
edit() {
  local ed="$1"; shift
  bump_now_secs 60
  hermetic_env
  HERMETIC_ENV+=("EDITOR=${EDITORS}/${ed}/nvim")
  RC=0
  env -i "${HERMETIC_ENV[@]}" "${FIX}/tools/zsh" "${CODE}/bin/dotfiles" help "$@" \
    < /dev/null > "${FIX}/nm.out" 2> "${FIX}/nm.err" || RC=$?
  OUT="$(cat "${FIX}/nm.out")"
  ERR="$(cat "${FIX}/nm.err")"
}
copy() { bump_now_secs 60; nm_run "${CODE}/bin/dotfiles" "$@"; }
df_count() { df_git rev-list --count HEAD; }
opened_at() { cat "${EDITORS}/opened-at"; }
line_of() { grep -n -m1 "^$1() {" "$2" | cut -d: -f1; }
line_starting() { grep -n -m1 -F -- "$1" "$2" | cut -d: -f1; }

# ── usage ──
edit noop --edit nosuchverb
assert_eq "an unknown verb is a usage error" 64 "${RC}"
edit noop --no-commit verify
assert_eq "--no-commit without --edit is a usage error" 64 "${RC}"
edit noop --edit --frob
assert_eq "an unknown flag is a usage error" 64 "${RC}"
edit noop --edit verify push
assert_eq "two verbs are a usage error" 64 "${RC}"
copy help --help
assert_contains "help --help lists --edit" "${OUT}" "--edit"

# ── unchanged: no change, at the help function's line ──
live_before="$(cat "${CMD}/verify.zsh")"
df_before="$(df_count)"
edit noop --edit verify
assert_eq "unchanged: exit 0" 0 "${RC}"
assert_contains "unchanged: says so" "${OUT}" "help verify: no change"
assert_eq "the editor opens at verify's declaration" "+$(line_starting 'verb::define verify ' "${CMD}/verify.zsh")" "$(opened_at)"
assert_no_file "unchanged: no draft" "${VERIFY_DRAFT}"
edit noop --edit VERIFY
assert_eq "the verb is case-insensitive" 0 "${RC}"

# ── each problem: kept as a draft, the live file and the tier untouched ──
check_kept() {  # NAME EXPECTED-ERR
  assert_eq "$1: exit 1" 1 "${RC}"
  assert_contains "$1: named" "${ERR}" "$2"
  assert_contains "$1: the resume" "${ERR}" "fix='dotfiles help --edit verify'"
  assert_eq "$1: the live file is untouched" "${live_before}" "$(cat "${CMD}/verify.zsh")"
  assert_file "$1: the draft is kept" "${VERIFY_DRAFT}"
  assert_eq "$1: nothing committed" "${df_before}" "$(df_count)"
  rm -f "${VERIFY_DRAFT}"
}
edit no_description --edit verify
check_kept "no description" "undocumented: no description (verb::define verify"
edit no_flag_desc --edit verify
check_kept "a flag without a description" "undocumented: '--show' has no description"
edit hand_parsed --edit verify
check_kept "a flag parsed outside verb::parse" "undocumented: parses flags outside verb::parse: --shown"
edit bad_syntax --edit verify
check_kept "a syntax error" "syntax: "
edit unset_var --edit verify
check_kept "a help that does not render under set -u" "NO_SUCH_VAR_IN_HELP"

# A failure, then a good edit resumes the draft: in place, committed, never pushed.
edit no_description --edit verify
edit noop --edit verify
assert_eq "an unchanged resumed draft is still checked" 1 "${RC}"
assert_contains "resuming: says so" "${ERR}" "resuming the draft a failed edit left"
rm -f "${VERIFY_DRAFT}"
edit reword --edit verify
assert_eq "a good edit: exit 0" 0 "${RC}"
assert_contains "a good edit: in place" "$(cat "${CMD}/verify.zsh")" "the weekly check, edited: "
assert_eq "a good edit: one df commit" "$(( df_before + 1 ))" "$(df_count)"
assert_eq "a good edit: the subject" "dotfiles: edit help for verify" "$(df_git log -1 --format=%s)"
assert_contains "a good edit: the shared tier waits for dotfiles push" "${OUT}" 'Run `dotfiles push` when ready.'
assert_contains "a good edit: next" "${OUT}" "next: dotfiles verify --help"
assert_no_file "a good edit: no draft left" "${VERIFY_DRAFT}"
copy verify --help
assert_contains "the edited help is live" "${OUT}" "the weekly check, edited: "

# --no-commit, and an editor that fails.
df_before="$(df_count)"
editor push_reword '/^verb::define push / { sub(/publish every tier: /, "publish each tier: ") } { print }'
edit push_reword --edit push --no-commit
assert_eq "--no-commit: exit 0" 0 "${RC}"
assert_contains "--no-commit: says so" "${OUT}" "not committed | file="
assert_eq "--no-commit: nothing committed" "${df_before}" "$(df_count)"
assert_contains "--no-commit: in place" "$(cat "${CMD}/push.zsh")" "publish each tier: "
edit broken --edit push
assert_eq "a failing editor: exit 1" 1 "${RC}"
assert_contains "a failing editor: says so" "${ERR}" "editor exited non-zero"
rm -f "$(draft_of .config/dotfiles/cmd/push.zsh)"

# ── no VERB: lib/dispatch.zsh at help() ──
edit noop --edit
assert_eq "top-level, unchanged: exit 0" 0 "${RC}"
assert_contains "top-level, unchanged: says so" "${OUT}" "help dotfiles: no change"
assert_eq "the editor opens at help()" "+$(line_of help "${DISPATCH}")" "$(opened_at)"
dispatch_before="$(cat "${DISPATCH}")"
edit top_drop_dir --edit
assert_eq "top-level without --dir: exit 1" 1 "${RC}"
assert_contains "top-level without --dir: named" "${ERR}" "undocumented: flags not in it: --dir"
assert_contains "top-level: the resume" "${ERR}" "fix='dotfiles help --edit'"
assert_eq "top-level: the live file is untouched" "${dispatch_before}" "$(cat "${DISPATCH}")"
rm -f "$(draft_of .config/dotfiles/lib/dispatch.zsh)"
edit top_reword --edit
assert_eq "top-level, a good edit: exit 0" 0 "${RC}"
assert_eq "top-level: the subject" "dotfiles: edit the top-level help" "$(df_git log -1 --format=%s)"
assert_contains "top-level: next" "${OUT}" "next: dotfiles --help"
copy --help
assert_contains "the edited top-level help is live" "${OUT}" "the two-tier dotfiles (edited), and"

# ── a verb without a help: a stub, above cmd_zz ──
zz_before="$(cat "${CMD}/zz.zsh")"
edit noop --edit zz
assert_eq "stub unchanged: exit 0" 0 "${RC}"
assert_contains "stub unchanged: says so" "${OUT}" "help zz: no change; no help written"
assert_eq "stub unchanged: the file is untouched" "${zz_before}" "$(cat "${CMD}/zz.zsh")"
edit stub_para --edit zz
assert_eq "a stub saved without a synopsis: exit 1" 1 "${RC}"
assert_contains "a stub saved without a description: named" "${ERR}" "undocumented: no description (verb::define zz"
assert_contains "the stub lists the verb's flags" "$(cat "$(draft_of .config/dotfiles/cmd/zz.zsh)")" "verb::flag zz '--frob' ''"
rm -f "$(draft_of .config/dotfiles/cmd/zz.zsh)"
edit stub_fill --edit zz
assert_eq "a stub with a synopsis: exit 0" 0 "${RC}"
assert_eq "the editor opened at the stub" "+$(line_starting 'verb::define zz' "${CMD}/zz.zsh")" "$(opened_at)"
assert_eq "the stub sits above cmd_zz" 1 "$(( $(line_starting 'verb::define zz' "${CMD}/zz.zsh") < $(line_of cmd_zz "${CMD}/zz.zsh") ))"
copy zz --help
assert_eq "the new help: line 1" "frob the zz" "$(head -n 1 <<< "${OUT}")"
copy help
assert_contains "the verb table shows its synopsis" "${OUT}" "frob the zz"
copy zz --frob
assert_eq "the verb still runs" frobbed "${OUT}"

report
