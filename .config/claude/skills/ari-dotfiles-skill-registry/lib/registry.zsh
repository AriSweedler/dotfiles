#!/usr/bin/env zsh
# Shared constants and skill classification for the registry scripts. Source it;
# do not execute. Callers source ari-skill-shellscripts/lib/logging.zsh first.
#
# Skills are versioned in the dotfiles, one real directory per tier root, and
# ${HOME}/.claude/skills/<name> is a symlink into whichever tier owns the skill.
# Ari's own repos checked out inside a tier add roots too: each one's top-level
# skills/ directory holds skills that travel with that repo, committed in its own
# repo. The shared tier names them in its dev-repos manifest (plain clones the
# shared repo ignores); a tier may still name them in a .gitmodules. Either way
# this file and its callers call them submodules (`source=submodule:<path>`).

[[ -n "${_ARI_SKILL_REGISTRY_ZSH:-}" ]] && return 0
readonly _ARI_SKILL_REGISTRY_ZSH=1

#######################################
# Set $REPLY to the shared tier's worktree, in the dotfiles CLI's order
# (lib/env.zsh): ARI_DOTFILES_DF_WORK_TREE when set; else the parent of
# ARI_DOTFILES_DF_GIT_DIR when that is a clone's .git, HOME when it is a bare
# repo; else the ~/dotfiles clone when it has a .git (the Nix port); else HOME
# (the bare repo ~/dotfiles.git). No trailing slash. No subshell.
#######################################
shared_worktree_reply() {
  if [[ -n "${ARI_DOTFILES_DF_WORK_TREE:-}" ]]; then
    REPLY="${ARI_DOTFILES_DF_WORK_TREE%/}"
    return 0
  fi
  if [[ -n "${ARI_DOTFILES_DF_GIT_DIR:-}" ]]; then
    REPLY="${HOME}"
    [[ "${${ARI_DOTFILES_DF_GIT_DIR%/}:t}" == .git ]] && REPLY="${${ARI_DOTFILES_DF_GIT_DIR%/}:h}"
    return 0
  fi
  if [[ -e "${HOME}/dotfiles/.git" ]]; then
    REPLY="${HOME}/dotfiles"
    return 0
  fi
  REPLY="${HOME}"
}

#######################################
# Set $REPLY to this machine's name in the local-dotfiles clone (its
# local/<machine>/ directory), as ldf-link reads it: ARI_DOTFILES_MACHINE when
# set; else the first word of the machine-name file; else the short hostname.
# No subshell.
#######################################
ldf_machine_reply() {
  if [[ -n "${ARI_DOTFILES_MACHINE:-}" ]]; then
    REPLY="${ARI_DOTFILES_MACHINE}"
    return 0
  fi
  local file="${ARI_DOTFILES_MACHINE_NAME_FILE:-${HOME}/.local/share/dotfiles/machine-name}"
  local -a words
  [[ -r "${file}" ]] && words=(${=$(<"${file}")})
  REPLY="${words[1]:-${HOST%%.*}}"
}

#######################################
# Set $reply to the local tier's (git dir, worktree), in the dotfiles CLI's
# order (lib/env.zsh): ARI_DOTFILES_LDF_GIT_DIR when set, else the
# ~/local-dotfiles clone's .git when it exists, else the bare repo
# ~/.local/local-dotfiles.git; the worktree is ARI_DOTFILES_LDF_WORK_TREE when
# set, else the git dir's parent when it is a clone's .git, else ~/.local. No
# trailing slash. No subshell.
#######################################
local_git_reply() {
  local git_dir="${HOME}/.local/local-dotfiles.git"
  [[ -d "${HOME}/local-dotfiles/.git" ]] && git_dir="${HOME}/local-dotfiles/.git"
  git_dir="${${ARI_DOTFILES_LDF_GIT_DIR:-${git_dir}}%/}"
  local work_tree="${HOME}/.local"
  [[ "${git_dir:t}" == .git ]] && work_tree="${git_dir:h}"
  reply=("${git_dir}" "${${ARI_DOTFILES_LDF_WORK_TREE:-${work_tree}}%/}")
}

