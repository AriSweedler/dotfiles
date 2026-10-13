# step claude — Claude Code installed.
step::declare claude --group tools --desc "Claude Code installed"

typeset -g CLAUDE_INSTALLER="https://claude.ai/install.sh"

check::claude() {
  local claude_path
  if ! claude_path="$(command -v claude 2>/dev/null)"; then
    verdict fail claude_missing -d "claude not on PATH" -f "${CLI_NAME} apply claude"
    return 0
  fi
  # The version is the binary's: reuse it while the resolved file is the same one.
  local version CACHE_REPLY CACHE_HIT=0
  step::claude::version "${claude_path}"
  version="${CACHE_REPLY}"
  local detail="version='${version}' path='${claude_path}'"
  (( ! CACHE_HIT )) || detail+=$'\n'"cached: true | of='version' bin='${claude_path:A}'"
  verdict ok present -d "${detail}"
}

# CACHE_REPLY: `claude --version`, from the state dir while the binary's fingerprint holds.
step::claude::version() {
  local bin="${1}" REPLY CACHE_RACY file="${ARI_DOTFILES_STATE_DIR}/cache/claude.version"
  cache::fingerprint "${bin:A}"
  local fp="${REPLY}"
  if cache::enabled && [[ -r "${file}" ]] && [[ "${${mapfile[${file}]}%%$'\n'*}" == "${fp//$'\n'/ }" ]]; then
    CACHE_REPLY="${${mapfile[${file}]}#*$'\n'}"
    CACHE_HIT=1
    return 0
  fi
  CACHE_REPLY="$(claude --version 2>/dev/null || true)"
  if (( ! CACHE_RACY )) && [[ -n "${CACHE_REPLY}" ]]; then
    mkdir -p "${file:h}" && mapfile[${file}]="${fp//$'\n'/ }"$'\n'"${CACHE_REPLY}"
  fi
  return 0
}

apply::claude() {
  run_mut zsh -c 'curl -fsSL "$1" | sh' _ "${CLAUDE_INSTALLER}"
}
