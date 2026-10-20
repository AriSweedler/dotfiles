#!/usr/bin/env bash
# `brew triage --edit`: the undeclared items as a plan file in $EDITOR, one `skip  kind:name` line
# each; on save every line is checked, then the plan runs as --interactive's does (one decree, one
# commit, per group). Editors are scripts that change the file the way a person would.
set -u
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

world_new
world_use_fixture drift
seed_fake_repos
seed_ldf_remote

EDITORS="${FIX}/editors"
mkdir -p "${EDITORS}"
# editor NAME AWK: an editor that keeps a copy of the file it was given, then rewrites it with AWK.
editor() {
  printf '#!/bin/sh\ncp "$1" "%s/plan.given"\nawk %s "$1" > "$1.tmp" && mv "$1.tmp" "$1"\n' "${FIX}" "'$2'" > "${EDITORS}/$1"
  chmod +x "${EDITORS}/$1"
}
editor noop '{ print }'
editor comment '{ print } END { print "# just looking" }'
editor choose '
  $0 == "skip  formula:gh"                     { print "local add  formula:gh"; next }
  $0 == "skip  cask:instant-space-switcher"    { print "local add  cask:instant-space-switcher"; next }
  $0 == "skip  formula:libtiff"                { print "global add  formula:libtiff"; next }
  $0 == "skip  formula:python@3.10"            { print "local ignore  formula:python@3.10  # pulled in by a cask"; next }
  $0 == "skip  cask:google-chrome"             { print "local ignore cask:google-chrome # pulled in by a cask"; next }
  $0 == "skip  formula:buildkite/buildkite/bk@3" { print "global ignore  formula:buildkite/buildkite/bk@3  # company Brewfile owns it"; next }
  { print }'
editor bad '
  $0 == "skip  formula:gh"      { print "local nope  formula:gh"; next }
  $0 == "skip  formula:libtiff" { print "local ignore  formula:libtiff"; next }
  $0 == "skip  cask:google-chrome" { print "local add  cask:google-chrome  extra"; next }
  { print }
  END { print "skip  formula:nothere"; print "skip  tap:hashicorp/tap" }'
editor fix_bad '
  $0 == "local nope  formula:gh"           { print "skip  formula:gh"; next }
  $0 == "local ignore  formula:libtiff"     { print "skip  formula:libtiff"; next }
  /^local add  cask:google-chrome/          { print "skip  cask:google-chrome"; next }
  $0 == "skip  formula:nothere"             { next }
  { print }'

# triage_edit EDITOR ARGS...: `dotfiles brew triage --edit ARGS` with that editor, no terminal.
triage_edit() {
  local ed="$1"; shift
  bump_now_secs 60
  hermetic_env
  HERMETIC_ENV+=("EDITOR=${EDITORS}/${ed}")
  RC=0
  env -i "${HERMETIC_ENV[@]}" "${FIX}/tools/zsh" "${ORIG_CONFIG_DIR}/bin/dotfiles" brew triage --edit "$@" \
    < /dev/null > "${FIX}/nm.out" 2> "${FIX}/nm.err" || RC=$?
  OUT="$(cat "${FIX}/nm.out")"
  ERR="$(cat "${FIX}/nm.err")"
}
df_count() { df_git rev-list --count HEAD; }
ldf_count() { ldf_git rev-list --count HEAD 2>/dev/null || echo 0; }

# ── the file ──
triage_edit noop
assert_eq "unchanged: exit 0" 0 "${RC}"
assert_contains "unchanged: nothing to decree" "${OUT}" "no change; nothing to decree"
GIVEN="$(cat "${FIX}/plan.given")"
assert_contains "the header names each action" "${GIVEN}" "#   global add      declare it in the shared Brewfile"
assert_contains "the header names local ignore and its reason" "${GIVEN}" "#   local ignore    record it in the local Brewfile.ignore; needs a '# reason'"
assert_contains "one skip line per undeclared item" "${GIVEN}" $'\n'"skip  formula:gh"$'\n'
assert_contains "each kind is listed" "${GIVEN}" $'\n'"skip  vscode:ms-python.python"
assert_contains "the item's tap on a comment line above it" "${GIVEN}" "# formula gh (homebrew/core, new)"$'\n'"skip  formula:gh"
assert_eq "twelve undeclared items, twelve skip lines" 12 "$(grep -c '^skip  ' "${FIX}/plan.given")"
assert_contains "the rest of triage, as comments" "${GIVEN}" "# orphaned kegs"
assert_contains "a tap has no tap to name" "${GIVEN}" "# tap hashicorp/tap (new)"$'\n'
assert_eq "every reference line is a comment" 0 "$(awk '/for reference/ { r = 1; next } r && !/^#/' "${FIX}/plan.given" | wc -l | tr -d ' ')"

