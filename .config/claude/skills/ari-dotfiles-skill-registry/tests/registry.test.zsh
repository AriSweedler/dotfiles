#!/usr/bin/env zsh
# Automated tests for lib/registry.zsh's submodule roots, each in a throwaway HOME: a root the
# shared tier's dev-repos manifest declares, the manifest and a .gitmodules together (each root
# once), a .gitmodules alone (the bare-repo layout), and `status` keeping source=submodule:<path>;
# and the local tier's root and worktree in the local-dotfiles clone layout and the bare one.
# Run: zsh $HOME/.claude/skills/ari-dotfiles-skill-registry/tests/registry.test.zsh
set -uo pipefail

readonly SKILL_DIR="${0:A:h:h}"
readonly REGISTRY_LIB="${SKILL_DIR}/lib/registry.zsh"
readonly STATUS_BIN="${SKILL_DIR}/bin/status"
LIB_LOGGING="${HOME}/.claude/skills/ari-skill-shellscripts/lib/logging.zsh"
# Before link has run the farm is empty: the sibling in this tier root, as bin/ does.
[[ -r "${LIB_LOGGING}" ]] || LIB_LOGGING="${SKILL_DIR:h}/ari-skill-shellscripts/lib/logging.zsh"
readonly LIB_LOGGING
readonly T="$(mktemp -d "${TMPDIR:-/tmp}/registry-test.XXXXXX")"
trap 'rm -rf "${T}"' EXIT

typeset -i pass=0 fail=0
check() {   # <name> <want> <got>
  if [[ "${2}" == "${3}" ]]; then
    pass=$(( pass + 1 )); print -r -- "ok      ${1}"
    return 0
  fi
  fail=$(( fail + 1 )); print -r -- "FAIL    ${1} | want='${2}' got='${3}'"
}
contains() {   # <name> <needle> <haystack>
  if [[ "${3}" == *"${2}"* ]]; then
    pass=$(( pass + 1 )); print -r -- "ok      ${1}"
    return 0
  fi
  fail=$(( fail + 1 )); print -r -- "FAIL    ${1} | needle='${2}' in='${3}'"
}

#######################################
# Make a skill directory with a SKILL.md.
# Arguments:
#   $1 - directory
#######################################
mk_skill() {
  mkdir -p "${1}"
  print -r -- "---" > "${1}/SKILL.md"
}

#######################################
# Print `skill_roots df` as the registry computes it in the given HOME, one per line, with the
# dotfiles CLI's overrides unset so the registry makes its own pick.
# Arguments:
#   $1 - fake HOME
#######################################
roots_in() {
  env -u ARI_DOTFILES_DF_WORK_TREE -u ARI_DOTFILES_DEV_REPOS HOME="${1}" \
    zsh -c 'source "${1}"; source "${2}"; skill_roots df' zsh "${LIB_LOGGING}" "${REGISTRY_LIB}"
}

#######################################
# Print `status --all`'s rows in the given HOME.
# Arguments:
#   $1 - fake HOME
#######################################
status_in() {
  env -u ARI_DOTFILES_DF_WORK_TREE -u ARI_DOTFILES_DEV_REPOS HOME="${1}" \
    zsh "${STATUS_BIN}" --all 2>/dev/null
}

#######################################
# Write a dev-repos manifest declaring each path, with a comment line as the real one has.
# Arguments:
#   $1 - manifest file
#   $@ - repo paths
#######################################
write_manifest() {
  local file="${1}"; shift
  mkdir -p "${file:h}"
  {
    print -r -- "# Ari's own public repos, checked out inside the clone."
    local p
    for p in "$@"; do
      print -r -- "[repo \"${p}\"]"
      print -r -- "	path = ${p}"
      print -r -- "	url = https://example.com/${p:t}.git"
      print -r -- "	input = ${p:t}"
    done
  } > "${file}"
}

#######################################
# Write a .gitmodules declaring each path.
# Arguments:
#   $1 - .gitmodules file
#   $@ - submodule paths
#######################################
write_gitmodules() {
  local file="${1}"; shift
  local p
  for p in "$@"; do
    print -r -- "[submodule \"${p}\"]"
    print -r -- "	path = ${p}"
    print -r -- "	url = https://example.com/${p:t}.git"
  done > "${file}"
}

