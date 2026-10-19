#!/usr/bin/env bash
# `brew edit`: opens a tier file in $EDITOR, checks it parses, commits it with a subject naming
# what changed; a file that does not parse is left as edited, uncommitted.
set -u
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

world_new
world_use_fixture drift
seed_fake_repos
seed_ldf_remote
LOCAL="${ARI_DOTFILES_LOCAL_DIR}/Brewfile"
GLOBAL_IGNORE="${ARI_DOTFILES_SHARED_DIR}/Brewfile.ignore"
LOCAL_IGNORE="${ARI_DOTFILES_LOCAL_DIR}/Brewfile.ignore"

# Editors are scripts that change the file the way a person would; each one is an EDITOR value.
EDITORS="${FIX}/editors"
mkdir -p "${EDITORS}"
editor() { local name="$1"; shift; printf '#!/bin/sh\n%s\n' "$*" > "${EDITORS}/${name}"; chmod +x "${EDITORS}/${name}"; }
editor noop ':'
editor fails 'exit 3'
editor add_jq 'printf "brew \"jq\"\n" >> "$1"'
editor add_broken 'printf "brew \"oops\n" >> "$1"'
editor drop_last 'awk "NR > 1 { print prev } { prev = \$0 }" "$1" > "$1.tmp" && mv "$1.tmp" "$1"'
editor add_comment 'printf "# tidy later\n" >> "$1"'
editor add_four 'printf "brew \"a\"\nbrew \"b\"\ncask \"c\"\ntap \"d/e\"\n" >> "$1"'
editor ignore_libtiff 'printf "formula libtiff  # pulled in by a cask\n" >> "$1"'
editor ignore_no_name 'printf "formula\n" >> "$1"'

# edit EDITOR ARGS...: `dotfiles brew edit ARGS` with that editor; captures OUT, ERR, RC.
edit() {
  local ed="$1"; shift
  bump_now_secs 60
  hermetic_env
  HERMETIC_ENV+=("EDITOR=${EDITORS}/${ed}")
  RC=0
  env -i "${HERMETIC_ENV[@]}" "${FIX}/tools/zsh" "${ORIG_CONFIG_DIR}/bin/dotfiles" brew edit "$@" \
    > "${FIX}/nm.out" 2> "${FIX}/nm.err" || RC=$?
  OUT="$(cat "${FIX}/nm.out")"
  ERR="$(cat "${FIX}/nm.err")"
}
ldf_subject() { ldf_git log -1 --format=%s 2>/dev/null; }
df_subject() { df_git log -1 --format=%s; }
ldf_head() { ldf_git rev-parse -q --verify HEAD 2>/dev/null || true; }

# ── usage ──
nm brew edit --help
assert_eq "--help exits 0" 0 "${RC}"
assert_contains "--help: the synopsis" "${OUT}" "dotfiles brew edit [--global|--local] [--ignore] [--no-commit] [--no-push]"
nm brew --help
assert_contains "brew --help lists edit" "${OUT}" "brew edit [--global|--local] [--ignore]"
edit noop --global --local
assert_eq "--global with --local is a usage error" 64 "${RC}"
edit noop --bogus
assert_eq "an unknown flag is a usage error" 64 "${RC}"

# ── no change: a missing local Brewfile is not left behind ──
assert_no_file "the drift world starts without a local Brewfile" "${LOCAL}"
edit noop
assert_eq "no change exits 0" 0 "${RC}"
assert_contains "no change says so" "${OUT}" "brew: no change | tier=local"
assert_no_file "an unchanged new file is removed again" "${LOCAL}"

# ── the editor fails ──
edit fails
assert_eq "a failing editor exits 1" 1 "${RC}"
assert_contains "a failing editor is named" "${ERR}" "editor exited non-zero"

# ── a line added: created with the header, committed, pushed, next step named ──
edit add_jq
assert_eq "add exits 0" 0 "${RC}"
assert_contains "the header seeds a new local Brewfile" "$(cat "${LOCAL}")" "# Packages for THIS machine only"
assert_contains "the line is there" "$(cat "${LOCAL}")" 'brew "jq"'
assert_eq "commit subject names the item" "dotfiles: edit Brewfile (local): +formula:jq" "$(ldf_subject)"
assert_eq "pushed" "$(ldf_head)" "$(git --git-dir="${FIX}/remotes/local-dotfiles.git" rev-parse main)"
assert_contains "the summary line" "${OUT}" "+ formula:jq"
assert_contains "an added Brewfile line names the install step" "${OUT}" "next: dotfiles apply brew_pkgs"
assert_eq "brew parsed the file once, with --all" 1 "$(grep -c "bundle list --all --file=${LOCAL}" "${BREW_SHIM_LOG_DIR}/brew.log")"

