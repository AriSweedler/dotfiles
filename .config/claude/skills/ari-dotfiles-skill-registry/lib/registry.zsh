#!/usr/bin/env zsh
# Shared constants and skill classification for the registry scripts. Source it;
# do not execute. Callers source ari-skill-shellscripts/lib/logging.zsh first.
#
# Skills are versioned in the dotfiles, one real directory per tier root, and
# ${HOME}/.claude/skills/<name> is a symlink into whichever tier owns the skill.
# A tier's git submodules add roots too: every submodule's top-level skills/
# directory holds skills that travel with that submodule (committed in its own
# repo, owned by the tier that holds the submodule).

[[ -n "${_ARI_SKILL_REGISTRY_ZSH:-}" ]] && return 0
readonly _ARI_SKILL_REGISTRY_ZSH=1

# Callers define SKILLS_DIR before sourcing logging; this only fills it for a bare source.
: "${SKILLS_DIR:=${HOME}/.claude/skills}"
readonly IGNORE_FILE="${SKILLS_DIR}/.gitignore"
readonly TIERS=(df ldf)
readonly -A TIER_ROOTS=(
  df  "${HOME}/.config/claude/skills"
  ldf "${HOME}/.local/share/claude-skills"
)
# Each tier's worktree: where its .gitmodules lives and submodule paths resolve.
readonly -A TIER_WORKTREES=(
  df  "${HOME}"
  ldf "${HOME}/.local"
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
# Print the skills root of every submodule the tier tracks, one per line: for
# each path in the tier worktree's .gitmodules, <worktree>/<path>/skills when
# that directory exists. Nothing when the tier has no .gitmodules.
# Arguments:
#   $1 - tier
#######################################
submodule_skill_roots() {
  local tier="${1}"
  local worktree="${TIER_WORKTREES[${tier}]}"
  local modules="${worktree}/.gitmodules"
  [[ -f "${modules}" ]] || return 0
  local key sub_path
  while read -r key sub_path; do
    [[ -n "${sub_path}" ]] || continue
    [[ -d "${worktree}/${sub_path}/skills" ]] && echo "${worktree}/${sub_path}/skills"
  done < <(git config -f "${modules}" --get-regexp '^submodule\..*\.path$' 2>/dev/null)
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
# Run git against a tier's bare repo, via the df/ldf aliases the dotfiles skill
# documents.
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
#   linked    symlink into a tier root                     (healthy)
#   missing   tier holds it, no symlink in SKILLS_DIR      (fix: link)
#   dangling  symlink whose target is gone                 (fix: link --prune)
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
# scripts open inherits it instead of re-reading .gitmodules.
#######################################
warm_skill_roots() {
  local tier
  for tier in "${TIERS[@]}"; do
    skill_roots_reply "${tier}"
  done
}
warm_skill_roots
