# notify_badge — this machine's unread notifications (~/.config/bin/notify) as NOTIFY_UNREAD,
# for the prompt's (N) (starship's env_var.NOTIFY_UNREAD, dotfiles/nix/starship.nix). Set
# before each prompt by a glob of the unread markers: no process. Unset at 0, since starship
# prints "()" for a variable that is set but empty.
autoload -Uz add-zsh-hook

function _notify_badge_precmd() {
  local -a unread=( "${XDG_STATE_HOME:-${HOME}/.local/state}"/notify/unread/*(N.) )
  if (( ${#unread} )); then
    export NOTIFY_UNREAD="${#unread}"
    return 0
  fi
  unset NOTIFY_UNREAD
}

add-zsh-hook precmd _notify_badge_precmd
