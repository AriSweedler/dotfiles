# dotfiles/lib/logging.zsh — the one log library plus the two zsh plugins the logs need. All
# three ship in this checkout (DOTFILES_CONFIG from env.zsh; derived here too, so the module
# sources alone), so they resolve before HOME is checked out and before any skill is linked.
: "${DOTFILES_CONFIG:=${${(%):-%x}:A:h:h:h}}"
LIB_LOGGING="${DOTFILES_CONFIG}/zsh/plugins/log.zsh"
if [[ ! -r "${LIB_LOGGING}" ]]; then
  print -u2 "[ERROR] missing shared logging lib | path='${LIB_LOGGING}'"
  exit 1
fi
source "${LIB_LOGGING}"
source "${DOTFILES_CONFIG}/zsh/plugins/log_rotate.zsh"
source "${DOTFILES_CONFIG}/zsh/plugins/strip_ansi.zsh"   # the push and job logs are plain text
