function f1() {
  # Parse args
  local minutes
  minutes="${1:-1}"

  # Validate args
  if (( minutes <= 0 )); then
    log::err "Bad argument. Give a positive number | arg='$1'"
    return 1
  fi

  # Do work
  log::info "Finding all non-hidden files that are less than '$minutes' minutes old"
  find . -newermt "$minutes minute ago" -type f | grep -v "\/\."
}

# Edit the file that a shell function is defined in
function vifxn() {
  local -r func_name="${1:?}"
  if ! type "$func_name" | grep -q "shell function"; then
    log::err "Function does not exist | func_name='$func_name'"
    log::warn "type $func_name='$(type "$func_name")'"
    return 1
  fi

  # Parse the file
  local file
  file="$(type -a "$func_name" | awk '{print $NF}')"

  # Open the file and try jumping to the function with a search command
  vi +"/$func_name() {" "$file"
}
