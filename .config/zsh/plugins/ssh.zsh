function ssh-conf() {
  local -r base="$HOME/.ssh/conf.d"
  # shellcheck disable=SC2012
  local -r file="$(ls -1 "$base" | fzf)"
  "$EDITOR" "$base/$file"
}

# Show the machine dashboard
function machines() {
  b_echo "~~~"
  b_echo "machines"
  # When we get to the 'Host' start looking for the Hostname
  awk '
    prev_filename != FILENAME {
      prev_filename = FILENAME
      if (first == "no") {
        print ""
      } else {
        first = "no"
      }
      print "\t " FILENAME
    }
    /Host / {host=$2}
    /Host[nN]ame / {hostname=$2}
    host && hostname {
      print host " - " hostname
      host=""
      hostname=""
    }
  ' "$HOME/.ssh/conf.d/"*
  b_echo "~~~"
}

function ssh::load_agent() {
  local auth_socket="$HOME/.ssh/ssh_auth_sock"

  # Always point SSH_AUTH_SOCK at the fixed symlink so every shell (and
  # ForwardAgent) uses the same path regardless of session ordering.
  export SSH_AUTH_SOCK="$auth_socket"
  [ -S "$auth_socket" ] && return

  # Apple's launchd ssh-agent (/usr/bin/ssh-agent) cannot perform FIDO2
  # signing operations. Explicitly start Homebrew's agent.
  eval "$(/opt/homebrew/bin/ssh-agent -s)" &>/dev/null
  ln -sf "$SSH_AUTH_SOCK" "$auth_socket"
  export SSH_AUTH_SOCK="$auth_socket"

  ssh-add -l &> /dev/null && return
  for id in "$HOME"/.ssh/*id*; do
    ssh-add "$id" 2&>/dev/null
  done
}
ssh::load_agent
