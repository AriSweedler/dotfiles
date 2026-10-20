#!/usr/bin/env bash
# `steps edit`: a step file edited as a draft in $EDITOR, checked (zsh -n, the registry loading
# with the draft in place, its watches, the documentation rule), then put in place and committed
# in the shared tier; a draft that fails is kept for the next edit and the live file never changes.
set -u
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

world_new
# The program as real files under HOME, so an edit lands in the world's shared tier and never in
# the checkout under test (the world's lib/, cmd/ and steps/ are symlinks to it).
CODE="${HOME}/.config"
rm -f "${CODE}/dotfiles/lib" "${CODE}/dotfiles/cmd" "${CODE}/dotfiles/steps" "${CODE}/bin/dotfiles"
cp -R "${ORIG_CONFIG_DIR}/dotfiles/lib" "${ORIG_CONFIG_DIR}/dotfiles/cmd" "${ORIG_CONFIG_DIR}/dotfiles/steps" "${CODE}/dotfiles/"
cp "${ORIG_CONFIG_DIR}/bin/dotfiles" "${CODE}/bin/dotfiles"
STEPS="${CODE}/dotfiles/steps"
DRAFTS="${ARI_DOTFILES_STATE_DIR}/drafts"
# draft NAME: where edit::draft keeps NAME's draft: the live file's path under HOME, / as %.
draft() { printf '%s/.config%%dotfiles%%steps%%%s.zsh' "${DRAFTS}" "$1"; }
cat > "${STEPS}/zz_demo.zsh" <<'EOF'
# step zz_demo — a step the test owns.
step::declare zz_demo --group tools --desc "the demo file exists" \
  --apply "creates the demo file"
step::watches zz_demo '.config/zz-demo/**'

check::zz_demo() { verdict ok present; }
apply::zz_demo() { run_mut true; }
EOF
seed_fake_repos

EDITORS="${FIX}/editors"
mkdir -p "${EDITORS}"
# editor NAME AWK: rewrites the file it is given with AWK.
editor() { printf '#!/bin/sh\nawk %s "$1" > "$1.tmp" && mv "$1.tmp" "$1"\n' "'$2'" > "${EDITORS}/$1"; chmod +x "${EDITORS}/$1"; }
editor noop '{ print }'
# The template, documented: summary, --desc, --apply, the --none reason.
editor describe '/^# step [a-z_]* —$/ { print $0 " says hello"; next }
  /--desc ""/ { sub(/--desc ""/, "--desc \"a greeting\"") } /--apply ""/ { sub(/--apply ""/, "--apply \"prints hello\"") }
  /--none ""/ { sub(/--none ""/, "--none \"reads nothing\"") } { print }'
editor header_only '/^# step [a-z_]* —$/ { print $0 " says hello"; next } { print }'
# The template as a check-only step: no --apply line, no apply function.
editor check_only '/^# step [a-z_]* —$/ { print $0 " only checks"; next } /^# A check-only/ { skip = 1 } skip { next }
  /--desc "" \\/ { print "  --desc \"only a check\""; next } /--apply ""/ { next }
  /--none ""/ { sub(/--none ""/, "--none \"reads nothing\"") } { print }'
editor drop_apply_doc '/^  --apply / { next } /--desc .* \\$/ { sub(/ \\$/, "") } { print }'
editor bad_syntax 'END { print "check::zz_demo() {" } { print }'
editor other_name '{ sub(/^step::declare zz_demo /, "step::declare zz_other ") } { print }'
editor gut 'NR == 1 { print } { next }'
editor noisy 'END { print "print -r -- loud" } { print }'
editor bad_flag '{ sub(/--group tools/, "--group tools --colour red") } { print }'
editor both_watches '/^step::watches/ { print; print "step::watches zz_demo --none \"reads nothing\""; next } { print }'
editor comment 'END { print "# a later note" } { print }'

