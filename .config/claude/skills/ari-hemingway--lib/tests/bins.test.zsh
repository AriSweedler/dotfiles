#!/usr/bin/env zsh
# Automated tests for bin/verify-claims-at-sha and bin/git-permalink-info against throwaway repos, no network:
# git's http.proxy points at a closed port, so the one fetch the suite allows fails at once.
# verify-claims-at-sha: a present line, an expected substring (colons and glob characters taken literally),
# a line past the end, a path absent at the SHA, a malformed claim, a non-numeric line, a claims file with
# comments, a SHA that is not a commit; exit 1 when any claim fails.
# git-permalink-info: owner/repo and host from every remote URL form, a GitHub Enterprise host, a non-GitHub
# host, the fallback chain, --no-fetch, a fetch that fails without aborting, and the exit codes.
# Run: zsh $HOME/.claude/skills/ari-hemingway--lib/tests/bins.test.zsh
set -uo pipefail

readonly BIN="${0:A:h:h}/bin"
readonly T="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/hemingway-bins-test.XXXXXX")" && pwd -P)"
trap 'rm -rf "${T}"' EXIT
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL="${T}/gitconfig" GIT_TERMINAL_PROMPT=0 FETCH_HARD_TIMEOUT_SECS=10
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.com
git config --file "${GIT_CONFIG_GLOBAL}" init.defaultBranch main
git config --file "${GIT_CONFIG_GLOBAL}" http.proxy http://127.0.0.1:1

typeset -i pass=0 fail=0
check() {   # <name> <want> <got>
  if [[ "${2}" == "${3}" ]]; then (( pass++ )); print -r -- "ok      ${1}"
  else (( fail++ )); print -r -- "FAIL    ${1} | want='${2}' got='${3}'"; fi
}
contains() {   # <name> <needle> <haystack>
  if [[ "${3}" == *"${2}"* ]]; then (( pass++ )); print -r -- "ok      ${1}"
  else (( fail++ )); print -r -- "FAIL    ${1} | needle='${2}' in='${3}'"; fi
}
typeset -g out="" err="" rc=0
run() { rc=0; out="$("$@" 2>"${T}/err")" || rc=$?; err="$(<"${T}/err")"; }
field() { print -r -- "${out}" | sed -n "s/^${1}=//p"; }
row() { print -r -- "${out}" | awk -v p="${1}" '$3 == p { print $1; exit }'; }

# A repo with one file, committed; the file changes afterwards, so the old SHA keeps the old text.
R="${T}/repo"; git init -q "${R}"
print -r -- $'first line\n  const url = "a:b:c";\nmatch [this] *literally*' > "${R}/src.ts"
git -C "${R}" add -A; git -C "${R}" commit -q -m one
SHA="$(git -C "${R}" rev-parse HEAD)"
print -r -- "rewritten" > "${R}/src.ts"; git -C "${R}" commit -q -am two
cd "${R}" || exit 1

# ── verify-claims-at-sha ──
run zsh "${BIN}/verify-claims-at-sha" --sha "${SHA:0:7}" --claim src.ts:1 --claim 'src.ts:2:url = "a:b:c"' --claim 'src.ts:3:[this] *literally*'
check "claims: all pass is exit 0" 0 "${rc}"
check "claims: a present line passes" PASS "$(print -r -- "${out}" | awk '$2 == 1 { print $1 }')"
check "claims: an expected substring with colons passes" PASS "$(print -r -- "${out}" | awk '$2 == 2 { print $1 }')"
check "claims: glob characters in the expected text are literal" PASS "$(print -r -- "${out}" | awk '$2 == 3 { print $1 }')"
contains "claims: the detail is the line, trimmed" 'const url = "a:b:c";' "${out}"
contains "claims: the table is fenced for callers" "=== end FACT_CHECK ===" "${out}"

run zsh "${BIN}/verify-claims-at-sha" --sha "${SHA}" --claim 'src.ts:3:[that]' --claim src.ts:9 --claim gone.ts:1 --claim nocolon --claim src.ts:x
check "claims: any failure is exit 1" 1 "${rc}"
contains "claims: an absent substring names both" "expected substring absent | expected='[that]'" "${out}"
contains "claims: a line past the end" "line 9 is beyond end of file" "${out}"
contains "claims: a path absent at the SHA" "path not present at sha" "${out}"
contains "claims: a malformed claim" "malformed claim" "${out}"
contains "claims: a line that is not a number" "line is not a number" "${out}"
contains "claims: the summary counts the failures" "failed='5' total='5'" "${err}"

