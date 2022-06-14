function ssh-conf() {
  local -r base="$HOME/.ssh/conf.d"
  # shellcheck disable=SC2012
  local -r file="$(ls -1 "$base" | fzf)"
  vim "$base/$file"
}

# Invoke ssh on any machine in my config.
#
# Example:
#
#     shsh -- ls
#
# This will run fzf to select a machine & then 'ssh <machine> ls' on it
function shsh() {
  # Parse args.
  # Everything before '--' is a --query to fzf.
  # Everything after is the command to run.
  local query="" arg
  while arg="$1" && shift 1 &>/dev/null; do
    [[ "$arg" == "--" ]] && break
    query="$query$arg "
  done

  # If there's no command, do not allow multiple machines to be selected
  local multi="--multi"
  [ -z "$*" ] && multi="--no-multi"

  # Invoke fzf
  local -r sshable_machines="$(awk '/Host / {print $2}' "$HOME/.ssh/conf.d/"*)"
  local -r selected="$(echo "$sshable_machines" | fzf $multi --query "$query")"

  # Invoke the command for each selected machine. If there's no command, we
  # just open up a shell
  log_info "You selected: '$selected'"

  while read machine; do
    if (( $# == 0 )); then
      log_err "TODO fix this bug 'vim:///Users/arisweedler/.local/zsh-init/ssh.zsh:38'"
      ssh -n "$machine"
    else
      log_info "On machine '$machine', running command '$*'"
      ssh "$machine" /bin/bash <<< "$@"
      echo
    fi
  done <<< "$selected"
}

# Show the machine dashboard
function machines() {
  b-echo "~~~"
  pushd "$HOME/workspace/hawkeye-tools/output" || exit
  b-echo "Vagrant folders"
  ls -1
  b-echo "machines"
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
  popd &>/dev/null || exit
  b-echo "~~~"
}