# 1. Nix layout: the ~/dotfiles clone, a manifest-declared root, no .gitmodules anywhere.
h="${T}/manifest"
mkdir -p "${h}/dotfiles/.git" "${h}/.claude/skills"
mk_skill "${h}/dotfiles/.config/claude/skills/tier-skill"
write_manifest "${h}/dotfiles/.config/dotfiles/dev-repos" .config/plugged .config/no-skills
mk_skill "${h}/dotfiles/.config/plugged/skills/dev-skill"
mkdir -p "${h}/dotfiles/.config/no-skills"
check "manifest: tier root, then the declared repo's skills/" \
  "${h}/dotfiles/.config/claude/skills"$'\n'"${h}/dotfiles/.config/plugged/skills" "$(roots_in "${h}")"
rows="$(status_in "${h}")"
contains "manifest: an unlinked dev-repo skill is missing, with its source" \
  "state=missing tier=df name=dev-skill source=submodule:.config/plugged" "${rows}"
ln -s "${h}/dotfiles/.config/plugged/skills/dev-skill" "${h}/.claude/skills/dev-skill"
rows="$(status_in "${h}")"
contains "manifest: a linked dev-repo skill keeps source=submodule:<path>" \
  "state=linked tier=df name=dev-skill source=submodule:.config/plugged" "${rows}"

# 2. The manifest and a .gitmodules together: a path both name is one root.
h="${T}/both"
mkdir -p "${h}/dotfiles/.git" "${h}/.claude/skills" "${h}/dotfiles/.config/claude/skills"
write_manifest "${h}/dotfiles/.config/dotfiles/dev-repos" .config/plugged
write_gitmodules "${h}/dotfiles/.gitmodules" .config/plugged .config/exo
mk_skill "${h}/dotfiles/.config/plugged/skills/dev-skill"
mk_skill "${h}/dotfiles/.config/exo/skills/exo-skill"
check "both: manifest paths first, .gitmodules adds the rest, none twice" \
  "${h}/dotfiles/.config/claude/skills"$'\n'"${h}/dotfiles/.config/plugged/skills"$'\n'"${h}/dotfiles/.config/exo/skills" \
  "$(roots_in "${h}")"
rows="$(status_in "${h}")"
contains "both: a skill under a root both name is not a conflict" \
  "state=missing tier=df name=dev-skill source=submodule:.config/plugged" "${rows}"
contains "both: a .gitmodules-only root still counts" \
  "state=missing tier=df name=exo-skill source=submodule:.config/exo" "${rows}"

# 3. Bare-repo layout (no ~/dotfiles clone): HOME is the worktree and its .gitmodules is read.
h="${T}/bare"
mkdir -p "${h}/.claude/skills" "${h}/.config/claude/skills"
write_gitmodules "${h}/.gitmodules" .config/plugged
mk_skill "${h}/.config/plugged/skills/dev-skill"
check "bare: HOME's .gitmodules names the root" \
  "${h}/.config/claude/skills"$'\n'"${h}/.config/plugged/skills" "$(roots_in "${h}")"
contains "bare: source is relative to HOME" \
  "state=missing tier=df name=dev-skill source=submodule:.config/plugged" "$(status_in "${h}")"

# 4. Under the Nix layout a stale HOME/.gitmodules (left from the bare-repo layout) is not read.
h="${T}/stale"
mkdir -p "${h}/dotfiles/.git" "${h}/.claude/skills" "${h}/dotfiles/.config/claude/skills"
write_gitmodules "${h}/.gitmodules" .config/old
mk_skill "${h}/.config/old/skills/old-skill"
check "stale: only the tier root" "${h}/dotfiles/.config/claude/skills" "$(roots_in "${h}")"

# 5. The CLI's overrides: a clone's .git in ARI_DOTFILES_DF_GIT_DIR names its parent (no ~/dotfiles
# needed); a trailing slash on ARI_DOTFILES_DF_WORK_TREE still yields source=submodule:<path>.
h="${T}/override"
mkdir -p "${h}/clone/.git" "${h}/.claude/skills" "${h}/clone/.config/claude/skills"
write_manifest "${h}/clone/.config/dotfiles/dev-repos" .config/plugged
mk_skill "${h}/clone/.config/plugged/skills/dev-skill"
got="$(env -u ARI_DOTFILES_DF_WORK_TREE -u ARI_DOTFILES_DEV_REPOS HOME="${h}" ARI_DOTFILES_DF_GIT_DIR="${h}/clone/.git" \
  zsh -c 'source "${1}"; source "${2}"; skill_roots df' zsh "${LIB_LOGGING}" "${REGISTRY_LIB}")"
check "override: ARI_DOTFILES_DF_GIT_DIR's parent is the worktree" \
  "${h}/clone/.config/claude/skills"$'\n'"${h}/clone/.config/plugged/skills" "${got}"
