#!/bin/bash

# The classic log suite
c_red='\e[31m'
c_green='\e[32m'
c_yellow='\e[33m'
c_rst='\e[0m'

preamble() { echo -n "[$(date "+%Y-%m-%dT%T.000Z")] [${BASH_SOURCE[2]}]" ; }
log::err() { printf "${c_red}[ERROR] $(preamble)${c_rst} $*\n" >&2 ; }
log::info() { printf "${c_green}[INFO] $(preamble)${c_rst} $*\n" >&2 ; }
log::warn() { printf "${c_yellow}[WARN] $(preamble)${c_rst} $*\n" >&2 ; }
run_cmd() { log::info "$@"; "$@" && return; rc=$?; log::err "cmd '$*' failed: $rc"; return $rc ; }

# Multiline log (no preamble per line)
log::WARN() ( preamble(){ :; }; (while IFS= read -r line; do log::warn  "| $line"; done <<< "$*") ; )

function ensure_brew() {
  if command -v brew &>/dev/null; then
    log::info "Brew is installed"
    return
  fi

  log::warn "Brew is not installed"
  log::info "Installing brew"
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  brew tap homebrew/autoupdate

  if ! command -v brew &>/dev/null; then
    log::err "Failed to install brew"
    return 1
  fi
}

function ensure_brew_pkgs() {
  # Formulae and casks are mixed — brew install handles both.
  # Commented-out packages were deliberately excluded; don't uncomment without asking.
  # Work-specific tools (bazelisk, awscli, spr, etc.) are installed separately.
  local pkgs=(
    # Unix essentials
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
    font-caskaydia-mono-nerd-font  # cask — Nerd Font for terminal
    fzf
    git-delta
    jq
    ripgrep
    starship  # shell prompt
    tmux
    tmuxinator
    tmuxinator-completion
    tree
    yq

    # Lang: Shells
    bash
    zsh
    zsh-vi-mode

    # Lang: Go
    go
    gopls  # Go language server
    # goland

    # Lang: Java
    jenv
    # intellij-idea

    # Editor
    bob  # nvim version manager — ensure_bob_neovim installs neovim via bob

    # Lang: misc
    lua
    lua-language-server
    tree-sitter
    tree-sitter-cli
    pipx
    uv       # fast Python package manager
    python
    # node   # managed by company tooling; karabiner bake needs npm from it
    shellcheck
    terraform-ls  # Terraform language server
    # visual-studio-code

    # Data
    redis

    # Infra
    kubectx    # kx/knx — quick k8s context/namespace switching
    kubectl
    terraform

    # Personal (casks)
    1password-cli
    karabiner-elements
    raycast
    spotify
  )

  local pkg_installed
  pkg_installed=$(echo; brew list --formula; brew list --cask; echo)

  local pkg_already_installed=() pkg_to_install=()
  for pkg in "${pkgs[@]}"; do
    if [[ "$pkg_installed" == *$'\n'"$pkg"$'\n'* ]]; then
      pkg_already_installed+=("${pkg}")
    else
      pkg_to_install+=("${pkg}")
    fi
  done

  if ((${#pkg_already_installed[@]})); then
    log::info "Already installed (${#pkg_already_installed[@]}/${#pkgs[@]})"
  fi

  if ((${#pkg_to_install[@]})); then
    run_cmd brew install "${pkg_to_install[@]}"
  else
    log::info "All requested packages are already installed."
  fi
}

function ensure_claude() {
  if command -v claude &>/dev/null; then
    log::info "Claude Code is already installed | version='$(claude --version)'"
    return
  fi
  log::info "Installing Claude Code"
  curl -fsSL https://claude.ai/install.sh | sh
}

function ensure_bob_neovim() {
  if ! command -v bob &>/dev/null; then
    log::err "bob not installed, can't install neovim"
    return 1
  fi
  if bob ls | grep -q "Used"; then
    log::info "Neovim already installed via bob"
    return
  fi
  run_cmd bob install latest
  run_cmd bob use latest
}

function ensure_terminal_nerdfont() {
  local installed_nerdfonts
  if ! installed_nerdfonts="$(brew list --cask | grep nerd-font)"; then
    log::err "No Nerd Fonts installed via Homebrew"
    return 1
  fi

  # Nerd Font installed; now set it as the default font in your terminal. This
  # must be done manually.
  log::WARN "⚠️ Manual step required:
set a Nerd Font as your default terminal font:
  * Terminal.app: Go to Preferences → Profiles → Text → Font
  * iTerm2: Go to Preferences → Profiles → Text → Change Font

Installed nerdfonts:
$(printf "  • %s\n" "${installed_nerdfonts}")
"
}

function ensure_karabiner() {
  if ! command -v npm &>/dev/null; then
    log::warn "npm not installed, skipping karabiner bake"
    return
  fi
  "$HOME/.config/karabiner/bin/bake"
}

# Ensure we have crucial programs installed
function main() {
  ensure_brew || return 1
  ensure_brew_pkgs
  ensure_bob_neovim
  ensure_claude
  ensure_terminal_nerdfont
  ensure_karabiner
}

main "$@"
