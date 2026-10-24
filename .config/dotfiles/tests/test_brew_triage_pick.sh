#!/usr/bin/env bash
# `brew triage --interactive`: the plan grouping as a pure function (choices in, decree argument
# lists out), the usage errors without a terminal or with --json, and plain triage untouched.
# The chooser itself needs a tty; the suite never has one, so it is checked by hand in tmux.
set -u
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

world_new
world_use_fixture drift

T=$'\t'
plan() { zfn decree.zsh decree::triage_plan "$@"; }

# ── decree::triage_plan: grouping ─────────────────────────────────────────────
plan -- "local${T}formula:gh${T}work tools" "global${T}cask:google-chrome${T}browser" "skip${T}tap:hashicorp/tap${T}" \
        "local${T}vscode:ms-python.python${T}work tools" "local${T}formula:deno${T}scripts" \
        "ignore-local${T}formula:libtiff${T}pulled in by a cask" \
        "ignore-global${T}formula:jq${T}every machine has it from elsewhere" \
        "ignore-local${T}formula:wget${T}pulled in by a cask" "ignore-local${T}formula:curl${T}system one is fine"
assert_eq "plan exits 0" 0 "${RC}"
assert_eq "one line per group: tier-flag order, items in choice order, split by reason" \
"cask:google-chrome --global --reason browser
formula:gh vscode:ms-python.python --local --reason 'work tools'
formula:deno --local --reason scripts
formula:jq --ignore-global --reason 'every machine has it from elsewhere'
formula:libtiff formula:wget --ignore-local --reason 'pulled in by a cask'
formula:curl --ignore-local --reason 'system one is fine'" "${OUT}"

plan --dry-run --no-push -- "global${T}formula:gh${T}auth" "ignore-local${T}cask:zoom${T}work"
assert_eq "--dry-run and --no-push end every group" \
"formula:gh --global --reason auth --dry-run --no-push
cask:zoom --ignore-local --reason work --dry-run --no-push" "${OUT}"

plan --no-push "local${T}formula:gh${T}auth"
assert_eq "pass-through flags without --" "formula:gh --local --reason auth --no-push" "${OUT}"

plan -- "skip${T}formula:gh${T}" "skip${T}cask:zoom${T}"
assert_eq "all skipped: no groups" 0 "${RC}"
assert_eq "all skipped: nothing printed" "" "${OUT}"

plan --
assert_eq "no choices: nothing printed" "" "${OUT}"

plan -- "local${T}formula:gh${T}the reason is the Brewfile comment"
assert_eq "a declare carries its --reason" "formula:gh --local --reason 'the reason is the Brewfile comment'" "${OUT}"
plan -- "global${T}formula:gh${T}"
assert_eq "a declare without a reason is refused" 64 "${RC}"
assert_contains "and names the action and the item" "${ERR}" "a global needs a reason | item='formula:gh'"

# The quoting round-trips through ${(Q)${(z)…}}, the way triage --interactive splits a line.
zfn decree.zsh eval 'for w in "${(@Q)${(z)$(decree::triage_plan -- "ignore-global"$'"'"'\t'"'"'"formula:gh"$'"'"'\t'"'"'"it'"'"'s \$HOME; \"x\" * y")}}"; do print -r -- "[${w}]"; done'
assert_eq "words survive the quoting" "[formula:gh]
[--ignore-global]
[--reason]
[it's \$HOME; \"x\" * y]" "${OUT}"

zfn decree.zsh decree::triage_plan_action "formula:gh cask:zoom --ignore-local --reason 'a --global b' --dry-run"
assert_eq "plan_action reads the flag word, not one inside a reason" "ignore-local" "${OUT}"

plan -- "ignore-local${T}formula:gh${T}"
assert_eq "an ignore without a reason is refused" 64 "${RC}"
assert_contains "and names the item" "${ERR}" "item='formula:gh'"
plan -- "global-ish${T}formula:gh${T}"
assert_eq "an unknown action is refused" 64 "${RC}"
plan -- "local${T}${T}"
assert_eq "a choice without an item is refused" 64 "${RC}"

# ── Usage errors ──────────────────────────────────────────────────────────────
bump_now_secs 60
nm brew triage --interactive < /dev/null
assert_eq "--interactive without a terminal is a usage error" 64 "${RC}"
assert_contains "and names the non-interactive form" "${ERR}" "run 'dotfiles brew triage' and paste the decree commands"
assert_not_contains "nothing is rendered on stdout" "${OUT}" "undeclared"

bump_now_secs 60
nm brew triage --interactive --dry-run --no-push < /dev/null
assert_eq "--interactive --dry-run without a terminal is still a usage error" 64 "${RC}"

bump_now_secs 60
nm brew triage --json --interactive < /dev/null
assert_eq "--json with --interactive is a usage error" 64 "${RC}"
assert_contains "and says they do not mix" "${ERR}" "--json and --interactive do not mix"
assert_eq "no JSON is printed" "" "${OUT}"

bump_now_secs 60
nm brew triage --dry-run < /dev/null
assert_eq "--dry-run without --interactive is a usage error" 64 "${RC}"
assert_contains "and names --interactive" "${ERR}" "go with --interactive"
assert_no_mutation "the usage errors are read-only"

# ── Help and the plain path ───────────────────────────────────────────────────
# A triage usage error prints the brew verb's help, as `--help` does.
nm brew triage --bogus < /dev/null
assert_eq "an unknown triage flag is a usage error" 64 "${RC}"
assert_contains "triage usage synopsis names --interactive" "${ERR}" "brew triage (--interactive | --edit [FILE]) [--dry-run] [--no-push]"
assert_contains "triage usage has the flag line" "${ERR}" "  --interactive   triage: pick a tier and give a reason per undeclared item"
nm help brew
assert_contains "brew help usage names --interactive" "${OUT}${ERR}" "brew triage (--interactive | --edit [FILE]) [--dry-run] [--no-push]"

bump_now_secs 60
nm brew triage < /dev/null
assert_eq "plain triage still exits 1 with drift" 1 "${RC}"
assert_contains "plain triage still prints the decree commands, each with --reason" "${OUT}" "dotfiles brew decree formula:gh --global --reason \"…\""
assert_contains "plain triage still lists orphans after undeclared" "${OUT}" "orphaned kegs"

report
