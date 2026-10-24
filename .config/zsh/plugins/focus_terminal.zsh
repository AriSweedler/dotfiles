# Bring the terminal app this shell runs in back to the front (macOS). Useful
# after a command hands focus to a browser. Works under tmux because
# __CFBundleIdentifier is inherited from the app that started the tmux server.
function focus_terminal() {
  [[ "$OSTYPE" == darwin* ]] || return 0

  local bundle_id="${__CFBundleIdentifier:-}"
  if [[ -z "$bundle_id" ]]; then
    case "${TERM_PROGRAM:-}" in
      Apple_Terminal) bundle_id=com.apple.Terminal ;;
      iTerm.app)      bundle_id=com.googlecode.iterm2 ;;
      WezTerm)        bundle_id=com.github.wez.wezterm ;;
      ghostty)        bundle_id=com.mitchellh.ghostty ;;
      *) log::warn "cannot determine terminal app | TERM_PROGRAM='${TERM_PROGRAM:-}'"; return 1 ;;
    esac
  fi

  osascript -e "tell application id \"${bundle_id}\" to activate" >/dev/null 2>&1
}