# Callers define SKILLS_DIR before sourcing logging; this only fills it for a bare source.
: "${SKILLS_DIR:=${HOME}/.claude/skills}"
readonly IGNORE_FILE="${SKILLS_DIR}/.gitignore"
readonly TIERS=(df ldf)
# A clone machine is one whose local tier is the local-dotfiles clone (its git
# dir is named .git); the bare repo's worktree is ~/.local itself. On a clone
# machine the clone keeps this machine's files under local/<machine>/, and
# ldf-link assembles ~/.local from them: LDF_ASSEMBLED_ROOT/<name> is then a
# real directory of per-file links into the clone, never a tier root.
readonly LDF_ASSEMBLED_ROOT="${HOME}/.local/share/claude-skills"
local_git_reply
readonly LDF_GIT_DIR="${reply[1]}" LDF_WORKTREE="${reply[2]}"
if [[ "${LDF_GIT_DIR:t}" == .git ]]; then
  readonly LDF_CLONE=true
  ldf_machine_reply
  readonly LDF_MACHINE="${REPLY}"
  readonly LDF_ROOT="${LDF_WORKTREE}/local/${LDF_MACHINE}/share/claude-skills"
else
  readonly LDF_CLONE=false LDF_MACHINE=""
  readonly LDF_ROOT="${LDF_WORKTREE}/share/claude-skills"
fi
shared_worktree_reply
# Each tier root is the real directory that holds its skills, under its
# worktree (callers take the root's path relative to it): on the Nix port the
# shared root is in the ~/dotfiles clone, which ~/.config/claude links to; on a
# clone machine the local root is in the local-dotfiles clone.
readonly -A TIER_ROOTS=(
  df  "${REPLY}/.config/claude/skills"
  ldf "${LDF_ROOT}"
)
# Each tier's worktree: where its manifests live and submodule paths resolve.
readonly -A TIER_WORKTREES=(
  df  "${REPLY}"
  ldf "${LDF_WORKTREE}"
)
# Each tier's dev-repos manifest (git's ini form: `[repo "<path>"]` blocks with a
# `path =`), the dotfiles CLI's DEV_REPOS; empty for a tier that has none.
readonly -A TIER_DEV_REPOS=(
  df  "${ARI_DOTFILES_DEV_REPOS:-${REPLY}/.config/dotfiles/dev-repos}"
  ldf ""
)

#######################################
# True (0) if the tier name is one of TIERS.
# Arguments:
#   $1 - tier
#######################################
is_valid_tier() {
  local tier="${1}"
  [[ -n "${TIER_ROOTS[${tier}]:-}" ]]
}

#######################################
# Print the real-directory root for a tier.
# Arguments:
#   $1 - tier
#######################################
tier_root() {
  local tier="${1}"
  echo "${TIER_ROOTS[${tier}]}"
}

#######################################
# Print every `path` value one ini file declares under the given section kind,
# one per line; nothing when the file is absent. A file git cannot parse prints
# nothing and logs a warning: its repos' skills would otherwise read as foreign.
# Arguments:
#   $1 - ini file (a dev-repos manifest or a .gitmodules)
#   $2 - section kind (`repo` or `submodule`)
#######################################
ini_paths() {
  local file="${1}" kind="${2}"
  [[ -n "${file}" && -f "${file}" ]] || return 0
  local out exit_code=0
  out="$(git config -f "${file}" --get-regexp "^${kind}\\..*\\.path\$" 2>&1)" || exit_code=$?
  # git config exits 1 when nothing matches: a file with no such section, not a broken one.
  if (( exit_code > 1 )); then
    log::warn "unreadable submodule manifest; its skills are not counted | file='${file}' exit_code='${exit_code}' error='${out%%$'\n'*}'"
    return 0
  fi
  local line
  for line in "${(@f)out}"; do
    [[ "${line}" == *' '?* ]] && echo "${line#* }"
  done
  return 0
}

