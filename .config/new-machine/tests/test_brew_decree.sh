#!/usr/bin/env bash
# `brew decree` against real bare repos: tier files, decree block, commits, push rules,
# refusals (declared, orphan, ambiguous, twice, unrelated staged changes), dry-run, sorting.
set -u
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

world_new
world_use_fixture drift
seed_df_remote
seed_fake_repos
seed_ldf_remote
df_git remote add origin "${FIX}/remotes/dotfiles.git"

LOCAL="${NEW_MACHINE_LOCAL_DIR}/Brewfile"
LOCAL_IGNORE="${NEW_MACHINE_LOCAL_DIR}/Brewfile.ignore"
GLOBAL="${HOME}/.config/new-machine/Brewfile"
GLOBAL_IGNORE="${HOME}/.config/new-machine/Brewfile.ignore"
MARKER="# ── decreed via 'new-machine brew decree'; move into a section when tidying ──"
LDF_REMOTE="${FIX}/remotes/local-dotfiles.git"

decree() { bump_now_secs 60; nm brew decree "$@"; }
ldf_head() { ldf_git rev-parse HEAD 2>/dev/null || printf 'unborn'; }
df_head() { df_git rev-parse HEAD; }
ldf_subject() { ldf_git log -1 --format=%s; }
df_subject() { df_git log -1 --format=%s; }
ldf_origin_main() { git --git-dir="${LDF_REMOTE}" rev-parse main 2>/dev/null || printf 'none'; }
# Non-blank lines after the decree marker.
block_lines() {
  local file="$1" line seen=0
  while IFS= read -r line || [[ -n "${line}" ]]; do
    if (( seen )); then [[ -n "${line}" ]] && printf '%s\n' "${line}"; continue; fi
    [[ "${line}" == "${MARKER}" ]] && seen=1
  done < "${file}"
}
line_no() { grep -nF -- "$2" "$1" | head -n 1 | cut -d: -f1; }

# ── decree gh --local ─────────────────────────────────────────────────────────
df_before="$(df_head)"
decree gh --local
assert_eq "decree gh --local exits 0" 0 "${RC}"
assert_file "local Brewfile created" "${LOCAL}"
assert_contains "local Brewfile carries the header" "$(cat "${LOCAL}")" "Packages for THIS machine only"
assert_contains "local Brewfile carries the marker" "$(cat "${LOCAL}")" "${MARKER}"
assert_eq "brew \"gh\" sits under the marker" 'brew "gh"' "$(block_lines "${LOCAL}")"
assert_eq "ldf commit subject" "dotfiles: declare formula gh (local)" "$(ldf_subject)"
assert_eq "ldf origin main advanced" "$(ldf_head)" "$(ldf_origin_main)"
assert_eq "df HEAD unchanged" "${df_before}" "$(df_head)"

# ── decree cask:google-chrome --global --reason browser ───────────────────────
df_remote_before="$(git ls-remote "${FIX}/remotes/dotfiles.git" | sort)"
decree cask:google-chrome --global --reason "browser"
assert_eq "decree cask --global exits 0" 0 "${RC}"
assert_contains "global Brewfile gained the cask with its reason" "$(cat "${GLOBAL}")" 'cask "google-chrome"  # browser'
assert_eq "df commit subject" "dotfiles: declare cask google-chrome (global)" "$(df_subject)"
assert_contains "global decree ends with the push reminder" "${OUT}${ERR}" 'Run `dotfiles push` when ready.'
assert_eq "df remote refs untouched" "${df_remote_before}" "$(git ls-remote "${FIX}/remotes/dotfiles.git" | sort)"

# ── refusals ──────────────────────────────────────────────────────────────────
ldf_before="$(ldf_head)"
decree kubectl --local
assert_eq "already declared → exit 1" 1 "${RC}"
assert_contains "names the tier it is declared in" "${OUT}${ERR}" "already declared in global"

