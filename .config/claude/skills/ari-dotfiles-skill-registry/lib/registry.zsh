#!/usr/bin/env zsh
# Shared constants and skill classification for the registry scripts. Source it;
# do not execute. Callers source ari-skill-shellscripts/lib/logging.zsh first.
#
# Skills are versioned in the dotfiles, one real directory per tier root, and
# ${HOME}/.claude/skills/<name> is a symlink into whichever tier owns the skill.

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
# Print every tier whose root holds a real directory for the skill, one per line.
# Arguments:
#   $1 - skill name
#######################################
tiers_holding() {
  local skill="${1}" tier
  for tier in "${TIERS[@]}"; do
    [[ -d "$(tier_root "${tier}")/${skill}" && ! -L "$(tier_root "${tier}")/${skill}" ]] && echo "${tier}"
  done
  return 0
}

#######################################
# Classify one skill. Prints `<state> <tier>`; tier is `-` when none applies.
#   linked    symlink into a tier root                     (healthy)
#   missing   tier holds it, no symlink in SKILLS_DIR      (fix: link)
#   dangling  symlink whose target is gone                 (fix: link --prune)
#   foreign   symlink pointing outside every tier root     (manual)
#   shadowed  real dir in SKILLS_DIR AND a tier holds it   (manual)
#   conflict  more than one tier holds it                  (manual)
#   ignored   real dir matched by .gitignore               (leave)
#   unlinked  real dir in SKILLS_DIR, no tier holds it     (fix: adopt)
#   absent    nowhere
# Arguments:
#   $1 - skill name
#######################################
skill_state() {
  local skill="${1}"
  local link="${SKILLS_DIR}/${skill}"
  local -a holders
  holders=("${(@f)$(tiers_holding "${skill}")}")
  holders=("${(@)holders:#}")

  if (( ${#holders} > 1 )); then
    echo "conflict ${(j:,:)holders}"
    return 0
  fi

  if [[ -L "${link}" ]]; then
    if [[ ! -e "${link}" ]]; then
      echo "dangling -"
      return 0
    fi
    local target tier
    target="${link:A}"
    for tier in "${TIERS[@]}"; do
      if [[ "${target}" == "$(tier_root "${tier}")/${skill}" ]]; then
        echo "linked ${tier}"
        return 0
      fi
    done
    echo "foreign -"
    return 0
  fi

  if [[ -d "${link}" ]]; then
    if (( ${#holders} == 1 )); then
      echo "shadowed ${holders[1]}"
      return 0
    fi
    if is_skill_ignored "${skill}"; then
      echo "ignored -"
      return 0
    fi
    echo "unlinked -"
    return 0
  fi

  if (( ${#holders} == 1 )); then
    echo "missing ${holders[1]}"
    return 0
  fi
  echo "absent -"
}

#######################################
# Print the union of skill names across SKILLS_DIR and every tier root, sorted.
# Only directories and symlinks count; files such as README.md do not.
#######################################
list_all_skills() {
  local root entry
  {
    for root in "${SKILLS_DIR}" "${(@v)TIER_ROOTS}"; do
      [[ -d "${root}" ]] || continue
      for entry in "${root}"/*(N-/) "${root}"/*(N@); do
        echo "${entry:t}"
      done
    done
  } | LC_ALL=C sort -u
}