#######################################
# Print the skills root of every submodule the tier tracks, one per line and
# each once: for each path in the tier's dev-repos manifest, then in its
# worktree's .gitmodules, <worktree>/<path>/skills when that directory exists.
# Nothing when the tier has neither file.
# Arguments:
#   $1 - tier
#######################################
submodule_skill_roots() {
  local tier="${1}"
  local worktree="${TIER_WORKTREES[${tier}]}"
  local -aU sub_paths=(
    "${(@f)$(ini_paths "${TIER_DEV_REPOS[${tier}]}" repo)}"
    "${(@f)$(ini_paths "${worktree}/.gitmodules" submodule)}"
  )
  sub_paths=("${(@)sub_paths:#}")
  local sub_path
  for sub_path in "${sub_paths[@]}"; do
    [[ -d "${worktree}/${sub_path}/skills" ]] && echo "${worktree}/${sub_path}/skills"
  done
  return 0
}

# A tier's roots never change within one run, and the per-skill functions below
# run once per skill (60+): computed once here, they cost no git spawn or fork.
typeset -gA _SKILL_ROOTS_BY_TIER

#######################################
# Set $reply to every directory that may hold the tier's skills: the tier root
# first, then each submodule's skills/. Forks only on the first call per tier.
# Arguments:
#   $1 - tier
#######################################
skill_roots_reply() {
  local tier="${1}"
  if [[ -z "${_SKILL_ROOTS_BY_TIER[${tier}]:-}" ]]; then
    local -a roots=("${TIER_ROOTS[${tier}]}")
    roots+=("${(@f)$(submodule_skill_roots "${tier}")}")
    roots=("${(@)roots:#}")
    _SKILL_ROOTS_BY_TIER[${tier}]="${(F)roots}"
  fi
  reply=("${(@f)_SKILL_ROOTS_BY_TIER[${tier}]}")
}

#######################################
# Print every directory that may hold the tier's skills, one per line: the tier
# root first, then each submodule's skills/.
# Arguments:
#   $1 - tier
#######################################
skill_roots() {
  skill_roots_reply "${1}"
  print -rl -- "${reply[@]}"
}

#######################################
# Print the root under which the tier holds the skill as a real directory, or
# nothing. A tier root beats a submodule root; two roots holding the same
# skill is a conflict skill_state reports.
# Arguments:
#   $1 - tier
#   $2 - skill name
#######################################
skill_holder_root() {
  local tier="${1}" skill="${2}" root
  skill_roots_reply "${tier}"
  for root in "${reply[@]}"; do
    if [[ -d "${root}/${skill}" && ! -L "${root}/${skill}" ]]; then
      echo "${root}"
      return 0
    fi
  done
  return 0
}

#######################################
# Print `submodule:<path>` when the root is a submodule's skills/ directory
# (path relative to the tier worktree), or nothing for a plain tier root.
# Arguments:
#   $1 - tier
#   $2 - root
#######################################
root_source() {
  local tier="${1}" root="${2}"
  local worktree="${TIER_WORKTREES[${tier}]}"
  if [[ "${root}" == "$(tier_root "${tier}")" ]]; then
    echo ""
    return 0
  fi
  local rel="${root#${worktree}/}"
  echo "submodule:${rel%/skills}"
}

#######################################
# True (0) on a clone machine when the machines file lists LDF_MACHINE: the
# name ldf-link assembles ~/.local for. Always true on a bare-repo machine.
#######################################
ldf_machine_known() {
  [[ "${LDF_CLONE}" == true ]] || return 0
  local name rest
  [[ -r "${LDF_WORKTREE}/machines" ]] || return 1
  while read -r name rest; do
    [[ "${name}" == "${LDF_MACHINE}" ]] && return 0
  done < "${LDF_WORKTREE}/machines"
  return 1
}

