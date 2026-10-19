# dotfiles/cmd/alttab.zsh — `dotfiles alttab`: the Free-tier AltTab built from source. The build and
# the certificate are ~/.config/alttab/bin's scripts; this verb runs them the one way init will not:
# making the signing certificate, which asks for an admin password in a macOS dialog.

help_alttab() {
  cat <<EOF
build, sign and install the Free-tier AltTab

${c_bold}Usage${c_rst}
  ${DF} alttab install [--dry-run] [--no-launch]
  ${DF} alttab status

  The alttab step checks for the patched AltTab; init rebuilds it when the
  certificate exists, but never creates the certificate, so a machine without
  one is told to run 'alttab install'. Sources: $(help::tilde "${HOME}/.config/alttab")
  (README.md has the whole story).

${c_bold}Subcommands${c_rst}
  install   create the local signing certificate 'AltTab Free Local' if it is
            missing (macOS asks for an admin password once to trust it), then
            clone, patch, build, sign, replace /Applications/AltTab.app, pin
            its updater to manual and open it; then run the alttab check
  status    the alttab step's check

${c_bold}Flags${c_rst}
  --dry-run    install: print the build's plan, change nothing
  --no-launch  install: do not open AltTab afterwards

  Needs full Xcode (not only Command Line Tools), selected with xcode-select.
EOF
}

cmd_alttab() {
  local sub="${1:-}"
  [[ -n "${sub}" ]] || usage_error "alttab needs a subcommand | known='install status'"
  shift
  source "${ARI_DOTFILES_STEPS}/alttab.zsh" || return 3
  step::alttab::paths
  case "${sub}" in
    install) alttab::install "$@" ;;
    status)
      (( $# == 0 )) || usage_error "alttab status takes no arguments | args='$*'"
      cmd_healthcheck --only alttab
      ;;
    *) usage_error "alttab: unknown subcommand | sub='${sub}' known='install status'" ;;
  esac
}

alttab::install() {
  local -a build_args=()
  local dry=0
  while (( $# )); do
    case "${1}" in
      --dry-run) dry=1; build_args+=(--dry-run) ;;
      --no-launch) build_args+=(--no-launch) ;;
      *) usage_error "alttab install: bad flag | flag='${1}'" ;;
    esac
    shift
  done
  if [[ "${OSTYPE}" != darwin* ]]; then
    log::err "AltTab is macOS only"
    return 1
  fi
  if [[ ! -x "${ALTTAB_DIR}/bin/alttab-free-build" ]]; then
    log::err "the AltTab sources are missing | dir='${ALTTAB_DIR}' fix='${CLI_NAME} pull'"
    return 1
  fi
  if ! step::alttab::has_xcode; then
    log::err "building AltTab needs full Xcode, not only Command Line Tools | selected='$(xcode-select -p 2>/dev/null || print -r -- none)'"
    log::err "install Xcode from the App Store, then | fix='sudo xcode-select -s /Applications/Xcode.app && sudo xcodebuild -license accept'"
    return 1
  fi
  if ! step::alttab::has_cert; then
    if (( dry )); then
      ui::paint grey "the build will create the signing certificate '${ALTTAB_IDENTITY}' first (one admin password dialog)"
    else
      ui::paint warn "Creating the signing certificate '${ALTTAB_IDENTITY}': macOS will ask for your admin password once, to trust it for code signing. Rebuilds reuse it, so AltTab keeps its Accessibility and Screen Recording grants."
    fi
  fi
  # The build script makes the certificate when it is missing, then builds and installs.
  zsh "${ALTTAB_DIR}/bin/alttab-free-build" "${build_args[@]}" || return $?
  (( dry )) && return 0
  cmd_healthcheck --only alttab
}