# ── a line that does not parse: left as edited, nothing committed ──
head_before="$(ldf_head)"
edit add_broken
assert_eq "a broken Brewfile exits 1" 1 "${RC}"
assert_contains "it says the file does not parse" "${ERR}" "Brewfile does not parse; left as edited, not committed"
assert_contains "brew's own complaint is shown" "${ERR}" "Invalid Brewfile"
assert_contains "the fix reopens the same file" "${ERR}" "fix='dotfiles brew edit --local'"
assert_contains "the broken line is kept" "$(cat "${LOCAL}")" 'brew "oops'
assert_eq "nothing committed" "${head_before}" "$(ldf_head)"

# ── fixed back to the committed file: nothing to commit ──
edit drop_last
assert_eq "restoring the committed file exits 0" 0 "${RC}"
assert_contains "it says nothing to commit" "${OUT}" "matches the committed file; nothing to commit"
assert_eq "still nothing committed" "${head_before}" "$(ldf_head)"

# ── a comment, --no-commit ──
edit add_comment --no-commit
assert_eq "--no-commit exits 0" 0 "${RC}"
assert_contains "--no-commit says so" "${OUT}" "not committed | file="
assert_eq "--no-commit commits nothing" "${head_before}" "$(ldf_head)"
assert_not_contains "a comment is no item change, so no next step" "${OUT}" "next:"
# Committed by the next edit; with no item change the subject says so.
edit drop_last
edit add_comment
assert_eq "comment only exits 0" 0 "${RC}"
assert_eq "comment-only subject" "dotfiles: edit Brewfile (local): comments or order only" "$(ldf_subject)"

# ── more than three changes: a count, then one body line each ──
edit add_four --no-push
assert_eq "four items exit 0" 0 "${RC}"
assert_eq "four items: a count in the subject" "dotfiles: edit Brewfile (local): 4 items" "$(ldf_subject)"
assert_contains "four items: a body line each" "$(ldf_git log -1 --format=%b)" "- + cask:c"
assert_not_contains "--no-push left the remote behind" "$(git --git-dir="${FIX}/remotes/local-dotfiles.git" rev-parse main)" "$(ldf_head)"

# ── a removal names triage ──
edit drop_last --no-push
assert_eq "removal subject" "dotfiles: edit Brewfile (local): -tap:d/e" "$(ldf_subject)"
assert_contains "a removed line names triage" "${OUT}" "next: dotfiles brew triage"

# ── the shared ignore file: committed in df, never pushed ──
df_before="$(df_git rev-parse HEAD)"
edit ignore_libtiff --global --ignore
assert_eq "global ignore exits 0" 0 "${RC}"
assert_contains "the ignore line is there" "$(cat "${GLOBAL_IGNORE}")" "formula libtiff  # pulled in by a cask"
assert_eq "df commit subject" "dotfiles: edit Brewfile.ignore (global): +formula:libtiff" "$(df_subject)"
assert_eq "one df commit" "$(( $(df_git rev-list --count "${df_before}") + 1 ))" "$(df_git rev-list --count HEAD)"
assert_contains "the shared tier is left for dotfiles push" "${OUT}" 'Run `dotfiles push` when ready.'
assert_contains "an ignore change names triage" "${OUT}" "next: dotfiles brew triage"

# ── an ignore line without a name does not parse ──
edit ignore_no_name --ignore
assert_eq "a bad ignore line exits 1" 1 "${RC}"
assert_contains "the parser's warning is shown" "${ERR}" "ignore entry without a name"
assert_contains "the fix reopens the ignore file" "${ERR}" "fix='dotfiles brew edit --local --ignore'"
assert_contains "the bad line is kept" "$(cat "${LOCAL_IGNORE}")" "formula"

assert_no_mutation "brew edit never calls a mutating brew command"
report
