#!/usr/bin/env bash
# test_suites: the doc rule for tests. A hermetic tests/test_*.sh says what it checks on line 2,
# a plugin *.test.zsh names an existing target on line 1 ('# Tests for <file>'); one that does
# not is a manual fail naming `dotfiles test --edit NAME`. A plugin with no suite is counted in
# the ok detail, never failed. The real suites of this checkout pass.
set -u
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

world_new
world_use_fixture satisfied
status_of() { step_get test_suites "$1"; }
check_suites() { bump_now_secs 60; nm check --only test_suites --json; out_json > /dev/null; }

# ── this checkout's own suites: every one documented ──
check_suites
assert_eq "this checkout: ok" ok "$(status_of .status)"
assert_eq "this checkout: reason documented" documented "$(status_of .reason)"
assert_contains "this checkout: plugins without a suite are a count" "$(status_of .detail)" "plugins have no suite"

# ── fixture suites, through the seams ──
PLUG="${FIX}/plugins"
SUITES="${FIX}/tests"
mkdir -p "${PLUG}" "${SUITES}"
export ARI_DOTFILES_ZSH_PLUGINS="${PLUG}" ARI_DOTFILES_TESTS="${SUITES}"
printf '# foo\n' > "${PLUG}/foo.zsh"
printf '# Tests for foo.zsh — the foo helpers.\n' > "${PLUG}/foo.test.zsh"
printf '# Tests for ~/.config/bin/dotfiles.\n' > "${PLUG}/entry.test.zsh"
printf '# bare\n' > "${PLUG}/bare.zsh"
printf '# lonely\n' > "${PLUG}/lonely.zsh"
printf '# the runner\n' > "${PLUG}/run_tests.zsh"
printf '#!/usr/bin/env bash\n# bar: what it checks.\n' > "${SUITES}/test_bar.sh"
printf '#!/usr/bin/env bash\n# baz: what it checks.\n' > "${SUITES}/test_baz.sh"
printf '#!/usr/bin/env bash\n' > "${SUITES}/run.sh"
# Old enough that the cache may store the verdict (inputs changed in the last two seconds are racy).
age() { touch -t 202601010000 "${PLUG}" "${PLUG}"/* "${SUITES}" "${SUITES}"/*; }
age

check_suites
assert_eq "documented: ok" ok "$(status_of .status)"
assert_eq "documented: the counts" "2 hermetic and 2 plugin suites say what they test; 2 plugins have no suite" "$(status_of .detail)"
check_suites
assert_eq "unchanged: still ok" ok "$(status_of .status)"
assert_contains "unchanged: a cache hit" "$(status_of .detail)" "cached: true"

# A hermetic suite with no description on line 2.
printf '#!/usr/bin/env bash\nset -u\n' > "${SUITES}/test_baz.sh"
check_suites
assert_eq "no line 2: fail" fail "$(status_of .status)"
assert_eq "no line 2: reason undocumented" undocumented "$(status_of .reason)"
assert_eq "no line 2: manual" true "$(status_of .manual)"
assert_eq "no line 2: not actionable" false "$(status_of .actionable)"
assert_contains "no line 2: names the file" "$(status_of .detail)" "tests/test_baz.sh: line 2 is not a '# ' line saying what it checks"
assert_eq "no line 2: the fix" "dotfiles test --edit baz" "$(status_of .fix)"
printf '#!/usr/bin/env bash\n# baz: what it checks.\n' > "${SUITES}/test_baz.sh"
printf '#!/usr/bin/env bash\n#\n' > "${SUITES}/test_foo.sh"
check_suites
assert_eq "named like a plugin suite: the fix spells test_NAME" "dotfiles test --edit test_foo" "$(status_of .fix)"
rm -f "${SUITES}/test_foo.sh"

# A plugin suite without '# Tests for', and one whose target does not exist.
printf '# Checks foo.\n' > "${PLUG}/foo.test.zsh"
printf '# Tests for gone.zsh.\n' > "${PLUG}/bare.test.zsh"
check_suites
assert_eq "plugin headers: fail" fail "$(status_of .status)"
assert_contains "no '# Tests for': named" "$(status_of .detail)" "zsh/plugins/foo.test.zsh: line 1 is not '# Tests for <file>'"
assert_contains "missing target: named" "$(status_of .detail)" "zsh/plugins/bare.test.zsh: '# Tests for gone.zsh.' names no file"
assert_contains "the fix names the first" "$(status_of .fix)" "dotfiles test --edit "
rm -f "${PLUG}/bare.test.zsh"
printf '# Tests for foo.zsh.\n' > "${PLUG}/foo.test.zsh"
check_suites
assert_eq "fixed: ok again" ok "$(status_of .status)"

nm steps
assert_contains "registered in the repo group" "$(awk '$1 == "test_suites" { print $2 }' <<< "${OUT}")" "repo"
assert_no_mutation "read-only"

if (( FAIL > 0 )); then printf '%s\n' "${ERR}" | tail -n 30 >&2; fi
report
