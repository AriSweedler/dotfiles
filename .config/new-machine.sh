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

function ensure_brew() {
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
    ffmpeg
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
    goland

    # Lang: Java
    jenv
    intellij-idea

    # Lang: misc
    lua
    lua-language-server
    python
    node
    shellcheck
    visual-studio-code

    # Containers
    docker
    helm

    # Mac customization
    raycast
    karabiner-elements
    bartender
    homerow

    # Personal
    spotify
  )

  # TODO: Suppress the warning errors if packages are already installed
  run_cmd brew install "${pkgs[@]}"
}

function terminal_settings() {
  # Now that we have a nerdfont installed, set it
  log::warn "You will need to manually set an installed nerdfont as a default font | installed_nerdfont='font-caskaydia-mono-nerd-font
'"
}

# Ensure we have crucial programs installed
function main() {
  ensure_brew
  ensure_brew_pkgs
  terminal_settings
}

main "$@"
