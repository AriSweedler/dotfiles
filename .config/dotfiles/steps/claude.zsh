# step claude — Claude Code installed.
step::declare claude --group tools --desc "Claude Code installed"

typeset -g CLAUDE_INSTALLER="https://claude.ai/install.sh"

check::claude() {
  local claude_path
  if ! claude_path="$(command -v claude 2>/dev/null)"; then
    verdict fail claude_missing -d "claude not on PATH" -f "${CLI_NAME} apply claude"
    return 0
  fi
  local version
  version="$(claude --version 2>/dev/null || true)"
  verdict ok present -d "version='${version}' path='${claude_path}'"
}

apply::claude() {
  run_mut zsh -c 'curl -fsSL "$1" | sh' _ "${CLAUDE_INSTALLER}"
}