# edit EDITOR ARGS...: `dotfiles steps ARGS` from the world's copy of the program, no terminal.
edit() {
  local ed="$1"; shift
  bump_now_secs 60
  hermetic_env
  HERMETIC_ENV+=("EDITOR=${EDITORS}/${ed}")
  RC=0
  env -i "${HERMETIC_ENV[@]}" "${FIX}/tools/zsh" "${CODE}/bin/dotfiles" steps "$@" \
    < /dev/null > "${FIX}/nm.out" 2> "${FIX}/nm.err" || RC=$?
  OUT="$(cat "${FIX}/nm.out")"
  ERR="$(cat "${FIX}/nm.err")"
}
df_count() { df_git rev-list --count HEAD; }
docs_of() { awk -v s="$1" '$1 == s { print $6 }' <<< "${OUT}"; }

# ── usage ──
edit noop edit
assert_eq "no NAME is a usage error" 64 "${RC}"
edit noop edit Bad-Name
assert_eq "not a step name: usage error" 64 "${RC}"
edit noop edit nobody
assert_eq "an unknown step: exit 1" 1 "${RC}"
assert_contains "an unknown step names --new" "${ERR}" "fix='dotfiles steps edit nobody --new'"
edit noop edit zz_demo --new
assert_eq "--new on an existing step: exit 1" 1 "${RC}"
edit noop edit zz_demo --frob
assert_eq "an unknown flag is a usage error" 64 "${RC}"
edit noop frob
assert_eq "an unknown subcommand is a usage error" 64 "${RC}"
edit noop list extra
assert_eq "list takes no arguments" 64 "${RC}"

# ── --new: the template alone is no change and creates nothing ──
edit noop edit hello --new
assert_eq "unchanged template: exit 0" 0 "${RC}"
assert_contains "unchanged template: says so" "${OUT}" "steps: no change; nothing created | step=hello"
assert_no_file "unchanged template: no step" "${STEPS}/hello.zsh"
assert_no_file "unchanged template: no draft" "$(draft hello)"

# ── --new, only the header documented: reported, kept, nothing created ──
df_before="$(df_count)"
edit header_only edit hello --new
assert_eq "half documented: exit 1" 1 "${RC}"
assert_contains "half documented: each gap" "${ERR}" \
  'undocumented: no --desc, no --apply "<what the apply changes>", step::watches --none without a reason'
assert_contains "half documented: the resume" "${ERR}" "fix='dotfiles steps edit hello --new'"
assert_no_file "half documented: no step" "${STEPS}/hello.zsh"
assert_file "half documented: the draft is kept" "$(draft hello)"
assert_eq "half documented: nothing committed" "${df_before}" "$(df_count)"

# Resumed from the draft and documented: in place, committed in the shared tier, never pushed.
edit describe edit hello --new
assert_eq "new step: exit 0" 0 "${RC}"
assert_contains "new step: resumed the draft" "${ERR}" "resuming the draft a failed edit left"
assert_contains "new step: its header" "$(head -n 1 "${STEPS}/hello.zsh")" "# step hello — says hello"
assert_eq "new step: one df commit" "$(( df_before + 1 ))" "$(df_count)"
assert_eq "new step: the subject" "dotfiles: add step hello (shared)" "$(df_git log -1 --format=%s)"
assert_contains "new step: the shared tier waits for dotfiles push" "${OUT}" 'Run `dotfiles push` when ready.'
assert_contains "new step: next, its check" "${OUT}" "next: dotfiles healthcheck --only hello"
assert_contains "new step: next, its apply" "${OUT}" "next: dotfiles apply hello"
assert_no_file "new step: no draft left" "$(draft hello)"
edit noop list
assert_eq "new step: listed" tools "$(awk '$1 == "hello" { print $2 }' <<< "${OUT}")"
assert_eq "new step: documented" ok "$(docs_of hello)"

