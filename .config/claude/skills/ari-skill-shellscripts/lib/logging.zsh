#!/usr/bin/env zsh
# Canonical logging for skill zsh scripts: a shim over the dotfiles' one log library,
# ~/.config/zsh/plugins/log.zsh (tiers, run_cmd, knobs: see its header). Source it; do not
# execute. The mandatory script preamble is in /ari-skill-shellscripts § Logging:
#
#   readonly SKILLS_DIR="${HOME}/.claude/skills"
#   source "${SKILLS_DIR}/ari-skill-shellscripts/lib/logging.zsh"
#
# Skill output is read back by an LLM, so the '[ts] [caller]' preamble is off here whatever
# stderr is; everything else is the shared lib as is.
[[ -n "${_ARI_LOGGING_ZSH:-}" ]] && return 0
readonly _ARI_LOGGING_ZSH=1
LOG_PREAMBLE=0
_ari_log_lib="${XDG_CONFIG_HOME:-${HOME}/.config}/zsh/plugins/log.zsh"
if [[ ! -r "${_ari_log_lib}" ]]; then
  print -u2 "[ERROR] missing shared logging lib | path='${_ari_log_lib}'"
  return 1
fi
source "${_ari_log_lib}"
unset _ari_log_lib
