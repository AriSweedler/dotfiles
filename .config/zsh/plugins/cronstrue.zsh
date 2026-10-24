
function cronny() {
  if ! command -v cronstrue &>/dev/null; then
    log::err "cronstrue not installed"
    return 1
  fi

  cronstrue "$(pbpaste)"
}