run zsh "${BIN}/verify-claims-at-sha" --sha HEAD --claim src.ts:1:rewritten
check "claims: HEAD has the rewritten text" 0 "${rc}"
run zsh "${BIN}/verify-claims-at-sha" --sha "${SHA}" --claim src.ts:1:rewritten
check "claims: the pinned SHA does not" 1 "${rc}"

print -r -- $'# a comment\n\nsrc.ts:1:first\nsrc.ts:2' > "${T}/claims"
run zsh "${BIN}/verify-claims-at-sha" --sha "${SHA}" --claims-file "${T}/claims"
check "claims file: blank lines and comments skipped, the rest pass" 0 "${rc}"
contains "claims file: two claims counted" "total='2'" "${err}"

run zsh "${BIN}/verify-claims-at-sha" --sha deadbeef --claim src.ts:1
check "claims: a SHA that is not a commit is exit 1" 1 "${rc}"
run zsh "${BIN}/verify-claims-at-sha" --sha "${SHA}"
check "claims: no claims is exit 1" 1 "${rc}"

# ── git-permalink-info: URL forms ──
typeset -A urls=(
  "https://github.com/Owner/repo.git"            "github.com Owner/repo"
  "https://github.com/Owner/repo"                "github.com Owner/repo"
  "https://github.com/Owner/repo/"               "github.com Owner/repo"
  "https://token@github.com/Owner/repo.git"      "github.com Owner/repo"
  "git@github.com:Owner/repo.git"                "github.com Owner/repo"
  "ssh://git@github.com:22/Owner/repo.git"       "github.com Owner/repo"
  "git@github.example.com:Team/svc.git"          "github.example.com Team/svc"
)
local url
git -C "${R}" remote add origin "https://github.com/Owner/repo.git"
git -C "${R}" update-ref refs/remotes/origin/main "${SHA}"
for url in "${(@k)urls}"; do
  git -C "${R}" remote set-url origin "${url}"
  run zsh "${BIN}/git-permalink-info" --no-fetch
  check "permalink: ${url}" "${urls[${url}]}" "$(field host) $(field owner_repo)"
done
check "permalink: the SHA is origin/main's, full" "${SHA}" "$(field sha)"
check "permalink: --no-fetch says skipped" "skipped" "$(field fetch_status)"
contains "permalink: the age is a number of seconds" "local_age_seconds=" "${out}"

git -C "${R}" remote set-url origin "https://gitlab.com/Owner/repo.git"
run zsh "${BIN}/git-permalink-info" --no-fetch
check "permalink: a host that is not GitHub is exit 5" 5 "${rc}"

# ── git-permalink-info: refs and fetch ──
git -C "${R}" remote set-url origin "https://github.com/Owner/repo.git"
run zsh "${BIN}/git-permalink-info" --no-fetch --ref origin/nope
check "permalink: an unresolvable ref falls back down the chain" "origin/main" "$(field ref)"
contains "permalink: and warns" "using fallback | requested='origin/nope' used='origin/main'" "${err}"
run zsh "${BIN}/git-permalink-info" --ref HEAD
check "permalink: a ref not on origin skips the fetch" "skipped HEAD" "$(field fetch_status) $(field ref)"
check "permalink: and resolves locally" "$(git -C "${R}" rev-parse HEAD)" "$(field sha)"
run zsh "${BIN}/git-permalink-info"
check "permalink: a fetch that fails is not fatal" 0 "${rc}"
check "permalink: it says failed and resolves the local ref" "failed ${SHA}" "$(field fetch_status) $(field sha)"
contains "permalink: and warns why" "Fetch failed (continuing with local ref)" "${err}"

run zsh "${BIN}/git-permalink-info" --ref
check "permalink: --ref with no value is exit 1" 1 "${rc}"
git -C "${R}" remote remove origin
run zsh "${BIN}/git-permalink-info" --no-fetch
check "permalink: no origin is exit 3" 3 "${rc}"
cd "${T}" || exit 1
run zsh "${BIN}/git-permalink-info" --no-fetch
check "permalink: outside a repo is exit 2" 2 "${rc}"
git init -q "${T}/empty"; cd "${T}/empty" || exit 1
git remote add origin git@github.com:o/r.git
run zsh "${BIN}/git-permalink-info" --no-fetch
check "permalink: no ref resolves at all is exit 4" 4 "${rc}"

print -r -- "summary  pass=${pass} fail=${fail}"
(( fail == 0 ))
