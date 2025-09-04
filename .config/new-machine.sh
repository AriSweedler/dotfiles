#!/bin/bash

# The classic log suite
c_red='\e[31m'
c_green='\e[32m'
c_yellow='\e[33m'
c_cyan='\e[36m'
c_rst='\e[0m'

preamble() { echo -n "[$(date "+%Y-%m-%dT%T.000Z")] [${BASH_SOURCE[2]}]" ; }
log::err() { printf "${c_red}[ERROR] $(preamble)${c_rst} $*\n" >&2 ; }
log::info() { printf "${c_green}[INFO] $(preamble)${c_rst} $*\n" >&2 ; }
log::warn() { printf "${c_yellow}[WARN] $(preamble)${c_rst} $*\n" >&2 ; }
run_cmd() { log::info "$@"; "$@" && return; rc=$?; log::err "cmd '$*' failed: $rc"; return $rc ; }

# Multiline. You may want to set OTTO_DISABLE_PREAMBLE here.
log::INFO() ( preamble(){ :; }; (while IFS= read -r line; do log::info  "| $line"; done <<< "$*") ; )
log::WARN() ( preamble(){ :; }; (while IFS= read -r line; do log::warn  "| $line"; done <<< "$*") ; )

function ensure_brew() {
  function is_installed() {
    local cmd="${1:?}"
    if which "$cmd" &>/dev/null; then
      return 0
    fi
    return 1
  }

  function install_brew() {
    log::info "Installing brew"
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

    log::info "Tapping all additional thingies"
    brew tap homebrew/autoupdate
  }

  if is_installed brew; then
    log::info "Brew is installed"
    return
  fi

  log::warn "Brew is not installed"
  if ! install_brew; then
    log::err "Failed to install brew. You'll need to fix this yourself"
    return
  fi

  if is_installed brew; then
    log::info "Brew is installed"
    return
  fi
}

function ensure_brew_pkgs() {
  local pkgs=(
    # Unix
    awk
    coreutils
    curl
    git
    watch
    wget

    # Nicer CLI
    bat
    fd
    # ffmpeg
    font-caskaydia-mono-nerd-font
    fzf
    git-delta
    jq
    neovim
    ripgrep
    starship
    tmux
    tmuxinator
    tree
    yq

    # Lang: Shells
    bash
    zsh
    zsh-vi-mode

    # Lang: Go
    go
    # goland

    # Lang: Java
    jenv
    # intellij-idea

    # Lang: misc
    lua
    # lua-language-server
    # python@3.13
    # node
    shellcheck
    # visual-studio-code

    # Containers
    docker
    helm
    kubectl

    # Personal
    # karabiner-elements
    spotify
  )

  echo "brew install ${pkgs[*]}"
  return

  # TODO: FIX ALL THIS
  # Get all currently installed formulae + casks
  local pkg_installed
  pkg_installed=$(echo; brew list --formula; brew list --cask; echo)

  # Figure which packages are already installed and which we need to install
  local pkg_already_installed pkg_to_install
  for pkg in "${pkgs[@]}"; do
    if [[ "$pkg_installed" != *$'\n'"$pkg"$'\n'* ]]; then
      pkg_to_install+=("${pkg}")
    else
      pkg_already_installed+=("${pkg}")
    fi
  done

  # Install and log
  (
    preamble() { :; }

    if ((${#pkg_already_installed[@]})); then
      log::INFO "Already installed packages (${#pkg_already_installed}/${#pkgs}):
$(printf "  • %s\n" ${pkg_already_installed})
"
    fi

    if ((${#pkg_to_install[@]})); then
      run_cmd brew install "${pkg_to_install[@]}"
    else
      log::INFO "✅ All requested packages are already installed."
    fi
  )
}

function set_terminal_nerdfont() {
  local installed_nerdfonts
  if ! installed_nerdfonts="$(brew list --cask | grep nerd-font)"; then
    log::ERR "❌ No Nerd Fonts installed via Homebrew!"
    return 1
  fi

  # Nerd Font installed; now set it as the default font in your terminal. This
  # must be done manually.
  log::WARN "⚠️ Manual step required:
set a Nerd Font as your default terminal font:
  * Terminal.app: Go to Preferences → Profiles → Text → Font
  * iTerm2: Go to Preferences → Profiles → Text → Change Font

Installed nerdfonts:
$(printf "  • %s\n" ${installed_nerdfonts})
"
}

function set_karabiner() {
  "$HOME/.config/karabiner/bin/bake"
}

# Ensure we have crucial programs installed
function main() {
  ensure_brew
  ensure_brew_pkgs
  # set_terminal_nerdfont
  # set_karabiner
}

main "$@"
