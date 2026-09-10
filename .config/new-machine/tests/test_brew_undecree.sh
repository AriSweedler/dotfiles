#!/usr/bin/env bash
# `brew undecree`: removes exactly the decreed line(s), drops a tap when its last user goes,
# leaves hand-placed lines alone.
set -u
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

world_new
world_use_fixture drift
seed_fake_repos
seed_ldf_remote
LOCAL="${NEW_MACHINE_LOCAL_DIR}/Brewfile"
MARKER="# ── decreed via 'new-machine brew decree'; move into a section when tidying ──"

decree() { bump_now_secs 60; nm brew decree "$@"; assert_eq "decree $* exits 0" 0 "${RC}"; }
undecree() { bump_now_secs 60; nm brew undecree "$@"; }
ldf_subject() { ldf_git log -1 --format=%s; }

decree gh --local
decree bk@3 --local
commits_before="$(ldf_git rev-list --count HEAD)"

undecree gh
assert_eq "undecree gh exits 0" 0 "${RC}"
assert_not_contains "brew \"gh\" removed" "$(cat "${LOCAL}")" 'brew "gh"'
assert_contains "bk@3 kept" "$(cat "${LOCAL}")" 'brew "buildkite/buildkite/bk@3"'
assert_contains "tap kept while bk@3 uses it" "$(cat "${LOCAL}")" 'tap "buildkite/buildkite", trusted: true'
assert_eq "undecree commit subject" "new-machine: undeclare formula gh (local)" "$(ldf_subject)"
assert_eq "exactly one commit" "$((commits_before + 1))" "$(ldf_git rev-list --count HEAD)"
assert_eq "pushed" "$(ldf_git rev-parse HEAD)" "$(git --git-dir="${FIX}/remotes/local-dotfiles.git" rev-parse main)"

undecree bk@3
assert_eq "undecree bk@3 exits 0" 0 "${RC}"
assert_not_contains "bk@3 removed" "$(cat "${LOCAL}")" 'buildkite/buildkite/bk@3'
assert_not_contains "tap removed with its last user" "$(cat "${LOCAL}")" 'tap "buildkite/buildkite"'
assert_eq "undecree bk@3 commit subject" "new-machine: undeclare formula buildkite/buildkite/bk@3 (local)" "$(ldf_subject)"

# A line Ari placed by hand, above the marker, is not decree's to remove.
{ printf '%s\n' '# hand-placed section' 'brew "python@3.10"' ''; cat "${LOCAL}"; } > "${LOCAL}.tmp"
mv "${LOCAL}.tmp" "${LOCAL}"
ldf_git add -- "${LOCAL}"
ldf_git commit -q -m "hand-place python@3.10"
head_before="$(ldf_git rev-parse HEAD)"
undecree python@3.10
assert_contains "hand-placed line is left in place" "$(cat "${LOCAL}")" 'brew "python@3.10"'
assert_contains "hand-placed line is reported" "${OUT}${ERR}" "python@3.10"
assert_eq "nothing committed for a hand-placed line" "${head_before}" "$(ldf_git rev-parse HEAD)"
assert_contains "marker still present" "$(cat "${LOCAL}")" "${MARKER}"
assert_no_mutation "undecree never calls a mutating brew command"

report