decree spacectl --local
assert_eq "orphaned keg → exit 1" 1 "${RC}"
assert_contains "orphan refusal prints the reinstall recipe" "${OUT}${ERR}" "brew uninstall spacectl && brew tap spacelift-io/spacelift && brew install --cask spacelift-io/spacelift/spacectl"
assert_contains "orphan refusal prints the follow-up decree" "${OUT}${ERR}" "dotfiles brew decree cask:spacelift-io/spacelift/spacectl --local"
assert_eq "refusals commit nothing" "${ldf_before}" "$(ldf_head)"

# ── decree bk@3 --local adds the tap in the same commit ───────────────────────
commits_before="$(ldf_git rev-list --count HEAD)"
decree bk@3 --local
assert_eq "decree bk@3 --local exits 0" 0 "${RC}"
assert_contains "bk@3 declared under its full name" "$(cat "${LOCAL}")" 'brew "buildkite/buildkite/bk@3"'
assert_contains "tap added with trusted: true" "$(cat "${LOCAL}")" 'tap "buildkite/buildkite", trusted: true'
tap_line="$(line_no "${LOCAL}" 'tap "buildkite/buildkite", trusted: true')"
brew_line="$(line_no "${LOCAL}" 'brew "buildkite/buildkite/bk@3"')"
if (( tap_line < brew_line )); then pass "tap line precedes the formula"; else fail "tap line precedes the formula" "tap@${tap_line} brew@${brew_line}"; fi
assert_eq "one commit for tap + formula" "$((commits_before + 1))" "$(ldf_git rev-list --count HEAD)"
assert_contains "output says the tap was added" "${OUT}${ERR}" "buildkite/buildkite"

# ── decree hashicorp/tap/terraform --global when the dump omits it ────────────
grep -v '^brew "terraform"' "${GLOBAL}" > "${GLOBAL}.tmp"
mv "${GLOBAL}.tmp" "${GLOBAL}"
df_git add -- "${GLOBAL}"
df_git commit -q -m "drop the keg-name terraform line"
decree hashicorp/tap/terraform --global
assert_eq "decree terraform --global exits 0" 0 "${RC}"
assert_contains "synthesized formula line" "$(cat "${GLOBAL}")" 'brew "hashicorp/tap/terraform"'
assert_contains "tap line with trusted: true" "$(cat "${GLOBAL}")" 'tap "hashicorp/tap", trusted: true'
assert_eq "df commit subject" "dotfiles: declare formula hashicorp/tap/terraform (global)" "$(df_subject)"

# ── --ignore-local libtiff, then --global removes the ignore ──────────────────
decree libtiff --ignore-local --reason dep
assert_eq "ignore-local exits 0" 0 "${RC}"
assert_file "local Brewfile.ignore created" "${LOCAL_IGNORE}"
assert_contains "ignore line written" "$(cat "${LOCAL_IGNORE}")" "formula libtiff"
assert_contains "ignore line carries the reason" "$(cat "${LOCAL_IGNORE}")" "# dep"
assert_eq "ignore commit subject" "dotfiles: ignore formula libtiff (local): dep" "$(ldf_subject)"
assert_eq "ignore pushed" "$(ldf_head)" "$(ldf_origin_main)"
bump_now_secs 60
nm brew triage --json
assert_json "classifier shows libtiff ignored" "$(out_json)" '[.ignored[] | select(.name=="libtiff")] | length' 1

# A hand-placed ignore line (the shipped global Brewfile.ignore is all hand-placed) goes too: §3.4 step 2.
printf 'formula libtiff   # library shim, hand-placed\n' > "${GLOBAL_IGNORE}"
df_git add -- "${GLOBAL_IGNORE}"
df_git commit -q -m "hand-place a global ignore"
decree libtiff --global
assert_eq "decree libtiff --global exits 0" 0 "${RC}"
assert_contains "global Brewfile gained libtiff" "$(cat "${GLOBAL}")" 'brew "libtiff"'
assert_not_contains "ignore line removed" "$(cat "${LOCAL_IGNORE}")" "libtiff"
assert_eq "ignore removal committed in the local tier" "" "$(ldf_git status --porcelain -- "${LOCAL_IGNORE}")"
assert_not_contains "hand-placed global ignore line removed too" "$(cat "${GLOBAL_IGNORE}")" "libtiff"
assert_eq "global ignore removal committed with the declaration" "" "$(df_git status --porcelain -- "${GLOBAL_IGNORE}")"
assert_contains "commit body records the dropped ignore line" "$(df_git log -1 --format=%b)" "drop ignore line: formula libtiff"

