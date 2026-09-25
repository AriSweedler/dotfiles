# dotfiles/lib/logging.zsh — the one log library plus the two zsh plugins the push logs need.
# All three ship in the shared tier's checkout, so they resolve before any skill is linked.
LIB_LOGGING="${HOME}/.config/zsh/plugins/log.zsh"
readonly LIB_LOGGING
if [[ ! -r "${LIB_LOGGING}" ]]; then
  print -u2 "[ERROR] missing shared logging lib | path='${LIB_LOGGING}'"
  exit 1
fi
source "${LIB_LOGGING}"
source "${HOME}/.config/zsh/plugins/log_rotate.zsh"
source "${HOME}/.config/zsh/plugins/strip_ansi.zsh"   # the push logs are plain text