#######################################
# True (0) when the skill's farm link names ldf-link's per-file links on a clone
# machine (LDF_ASSEMBLED_ROOT/<name>), not the clone's directory: an existing
# file edited through it reaches the clone, a new file lands in ~/.local
# untracked, so `link` retargets it.
# Arguments:
#   $1 - skill name
#######################################
links_via_ldf_link() {
  local skill="${1}" link="${SKILLS_DIR}/${1}"
  [[ "${LDF_CLONE}" == true && -L "${link}" && "${link:A}" == "${LDF_ASSEMBLED_ROOT:A}/${skill}" ]]
}

#######################################
# Run git against a tier's repo, via the df/ldf aliases the dotfiles skill
# documents (each picks a clone or a bare repo by the rule above).
# Arguments:
#   $1 - tier
#   $@ - git arguments
#######################################
tier_git() {
  local tier="${1}"; shift
  git "${tier}" "${@}"
}

#######################################
# True (0) if the skill matches a pattern in ${IGNORE_FILE}: downloaded or
# third-party skills that are not ours to adopt. gitignore-ish: blank lines and
# `#` lines skipped; each remaining line is a zsh glob matched against the bare
# skill name (leading `/`, trailing `/`, CR stripped).
# Arguments:
#   $1 - skill name
#######################################
is_skill_ignored() {
  local skill="${1}"
  [[ -f "${IGNORE_FILE}" ]] || return 1
  local line pat
  while IFS= read -r line || [[ -n "${line}" ]]; do
    line="${line%$'\r'}"
    [[ -z "${line}" || "${line}" == \#* ]] && continue
    pat="${line#/}"; pat="${pat%/}"
    [[ "${skill}" == ${~pat} ]] && return 0
  done < "${IGNORE_FILE}"
  return 1
}

#######################################
# True (0) if the directory under SKILLS_DIR is a skill: it holds a SKILL.md.
# Claude Code's own directories (the `synced` bucket) live under the same root
# without one and are never ours to adopt.
# Arguments:
#   $1 - skill name
#######################################
is_skill_dir() {
  local skill="${1}"
  [[ -f "${SKILLS_DIR}/${skill}/SKILL.md" ]]
}

#######################################
# Print why a real directory is ignored: `no-skill-md` when it has no SKILL.md,
# `gitignore` when a .gitignore pattern matches, empty otherwise.
# Arguments:
#   $1 - skill name
#######################################
skill_ignore_reason() {
  local skill="${1}"
  if ! is_skill_dir "${skill}"; then
    echo "no-skill-md"
    return 0
  fi
  if is_skill_ignored "${skill}"; then
    echo "gitignore"
    return 0
  fi
  echo ""
}

#######################################
# Print every tier holding a real directory for the skill under any of its roots
# (tier root or a submodule's skills/), one line per holding root, so a skill
# held twice within one tier shows up twice and reads as a conflict.
# Arguments:
#   $1 - skill name
#######################################
tiers_holding() {
  tiers_holding_reply "${1}"
  if (( ${#reply} > 0 )); then
    print -rl -- "${reply[@]}"
  fi
  return 0
}

#######################################
# tiers_holding into $reply, without a subshell.
# Arguments:
#   $1 - skill name
#######################################
tiers_holding_reply() {
  local skill="${1}" tier root
  local -a roots found=()
  for tier in "${TIERS[@]}"; do
    skill_roots_reply "${tier}"
    roots=("${reply[@]}")
    for root in "${roots[@]}"; do
      [[ -d "${root}/${skill}" && ! -L "${root}/${skill}" ]] && found+=("${tier}")
    done
  done
  reply=("${found[@]}")
  return 0
}

#######################################
# Classify one skill. Prints `<state> <tier>` and leaves the same in $REPLY, so
# a caller looping over every skill can read it without a subshell; tier is `-`
# when none applies.
#   linked    symlink into a tier root, or on a clone machine into ldf-link's
#             per-file links (LDF_ASSEMBLED_ROOT) to a held skill
#             (healthy; the latter: fix: link, which retargets it)
#   missing   tier holds it, no symlink in SKILLS_DIR      (fix: link)
#   dangling  symlink whose target is gone, or on a clone machine names
#             per-file links no clone directory backs      (fix: link --prune)
#   foreign   symlink pointing outside every tier root     (manual)
#   shadowed  real dir in SKILLS_DIR AND a tier holds it   (manual)
#   conflict  more than one tier holds it                  (manual)
#   ignored   real dir without SKILL.md, or matched by .gitignore  (leave)
#   unlinked  real dir in SKILLS_DIR, no tier holds it     (fix: adopt)
#   absent    nowhere
# Arguments:
#   $1 - skill name
#######################################
skill_state() {
  local skill="${1}"
  tiers_holding_reply "${skill}"
  skill_state_of "${skill}" "${SKILLS_DIR}/${skill}" "${reply[@]}"
  print -r -- "${REPLY}"
}

#######################################
# skill_state's classification, given what it gathered, into $REPLY. No
# subshell on any path a linked skill takes.
# Arguments:
#   $1 - skill name
#   $2 - the symlink path in SKILLS_DIR
#   $@ - tiers holding a real directory for the skill
#######################################
skill_state_of() {
  local skill="${1}" link="${2}"; shift 2
  local -a holders=("${@}")

  if (( ${#holders} > 1 )); then
    REPLY="conflict ${(j:,:)holders}"
    return 0
  fi

  if [[ -L "${link}" ]]; then
    if [[ ! -e "${link}" ]]; then
      REPLY="dangling -"
      return 0
    fi
    local target tier root
    local -a roots
    target="${link:A}"
    for tier in "${TIERS[@]}"; do
      skill_roots_reply "${tier}"
      roots=("${reply[@]}")
      for root in "${roots[@]}"; do
        if [[ "${target}" == "${root:A}/${skill}" ]]; then
          REPLY="linked ${tier}"
          return 0
        fi
      done
    done
    # On a clone machine, ldf-link's per-file links to a skill the clone holds
    # are that skill (links_via_ldf_link marks the row); with none behind them
    # they are a leftover of a skill gone from the clone, as good as gone.
    if [[ "${LDF_CLONE}" == true && "${target}" == "${LDF_ASSEMBLED_ROOT:A}/${skill}" ]]; then
      [[ "${holders[*]}" == ldf ]] && REPLY="linked ldf" || REPLY="dangling -"
      return 0
    fi
    REPLY="foreign -"
    return 0
  fi

  if [[ -d "${link}" ]]; then
    if (( ${#holders} == 1 )); then
      REPLY="shadowed ${holders[1]}"
      return 0
    fi
    if [[ -n "$(skill_ignore_reason "${skill}")" ]]; then
      REPLY="ignored -"
      return 0
    fi
    REPLY="unlinked -"
    return 0
  fi

  if (( ${#holders} == 1 )); then
    REPLY="missing ${holders[1]}"
    return 0
  fi
  REPLY="absent -"
}

#######################################
# Print the union of skill names across SKILLS_DIR, every tier root and every
# submodule skills/ root, sorted. Only directories and symlinks count; files
# such as README.md do not.
#######################################
list_all_skills() {
  local root entry tier
  local -a roots=("${SKILLS_DIR}")
  for tier in "${TIERS[@]}"; do
    skill_roots_reply "${tier}"
    roots+=("${reply[@]}")
  done
  {
    for root in "${roots[@]}"; do
      [[ -d "${root}" ]] || continue
      for entry in "${root}"/*(N-/) "${root}"/*(N@); do
        echo "${entry:t}"
      done
    done
  } | LC_ALL=C sort -u
}

#######################################
# Fill the roots cache in the sourcing process, so every $(...) subshell the
# scripts open inherits it instead of re-reading the manifests.
#######################################
warm_skill_roots() {
  local tier
  for tier in "${TIERS[@]}"; do
    skill_roots_reply "${tier}"
  done
}
warm_skill_roots