# A check-only step: no apply, so no apply to suggest.
edit check_only edit lookout --new
assert_eq "check-only step: exit 0" 0 "${RC}"
assert_contains "check-only step: next, its check" "${OUT}" "next: dotfiles healthcheck --only lookout"
assert_not_contains "check-only step: no apply to suggest" "${OUT}" "next: dotfiles apply lookout"

# ── an existing step: each problem kept as a draft, the live file and the tier untouched ──
live_before="$(cat "${STEPS}/zz_demo.zsh")"
df_before="$(df_count)"
check_kept() {  # NAME EXPECTED-ERR
  assert_eq "$1: exit 1" 1 "${RC}"
  assert_contains "$1: named" "${ERR}" "$2"
  assert_contains "$1: the resume" "${ERR}" "fix='dotfiles steps edit zz_demo'"
  assert_eq "$1: the live file is untouched" "${live_before}" "$(cat "${STEPS}/zz_demo.zsh")"
  assert_file "$1: the draft is kept" "$(draft zz_demo)"
  assert_eq "$1: nothing committed" "${df_before}" "$(df_count)"
  rm -f "$(draft zz_demo)"
}
edit drop_apply_doc edit zz_demo
check_kept "an apply without --apply" 'undocumented: no --apply "<what the apply changes>"'
edit bad_syntax edit zz_demo
check_kept "a syntax error" "syntax: "
edit other_name edit zz_demo
check_kept "declares another name" "step declared in another file | step='zz_other' file='zz_demo.zsh'"
edit gut edit zz_demo
check_kept "declares nothing" "declares no step zz_demo; want step::declare zz_demo"
edit noisy edit zz_demo
check_kept "prints when sourced" "loud"
edit bad_flag edit zz_demo
check_kept "a bad step::declare flag" "step::declare: bad flag | step='zz_demo' flag='--colour'"
edit both_watches edit zz_demo
check_kept "globs and --none" "undocumented: step::watches has both globs and --none"

# Fixed after a failure: resumed, saved, committed.
edit drop_apply_doc edit zz_demo
edit noop edit zz_demo
assert_eq "an unchanged resumed draft is still checked" 1 "${RC}"
cp "${STEPS}/zz_demo.zsh" "$(draft zz_demo)"
printf '# a resumed note\n' >> "$(draft zz_demo)"
edit noop edit zz_demo
assert_eq "resumed and good: exit 0" 0 "${RC}"
assert_contains "resumed and good: in place" "$(cat "${STEPS}/zz_demo.zsh")" "# a resumed note"
assert_eq "resumed and good: the subject" "dotfiles: edit step zz_demo (shared)" "$(df_git log -1 --format=%s)"

# ── unchanged; --no-commit; the --edit spelling; an editor that fails ──
edit noop edit zz_demo
assert_eq "unchanged: exit 0" 0 "${RC}"
assert_contains "unchanged: says so" "${OUT}" "steps: no change | step=zz_demo"
df_before="$(df_count)"
edit comment --edit zz_demo --no-commit
assert_eq "--edit, --no-commit: exit 0" 0 "${RC}"
assert_contains "--no-commit: says so" "${OUT}" "not committed | file="
assert_eq "--no-commit: nothing committed" "${df_before}" "$(df_count)"
assert_contains "--no-commit: in place" "$(cat "${STEPS}/zz_demo.zsh")" "# a later note"
printf '#!/bin/sh\nexit 3\n' > "${EDITORS}/broken"; chmod +x "${EDITORS}/broken"
edit broken edit zz_demo
assert_eq "a failing editor: exit 1" 1 "${RC}"
assert_contains "a failing editor: says so" "${ERR}" "editor exited non-zero; zz_demo kept as it was saved"
rm -f "$(draft zz_demo)"

# The edited registry still loads for every verb.
edit noop list
assert_eq "steps after the edits: exit 0" 0 "${RC}"
assert_eq "steps after the edits: zz_demo documented" ok "$(docs_of zz_demo)"

report
