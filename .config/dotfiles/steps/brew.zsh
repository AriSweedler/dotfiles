# step brew — Homebrew itself. The one hard prerequisite: when it fails in setup, every later
# group is skipped (`--abort`), because their tools come from it.
step::declare brew --group brew --abort --desc "Homebrew is installed"

typeset -g BREW_INSTALLER="https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh"

check::brew() {
  if [[ -z "${ARI_DOTFILES_BREW}" ]]; then
    verdict fail brew_missing -d "brew not found on PATH or under ${ARI_DOTFILES_BREW_PREFIXES:-<no prefixes>}" \
      -f "${CLI_NAME} apply brew"
    return 0
  fi
  local version
  if ! version="$("${ARI_DOTFILES_BREW}" --version 2>/dev/null)"; then
    verdict fail brew_missing -d "brew not found at ${ARI_DOTFILES_BREW} (--version failed)" -f "${CLI_NAME} apply brew"
    return 0
  fi
  local -a version_lines=("${(f)version}")
  verdict ok present -d "${version_lines[1]} | brew='${ARI_DOTFILES_BREW}'"
}

apply::brew() {
  # NONINTERACTIVE skips the installer's RETURN prompt (its stdout is our log file, so a prompt
  # would look like a hang) but also makes it run `sudo -n`, which aborts on a cold ticket. sudo
  # prompts on /dev/tty, which the watchdog-backgrounded step can still read.
  run_mut sudo -v || return 1
  run_mut zsh -c 'NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL "$1")"' _ "${BREW_INSTALLER}"
}
