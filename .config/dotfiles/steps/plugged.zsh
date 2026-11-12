# step plugged — the plugged dev repo checkout (dotfiles_repo clones it): hooks and the
# personal identity are plain local config a fresh checkout lacks. The binary on PATH is Nix's
# (pkgs/plugged, built by `dotfiles switch`); bin/plugged-dev keeps the edit-and-run loop.
step::declare plugged --group tools --needs dotfiles_repo \
  --desc "the plugged checkout has its hooks wired (core.hooksPath=.githooks), and Nix's plugged is on PATH" \
  --apply "sets the checkout's commit identity and core.hooksPath=.githooks"
step::watches plugged '.config/dotfiles/nix/flake.lock'   # where its input is locked

step::plugged::dir() {
  print -r -- "${HOME}/.config/plugged"
}

# Where home-manager installs the plugged that pkgs/plugged builds.
step::plugged::binary() {
  print -r -- "/etc/profiles/per-user/${USER}/bin/plugged"
}

check::plugged() {
  local dir
  dir="$(step::plugged::dir)"
  if [[ ! -x "${dir}/bin/plugged" ]]; then
    verdict skip no_submodule -d "plugged not checked out | path='${dir}'" -f "${CLI_NAME} apply dotfiles_repo"
    return 0
  fi
  if ! tier::is_submodule_identity_ok "${dir}"; then
    verdict fail identity_drift -d "local user.name/user.email are not the personal identity" -f "${CLI_NAME} apply plugged"
    return 0
  fi
  local hooks
  hooks="$(git -C "${dir}" config core.hooksPath 2>/dev/null || true)"
  if [[ "${hooks}" != ".githooks" ]]; then
    verdict fail hooks_unwired -d "hooksPath='${hooks:-unset}'" -f "${CLI_NAME} apply plugged"
    return 0
  fi
  local binary
  binary="$(step::plugged::binary "${dir}")"
  if [[ ! -x "${binary}" ]]; then
    verdict fail not_built -d "Nix's plugged is not installed | path='${binary}'" -f "${CLI_NAME} switch"
    return 0
  fi
  verdict ok built -d "hooks='${hooks}' binary='${binary}'"
}

apply::plugged() {
  local dir
  dir="$(step::plugged::dir)"
  if [[ ! -x "${dir}/bin/plugged" ]]; then
    log::err "plugged not checked out | path='${dir}' fix='${CLI_NAME} apply dotfiles_repo'"
    return 1
  fi
  tier::submodule_identity_apply "${dir}" || return 1
  if [[ "$(git -C "${dir}" config core.hooksPath 2>/dev/null)" != ".githooks" ]]; then
    run_mut git -C "${dir}" config core.hooksPath .githooks || return 1
  fi
}
