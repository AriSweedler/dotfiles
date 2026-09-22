# dotfiles/lib/logging.zsh — the shared logging library plus the two zsh plugins the push logs
# need. The one module with source-time work; it resolves its paths from $HOME alone, so it
# needs no other module first (see README.md).
#
# Bootstrap: before `dotfiles init` has linked the skills, ~/.claude/skills is empty and the
# only reachable copy of the logging lib is the shared tier's own under ~/.config.
LIB_LOGGING="${HOME}/.claude/skills/ari-skill-shellscripts/lib/logging.zsh"
[[ -r "${LIB_LOGGING}" ]] || LIB_LOGGING="${HOME}/.config/claude/skills/ari-skill-shellscripts/lib/logging.zsh"
readonly LIB_LOGGING
if [[ ! -r "${LIB_LOGGING}" ]]; then
  print -u2 "[ERROR] missing shared logging lib | path='${LIB_LOGGING}'"
  exit 1
fi
source "${LIB_LOGGING}"
source "${HOME}/.config/zsh/plugins/log_rotate.zsh"
source "${HOME}/.config/zsh/plugins/strip_ansi.zsh"   # the push logs are plain text
