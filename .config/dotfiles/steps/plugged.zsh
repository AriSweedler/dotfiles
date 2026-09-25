# step plugged — the shared-tier Swift submodule (dotfiles_repo initializes it): hooks and the
# personal identity are plain local config a fresh checkout lacks; the release build needs the
# Xcode command line tools.
step::declare plugged --group tools --needs dotfiles_repo \
  --desc "the plugged submodule has its hooks wired (core.hooksPath=.githooks) and a built release binary"

step::plugged::dir() {
  print -r -- "${HOME}/.config/plugged"
}

# Where bin/plugged's build lands: the shared Swift cache through swift-pkg, else SwiftPM's .build/.
step::plugged::binary() {
  local dir="${1}" swift_pkg="${HOME}/.config/bin/swift-pkg"
  if [[ -x "${swift_pkg}" ]]; then
    zsh "${swift_pkg}" --path "${dir}"
  else
    print -r -- "${dir}/.build/release/plugged"
  fi
}

check::plugged() {
  local dir
  dir="$(step::plugged::dir)"
  if [[ ! -x "${dir}/bin/plugged" ]]; then
    verdict skip no_submodule -d "plugged not checked out | path='${dir}'" -f "${CLI_NAME} apply dotfiles_repo"
    return 0
  fi
  if ! command -v swift >/dev/null 2>&1; then
    verdict warn swift_missing -d "swift is not on PATH" -f "xcode-select --install" -m
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
    verdict fail not_built -d "no release binary | path='${binary}'" -f "${CLI_NAME} apply plugged"
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
  if ! command -v swift >/dev/null 2>&1; then
    log::warn "swift is not on PATH; skipping | fix='xcode-select --install'"
    return 0
  fi
  tier::submodule_identity_apply "${dir}" || return 1
  if [[ "$(git -C "${dir}" config core.hooksPath 2>/dev/null)" != ".githooks" ]]; then
    run_mut git -C "${dir}" config core.hooksPath .githooks || return 1
  fi
  run_mut zsh "${dir}/bin/plugged-dev" build
}
