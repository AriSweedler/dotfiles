# step chrome_exoskeleton — the shared-tier submodule (dotfiles_repo initializes it) has its
# dependencies, which wire its hooks through npm's prepare script, a built dist/, and that
# dist/ (or dist-personal/) loaded unpacked and enabled in at least one Chrome profile. Loading
# it is the one part only a human can do (chrome://extensions, Load unpacked), so it is a manual
# fail. Node comes from the local tier's env.zsh on a work machine; a personal machine needs it
# on PATH, hence a warn, not a fail.
step::declare chrome_exoskeleton --group tools --needs dotfiles_repo \
  --desc "the Chrome Exoskeleton submodule has its dependencies (which wire its hooks), a built dist/, and Chrome loads it, enabled, in at least one profile" \
  --apply "sets the submodule's commit identity, installs its node dependencies when missing (exo deps ci, which wires its hooks) and builds dist/ (exo build)"
step::watches chrome_exoskeleton '.config/chrome-exoskeleton'   # the submodule pointer

step::chrome_exoskeleton::dir() {
  print -r -- "${HOME}/.config/chrome-exoskeleton"
}

step::chrome_exoskeleton::is_node_present() {
  local env_zsh="${XDG_DATA_HOME:-${HOME}/.local/share}/chrome-exoskeleton/env.zsh"
  [[ -r "${env_zsh}" ]] && source "${env_zsh}"
  command -v node >/dev/null 2>&1
}

# step::chrome_exoskeleton::profiles <fw>: reply_loaded and reply_disabled are the display names
# of the Chrome profiles (Local State's profile.info_cache) that load <fw>/dist or
# <fw>/dist-personal unpacked, enabled or not; reply_without is every other profile. Chrome
# keeps an unpacked extension in the profile's Secure Preferences (Preferences on older builds).
# Older builds flag a disabled one with state 0 or a disable_reasons bitmask, newer ones with
# a non-empty disable_reasons list. Reads files only, so it works with Chrome open or closed.
step::chrome_exoskeleton::profiles() {
  local fw="${1}" chrome="${ARI_DOTFILES_CHROME_DIR}" dir name prefs st
  typeset -ga reply_loaded=() reply_disabled=() reply_without=()
  [[ -r "${chrome}/Local State" ]] || return 0
  while IFS=$'\t' read -r dir name; do
    st=none
    for prefs in "${chrome}/${dir}/Secure Preferences" "${chrome}/${dir}/Preferences"; do
      [[ -r "${prefs}" ]] || continue
      st="$(jq -r --arg a "${fw}/dist" --arg b "${fw}/dist-personal" --arg c "${fw:A}/dist" --arg d "${fw:A}/dist-personal" '
        [.extensions.settings // {} | to_entries[].value
          | select((.path? // "") as $p | [$a, $b, $c, $d] | index($p))
          | if (.state == 0)
               or ((.disable_reasons | type) == "number" and .disable_reasons != 0)
               or ((.disable_reasons | type) == "array" and (.disable_reasons | length) > 0)
            then "disabled" else "enabled" end]
        | if index("enabled") then "enabled" elif length > 0 then "disabled" else "none" end' "${prefs}" 2>/dev/null || print -r -- none)"
      [[ "${st}" == none ]] || break
    done
    case "${st}" in
      enabled) reply_loaded+=("${name}") ;;
      disabled) reply_disabled+=("${name}") ;;
      *) reply_without+=("${name}") ;;
    esac
  done < <(jq -r '.profile.info_cache // {} | to_entries[] | [.key, (.value.name // .key)] | @tsv' "${chrome}/Local State" 2>/dev/null)
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
  local version load_fix
  version="$(jq -r .version "${fw}/dist/manifest.json" 2>/dev/null || echo '?')"
  load_fix="open Chrome, chrome://extensions, turn on Developer mode, Load unpacked: ${fw}/dist"
  if [[ ! -r "${ARI_DOTFILES_CHROME_DIR}/Local State" ]]; then
    verdict fail not_loaded -m -d "no Chrome profile found (Chrome never opened, or not installed) | path='${ARI_DOTFILES_CHROME_DIR}'" -f "${load_fix}"
    return 0
  fi
  local -a reply_loaded reply_disabled reply_without
  step::chrome_exoskeleton::profiles "${fw}"
  if (( ! ${#reply_loaded} )); then
    if (( ${#reply_disabled} )); then
      verdict fail disabled -m -d "loaded but turned off in every profile that has it | profiles='${(j:, :)reply_disabled}'" \
        -f "open Chrome, chrome://extensions, turn the Chrome Exoskeleton card on"
    else
      verdict fail not_loaded -m -d "no Chrome profile loads ${fw}/dist | profiles='${(j:, :)reply_without}'" -f "${load_fix}"
    fi
    return 0
  fi
  local -a others=("${reply_without[@]}" "${reply_disabled[@]}")
  local detail="dist version=${version} hooks='${hooks}' loaded in '${(j:, :)reply_loaded}'"
  (( ${#others} )) && detail+=" (not in '${(j:, :)others}')"
  verdict ok built -d "${detail}"
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
