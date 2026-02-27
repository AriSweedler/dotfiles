autoload -Uz add-zsh-hook

function python_sourcer() {
  # Exit early if we're not entering a dir with a venv
  local venv_activate_script="./venv/bin/activate"
  ! [ -f "${venv_activate_script}" ] && return

  # If we're already in a VIRTUAL_ENV, log a warning
  if [ -n "${VIRTUAL_ENV}" ]; then
    log::warn "Already in VIRTUAL_ENV | VIRTUAL_ENV='${VIRTUAL_ENV}'"
  fi

  # Source it, and an optional `.env` file
  run_cmd source "${venv_activate_script}"
  for f in ".env" ".env.local"; do
    ! [ -f "${f}" ] && continue
    run_cmd source "${f}"
  done

}

add-zsh-hook chpwd python_sourcer