# ── all skip ──
triage_edit comment
assert_eq "all skip: exit 0" 0 "${RC}"
assert_contains "all skip: says so" "${OUT}" "every item skipped; nothing to decree"

# ── bad lines: each named by number, the file kept, the resume command given ──
df_before="$(df_count)" ldf_before="$(ldf_count)"
triage_edit bad
assert_eq "bad lines: exit 1" 1 "${RC}"
line_of() { grep -n -F -x -- "$1" "${PLAN}" | cut -d: -f1; }
PLAN="$(printf '%s' "${ERR}" | awk -F"--edit " '/fix=/ { sub(/\x27.*/, "", $2); print $2 }')"
assert_file "the plan file is kept" "${PLAN}"
assert_contains "an unknown action, by line" "${ERR}" "line $(line_of 'local nope  formula:gh'): unknown action; use global add, local add, global ignore, local ignore or skip"
assert_contains "an ignore without a reason, by line" "${ERR}" "line $(line_of 'local ignore  formula:libtiff'): an ignore needs a reason"
assert_contains "a stray word, by line" "${ERR}" "line $(line_of 'local add  cask:google-chrome  extra'): expected one kind:name"
assert_contains "an item that is not undeclared" "${ERR}" "not an undeclared item here | item='formula:nothere'"
assert_contains "an item twice" "${ERR}" "listed twice | item='tap:hashicorp/tap'"
assert_contains "the resume command" "${ERR}" "fix='dotfiles brew triage --edit ${PLAN}'"
assert_eq "bad lines: no df commit" "${df_before}" "$(df_count)"
assert_eq "bad lines: no ldf commit" "${ldf_before}" "$(ldf_count)"

# Resumed and fixed: the remaining duplicate line is still bad, so it is reported again.
triage_edit fix_bad "${PLAN}"
assert_eq "resume, still a duplicate: exit 1" 1 "${RC}"
assert_contains "resume reads the given file" "${ERR}" "listed twice | item='tap:hashicorp/tap'"
assert_not_contains "resume: the fixed lines are fine" "${ERR}" "unknown action"

# ── dry run: the plan, no commit ──
triage_edit choose --dry-run --no-push
assert_eq "dry run: exit 0" 0 "${RC}"
assert_contains "dry run: the plan's title" "${OUT}" "plan: 4 decree(s), one commit each (dry run)"
assert_contains "dry run: global add" "${OUT}" "dotfiles brew decree formula:libtiff --global --dry-run --no-push"
assert_contains "dry run: local add, two items in one decree" "${OUT}" "dotfiles brew decree formula:gh cask:instant-space-switcher --local --dry-run --no-push"
assert_contains "dry run: global ignore, with its reason" "${OUT}" "--ignore-global --reason 'company Brewfile owns it'"
assert_contains "dry run: local ignore, one group for one reason" "${OUT}" "formula:python@3.10 cask:google-chrome --ignore-local --reason 'pulled in by a cask'"
assert_eq "dry run: no df commit" "${df_before}" "$(df_count)"
assert_eq "dry run: no ldf commit" "${ldf_before}" "$(ldf_count)"

# ── a real run: one commit per group ──
triage_edit choose
assert_eq "real run: exit 0" 0 "${RC}"
assert_eq "real run: two df commits (global add, global ignore)" "$(( df_before + 2 ))" "$(df_count)"
assert_eq "real run: two ldf commits (local add, local ignore)" "$(( ldf_before + 2 ))" "$(ldf_count)"
assert_contains "real run: the df subjects" "$(df_git log -2 --format=%s)" "dotfiles: declare formula libtiff (global)"
assert_contains "real run: the global ignore" "$(df_git log -2 --format=%s)" "dotfiles: ignore formula buildkite/buildkite/bk@3 (global): company Brewfile owns it"
assert_contains "real run: the ldf subjects" "$(ldf_git log -2 --format=%s)" "dotfiles: declare 2 items (local)"
assert_contains "real run: the local ignore" "$(ldf_git log -2 --format=%s)" "dotfiles: ignore 2 items (local): pulled in by a cask"
assert_eq "real run: pushed" "$(ldf_git rev-parse HEAD)" "$(git --git-dir="${FIX}/remotes/local-dotfiles.git" rev-parse main)"

# ── usage ──
bump_now_secs 60
nm brew triage --edit --json < /dev/null
assert_eq "--edit with --json is a usage error" 64 "${RC}"
nm brew triage --edit --interactive < /dev/null
assert_eq "--edit with --interactive is a usage error" 64 "${RC}"
triage_edit noop "${FIX}/no-such-plan.txt"
assert_eq "a missing FILE is a usage error" 64 "${RC}"

assert_no_mutation "triage --edit never calls a mutating brew command"
report