got="$(env -u ARI_DOTFILES_DEV_REPOS HOME="${h}" ARI_DOTFILES_DF_WORK_TREE="${h}/clone/" zsh "${STATUS_BIN}" --all 2>/dev/null)"
contains "override: a trailing slash keeps the source path relative" \
  "state=missing tier=df name=dev-skill source=submodule:.config/plugged" "${got}"

# 6. A manifest git cannot parse warns and counts no roots from it.
h="${T}/broken"
mkdir -p "${h}/dotfiles/.git" "${h}/.claude/skills" "${h}/dotfiles/.config/claude/skills"
mkdir -p "${h}/dotfiles/.config/dotfiles"
print -r -- '[repo ".config/plugged"' > "${h}/dotfiles/.config/dotfiles/dev-repos"
mk_skill "${h}/dotfiles/.config/plugged/skills/dev-skill"
got="$(env -u ARI_DOTFILES_DF_WORK_TREE -u ARI_DOTFILES_DEV_REPOS HOME="${h}" \
  zsh -c 'source "${1}"; source "${2}"; skill_roots df' zsh "${LIB_LOGGING}" "${REGISTRY_LIB}" 2>&1)"
contains "broken: the unreadable manifest is named in a warning" "unreadable submodule manifest" "${got}"
contains "broken: the tier root is still listed" "${h}/dotfiles/.config/claude/skills" "${got}"

# 7. Each tier root sits under its tier worktree, in both layouts: callers (/ari-skill-update's
# blobs lib) take the root's path relative to the worktree.
for h in "${T}/manifest" "${T}/bare"; do
  got="$(env -u ARI_DOTFILES_DF_WORK_TREE -u ARI_DOTFILES_DEV_REPOS -u ARI_DOTFILES_LDF_GIT_DIR -u ARI_DOTFILES_LDF_WORK_TREE \
    HOME="${h}" zsh -c '
    source "${1}"; source "${2}"
    for t in "${TIERS[@]}"; do
      [[ "${TIER_ROOTS[$t]}" == "${TIER_WORKTREES[$t]}"/* ]] && print -r -- "${t} under" || print -r -- "${t} outside"
    done' zsh "${LIB_LOGGING}" "${REGISTRY_LIB}")"
  check "invariant (${h:t}): every tier root is under its worktree" "df under"$'\n'"ldf under" "${got}"
done

#######################################
# Print the local tier's root and worktree as the registry computes them in the given HOME, the
# dotfiles CLI's ldf overrides unset unless passed as NAME=VALUE arguments.
# Arguments:
#   $1 - fake HOME
#   $@ - extra environment assignments
#######################################
ldf_in() {
  local home="${1}"; shift
  env -u ARI_DOTFILES_LDF_GIT_DIR -u ARI_DOTFILES_LDF_WORK_TREE -u ARI_DOTFILES_MACHINE -u ARI_DOTFILES_MACHINE_NAME_FILE \
    HOME="${home}" "$@" zsh -c 'source "${1}"; source "${2}"; print -r -- "${TIER_ROOTS[ldf]} ${TIER_WORKTREES[ldf]}"' \
    zsh "${LIB_LOGGING}" "${REGISTRY_LIB}"
}

# 8. The local tier follows lib/env.zsh: the ~/local-dotfiles clone when it has a .git (root under
# local/<machine>/, the machine from the machine-name file), else the bare repo with ~/.local.
h="${T}/ldf-clone"
mkdir -p "${h}/local-dotfiles/.git" "${h}/.local/share/dotfiles"
print -r -- "testbox" > "${h}/.local/share/dotfiles/machine-name"
check "ldf clone: root under local/<machine>/, worktree the clone" \
  "${h}/local-dotfiles/local/testbox/share/claude-skills ${h}/local-dotfiles" "$(ldf_in "${h}")"
check "ldf clone: ARI_DOTFILES_MACHINE wins over the file" \
  "${h}/local-dotfiles/local/other/share/claude-skills ${h}/local-dotfiles" "$(ldf_in "${h}" ARI_DOTFILES_MACHINE=other)"
check "ldf clone: ARI_DOTFILES_LDF_GIT_DIR naming the bare repo restores ~/.local" \
  "${h}/.local/share/claude-skills ${h}/.local" "$(ldf_in "${h}" ARI_DOTFILES_LDF_GIT_DIR="${h}/.local/local-dotfiles.git")"
check "ldf bare: no clone, the bare repo's ~/.local" \
  "${T}/bare/.local/share/claude-skills ${T}/bare/.local" "$(ldf_in "${T}/bare")"

print -r -- "summary  pass=${pass} fail=${fail}"
(( fail == 0 ))
