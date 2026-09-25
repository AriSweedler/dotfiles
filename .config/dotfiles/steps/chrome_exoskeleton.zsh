# step chrome_exoskeleton — the shared-tier submodule (dotfiles_repo initializes it) has its
# dependencies, which wire its hooks through npm's prepare script, and a built dist/ for
# Chrome to load. Node comes from the local tier's env.zsh on a work machine; a personal
# machine needs it on PATH, hence a warn, not a fail.
step::declare chrome_exoskeleton --group tools --needs dotfiles_repo \
  --desc "the Chrome Exoskeleton submodule has its dependencies (which wire its hooks) and a built dist/"

step::chrome_exoskeleton::dir() {
  print -r -- "${HOME}/.config/chrome-exoskeleton"
}

step::chrome_exoskeleton::is_node_present() {
  local env_zsh="${XDG_DATA_HOME:-${HOME}/.local/share}/chrome-exoskeleton/env.zsh"
  [[ -r "${env_zsh}" ]] && source "${env_zsh}"
  command -v node >/dev/null 2>&1
}

check::chrome_exoskeleton() {
  local fw
  fw="$(step::chrome_exoskeleton::dir)"
  if [[ ! -x "${fw}/bin/exo" ]]; then
    verdict skip no_submodule -d "framework not checked out | path='${fw}'" -f "${CLI_NAME} apply dotfiles_repo"
    return 0
  fi
  if ! step::chrome_exoskeleton::is_node_present; then
    verdict warn node_missing -d "node is not on PATH and no env.zsh provides it" -f "brew install node   (or set it up in ~/.local/share/chrome-exoskeleton/env.zsh)" -m
    return 0
  fi
  if ! tier::is_submodule_identity_ok "${fw}"; then
    verdict fail identity_drift -d "local user.name/user.email are not the personal identity" -f "${CLI_NAME} apply chrome_exoskeleton"
    return 0
  fi
  local hooks
  hooks="$(git -C "${fw}" config core.hooksPath 2>/dev/null || true)"
  if [[ ! -d "${fw}/node_modules" || "${hooks}" != ".githooks" ]]; then
    verdict fail deps_missing -d "node_modules='$([[ -d "${fw}/node_modules" ]] && echo present || echo missing)' hooksPath='${hooks:-unset}'" -f "${CLI_NAME} apply chrome_exoskeleton"
    return 0
  fi
  if [[ ! -f "${fw}/dist/manifest.json" ]]; then
    verdict fail not_built -d "no dist/manifest.json | path='${fw}/dist'" -f "${CLI_NAME} apply chrome_exoskeleton"
    return 0
  fi
  verdict ok built -d "dist version=$(jq -r .version "${fw}/dist/manifest.json" 2>/dev/null || echo '?') hooks='${hooks}'"
}

apply::chrome_exoskeleton() {
  local fw
  fw="$(step::chrome_exoskeleton::dir)"
  if [[ ! -x "${fw}/bin/exo" ]]; then
    log::err "framework not checked out | path='${fw}' fix='${CLI_NAME} apply dotfiles_repo'"
    return 1
  fi
  if ! step::chrome_exoskeleton::is_node_present; then
    log::warn "node is not on PATH; skipping | fix='brew install node, or ~/.local/share/chrome-exoskeleton/env.zsh'"
    return 0
  fi
  tier::submodule_identity_apply "${fw}" || return 1
  if [[ ! -d "${fw}/node_modules" || "$(git -C "${fw}" config core.hooksPath 2>/dev/null)" != ".githooks" ]]; then
    run_mut zsh "${fw}/bin/exo" deps ci || return 1
  fi
  run_mut zsh "${fw}/bin/exo" build
}
