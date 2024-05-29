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
    # Shells
    bash
    zsh

    # Unix
    awk
    coreutils
    curl
    git
    watch
    wget

    # Nice CLI utilities
    bat
    fd
    ffmpeg
    font-caskaydia-mono-nerd-font
    fzf
    jq
    neovim
    ripgrep
    tmux
    tmuxinator
    tree
    yq

    # Mac customization
    hammerspoon
    monitorcontrol
    rectangle
    starship

    # Languages and tools
    go
    lua
    node
    python
    shellcheck
  )

  # TODO: Suppress the warning errors if packages are already installed
  run_cmd brew install "${pkgs[@]}"
}

# Ensure we have crucial programs installed
function main() {
  ensure_brew
  ensure_brew_pkgs
}

main "$@"
