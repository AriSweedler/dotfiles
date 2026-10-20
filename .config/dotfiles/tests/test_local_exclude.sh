#!/usr/bin/env bash
# The local-dotfiles allowlist template admits share/new-machine/ but still excludes secrets.
set -u
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

world_new
BARE="${FIX}/ldf.git"
WORK="${FIX}/ldfwork"
git init -q --bare --initial-branch=main "${BARE}"
mkdir -p "${BARE}/info" "${WORK}/share/new-machine"
cp "${REPO_DIR}/local-dotfiles-exclude" "${BARE}/info/exclude"
printf 'brew "gh"\n' > "${WORK}/share/new-machine/Brewfile"
printf 'formula libtiff  # library\n' > "${WORK}/share/new-machine/Brewfile.ignore"
printf 'export TOKEN=nope\n' > "${WORK}/share/new-machine/x.secret.zsh"
g() { git --git-dir="${BARE}" --work-tree="${WORK}" "$@"; }

rc=0; (cd "${WORK}" && g check-ignore -q share/new-machine/Brewfile) || rc=$?
assert_eq "share/new-machine/Brewfile is tracked-eligible" 1 "${rc}"
rc=0; (cd "${WORK}" && g check-ignore -q share/new-machine/Brewfile.ignore) || rc=$?
assert_eq "share/new-machine/Brewfile.ignore is tracked-eligible" 1 "${rc}"
rc=0; (cd "${WORK}" && g check-ignore -q share/new-machine/x.secret.zsh) || rc=$?
assert_eq "share/new-machine/x.secret.zsh stays excluded" 0 "${rc}"

(cd "${WORK}" && g add -A .)
staged="$(g diff --cached --name-only | sort)"
assert_eq "git add -A stages exactly the two Brewfiles" "share/new-machine/Brewfile
share/new-machine/Brewfile.ignore" "${staged}"

# Every directory the template admits by name keeps a secret beside it out, as the edit checks.
admitted="$(awk '/^!\/[^*?[]*\/$/ { print substr($0, 3, length($0) - 3) }' "${REPO_DIR}/local-dotfiles-exclude")"
leaks=""
while IFS= read -r d; do
  [[ -n "${d}" ]] || continue
  mkdir -p "${WORK}/${d}"
  printf 'export TOKEN=nope\n' > "${WORK}/${d}/x.secret.zsh"
  (cd "${WORK}" && g check-ignore -q "${d}/x.secret.zsh") || leaks+=" ${d}/x.secret.zsh"
done <<< "${admitted}"
assert_contains "the template admits directories" "${admitted}" "share/new-machine"
assert_eq "no admitted directory lets a *.secret.zsh in" "" "${leaks}"

# The template is an allowlist (its first rule excludes everything), and every '!' entry says
# why: a '# why' comment on the line above it or above its run of '!' lines.
first_rule="$(grep -vE '^[[:space:]]*(#|$)' "${REPO_DIR}/local-dotfiles-exclude" | head -n 1)"
assert_eq "the first rule is /*" "/*" "${first_rule}"
undocumented="$(awk '/^!/ && prev !~ /^!/ { doc = (prev ~ /^#[[:space:]]*[^[:space:]]/) } /^!/ && !doc { print } { prev = $0 }' "${REPO_DIR}/local-dotfiles-exclude")"
assert_eq "every '!' entry of the template has its why" "" "${undocumented}"
# cmd/git.zsh opens with its declaration, so lib/verb.zsh is loaded first, as bin/dotfiles does.
hermetic_env
RC=0
OUT="$(env -i "${HERMETIC_ENV[@]}" "${FIX}/tools/zsh" -f -c 'source "${1:h:h}/lib/verb.zsh"; source "$1"; git_allowlist_undocumented "$2"; print -rl -- "${reply[@]}"' _ \
  "${ORIG_CONFIG_DIR}/dotfiles/cmd/git.zsh" "${REPO_DIR}/local-dotfiles-exclude" 2>&1)" || RC=$?
assert_eq "git_allowlist_undocumented agrees: nothing" "0:" "${RC}:${OUT}"
# What the rule calls documented: a comment heads a run of '!' lines; any other line ends the run.
printf '/*\n# why a and b\n!/a/\n!/b/\n/b/*\n!/b/c/\n#\n!/d/\n' > "${FIX}/sample-exclude"
OUT="$(env -i "${HERMETIC_ENV[@]}" "${FIX}/tools/zsh" -f -c 'source "${1:h:h}/lib/verb.zsh"; source "$1"; git_allowlist_undocumented "$2"; print -r -- "${reply[*]}"' _ \
  "${ORIG_CONFIG_DIR}/dotfiles/cmd/git.zsh" "${FIX}/sample-exclude" 2>&1)"
assert_eq "a run under a comment is documented; after a rule or an empty '#' it is not" "!/b/c/ !/d/" "${OUT}"

report
