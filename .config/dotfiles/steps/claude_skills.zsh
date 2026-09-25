# step claude_skills — every skill a dotfiles tier holds is symlinked into ~/.claude/skills
# and no link dangles. The registry skill owns the classification; it is addressed by its
# shared-tier path, because on a fresh machine the symlink is exactly what does not exist yet.
step::declare claude_skills --group repo --needs dotfiles_repo \
  --desc "every skill a dotfiles tier holds is symlinked into ~/.claude/skills and no link dangles"

step::claude_skills::registry_bin() {
  print -r -- "${HOME}/.config/claude/skills/ari-dotfiles-skill-registry/bin"
}

check::claude_skills() {
  local bin
  bin="$(step::claude_skills::registry_bin)"
  if [[ ! -r "${bin}/status" ]]; then
    verdict skip no_registry -d "skill registry not checked out | path='${bin}/status'"
    return 0
  fi
  local rows
  rows="$(zsh "${bin}/status" --all 2>/dev/null || true)"
  local -a missing dangling manual
  local line state name linked=0
  for line in "${(f)rows}"; do
    [[ "${line}" == state=* ]] || continue
    state="${${line#state=}%% *}"
    name="${line##*name=}"
    case "${state}" in
      linked) linked=$(( linked + 1 )) ;;
      missing) missing+=("${name}") ;;
      dangling) dangling+=("${name}") ;;
      shadowed|foreign|conflict) manual+=("${name}:${state}") ;;
    esac
  done
  if (( ${#missing} + ${#dangling} > 0 )); then
    verdict fail links_missing -d "missing='${(j:,:)missing}' dangling='${(j:,:)dangling}'" -f "${CLI_NAME} apply claude_skills"
    return 0
  fi
  if (( ${#manual} > 0 )); then
    verdict warn needs_hand -d "${(j:,:)manual}" -f 'zsh $HOME/.claude/skills/ari-dotfiles-skill-registry/bin/status' -m
    return 0
  fi
  verdict ok linked -d "$(plural "${linked}" 'skill linked' 'skills linked')"
}

apply::claude_skills() {
  run_mut zsh "$(step::claude_skills::registry_bin)/link" --prune
}