# ── ambiguous kind ────────────────────────────────────────────────────────────
fixture_add_formula foo
fixture_add_cask foo
ldf_before="$(ldf_head)"
decree foo --local
assert_eq "ambiguous kind → exit 64" 64 "${RC}"
assert_contains "candidates name the formula form" "${OUT}${ERR}" "formula:foo"
assert_contains "candidates name the cask form" "${OUT}${ERR}" "cask:foo"

# ── the same decree twice ─────────────────────────────────────────────────────
decree gh --local
assert_eq "second decree exits 1" 1 "${RC}"
assert_eq "second decree commits nothing" "${ldf_before}" "$(ldf_head)"

# ── unrelated staged changes ──────────────────────────────────────────────────
# A path the allowlist admits (!/bin/), so `git add` really stages it.
mkdir -p "${HOME}/.local/bin"
printf 'unrelated\n' > "${HOME}/.local/bin/unrelated"
ldf_git add -- "${HOME}/.local/bin/unrelated"
assert_eq "test setup: an unrelated file is staged" "bin/unrelated" "$(ldf_git diff --cached --name-only)"
local_sha_before="$(sha256 "${LOCAL}")"
decree python@3.10 --local
assert_eq "staged changes → exit 1" 1 "${RC}"
assert_contains "names the refusal" "${OUT}${ERR}" "unrelated staged changes"
assert_eq "local Brewfile untouched" "${local_sha_before}" "$(sha256 "${LOCAL}")"
assert_eq "nothing committed" "${ldf_before}" "$(ldf_head)"
ldf_git reset -q -- "${HOME}/.local/bin/unrelated"
rm -f "${HOME}/.local/bin/unrelated"
# Whatever the refusal left behind is discarded so the cases below start from the committed tier.
ldf_git checkout -q -- "${LOCAL}"
assert_eq "test setup: local Brewfile back at HEAD" "${local_sha_before}" "$(sha256 "${LOCAL}")"

# ── --dry-run ─────────────────────────────────────────────────────────────────
decree python@3.10 --local --dry-run
assert_eq "dry-run exits 0" 0 "${RC}"
assert_eq "dry-run changes no file" "${local_sha_before}" "$(sha256 "${LOCAL}")"
assert_eq "dry-run commits nothing" "${ldf_before}" "$(ldf_head)"
assert_contains "dry-run prints the line" "${OUT}${ERR}" 'brew "python@3.10"'
assert_contains "dry-run prints the target path" "${OUT}${ERR}" "${LOCAL}"
assert_contains "dry-run prints the git commands" "${OUT}${ERR}" "commit"

# ── push failure is a warning ─────────────────────────────────────────────────
ldf_git remote remove origin
decree python@3.10 --local
assert_eq "decree without an origin exits 0" 0 "${RC}"
assert_eq "commit stands" "dotfiles: declare formula python@3.10 (local)" "$(ldf_subject)"
assert_contains "stderr points at git ldf push" "${ERR}" "git ldf push"

# ── the block stays sorted: taps, then formulae by name ───────────────────────
expected_block='tap "buildkite/buildkite", trusted: true
brew "buildkite/buildkite/bk@3"
brew "gh"
brew "python@3.10"'
assert_eq "decree block sorted by kind then name" "${expected_block}" "$(block_lines "${LOCAL}")"
assert_no_mutation "decree never calls a mutating brew command"

report
