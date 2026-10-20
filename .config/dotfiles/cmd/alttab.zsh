# dotfiles/cmd/alttab.zsh — `dotfiles alttab`: the Free-tier AltTab built from source. The build and
# the certificate are ~/.config/alttab/bin's scripts; this verb runs them the one way init will not:
# making the signing certificate, which asks for an admin password in a macOS dialog. `edit`
# (cmd/alttab/edit.zsh) changes free.patch.

help_alttab() {
  cat <<EOF
build, sign and install the Free-tier AltTab

${c_bold}Usage${c_rst}
  ${DF} alttab install [--dry-run] [--no-launch]
  ${DF} alttab status
  ${DF} alttab edit [--header] [--no-commit]     (also: alttab --edit)

  The alttab step checks for the patched AltTab; init rebuilds it when Xcode
  is ready and the certificate exists, but runs no sudo and makes no
  certificate, so a machine short of either is told to run 'alttab install'.
  Sources: $(help::tilde "${HOME}/.config/alttab") (README.md has the whole story).

${c_bold}Subcommands${c_rst}
  install   get Xcode ready (select it, accept its license, install its
            first-launch packages; each a sudo command, named first), create
            the local signing certificate 'AltTab Free Local' if it is missing
            (macOS asks for an admin password once to trust it), then clone,
            patch, build, sign, replace /Applications/AltTab.app, pin its
            updater to manual and open it; then run the alttab check
  status    the alttab step's check
  edit      open the files free.patch changes in \$EDITOR, in the build's
            clone ($(help::tilde "${XDG_CACHE_HOME:-${HOME}/.cache}/alttab-free/src")); on save free.patch becomes its
            header plus the clone's 'git diff HEAD'. It must apply to a clean
            checkout of free.patch.ref, and its "What it changes" list must
            name every file it touches; then it is committed (shared tier).
            Pro stays locked except shortcut slot 2 (AGENTS.md). Builds
            nothing: run 'alttab install' next

${c_bold}Flags${c_rst}
  --dry-run    install: print the build's plan, change nothing
  --no-launch  install: do not open AltTab afterwards
  --edit       the other spelling of edit
  --header     edit: open free.patch itself (its header names each file it
               changes); prints the change as a diff
  --no-commit  edit: put free.patch in place, leave it uncommitted

  Needs the Xcode app from the App Store; Command Line Tools alone cannot
  build a macOS app.
EOF
}

cmd_alttab() {
  local sub="${1:-}"
  [[ -n "${sub}" ]] || usage_error "alttab needs a subcommand | known='install status edit'"
  shift
  source "${ARI_DOTFILES_STEPS}/alttab.zsh" || return 3
  step::alttab::paths
  case "${sub}" in
    install) alttab::install "$@" ;;
    edit|--edit)
      need_lib "${ARI_DOTFILES_CMD}/alttab/edit.zsh" || return 3
      alttab::edit "$@"
      ;;
    status)
      (( $# == 0 )) || usage_error "alttab status takes no arguments | args='$*'"
      cmd_healthcheck --only alttab
      ;;
    *) usage_error "alttab: unknown subcommand | sub='${sub}' known='install status edit'" ;;
  esac
}

# What a setup command is for, before it runs; a dry run says it would.
alttab::_say() { if is_dry_run; then ui::paint grey "would: ${1}"; else ui::paint warn "${1}"; fi; }

# alttab::ready_xcode: the Xcode app selected, its license accepted and its first-launch packages
# installed, each with one sudo command named before it runs (one password prompt; sudo caches it).
# The app itself is the App Store's to install. Dry run: the commands, none run.
alttab::ready_xcode() {
  local REPLY last=""
  local -a cmd
  while step::alttab::xcode_state; [[ "${REPLY}" != ok ]]; do
    if [[ "${REPLY}" == "${last}" ]] && ! is_dry_run; then
      log::err "Xcode is still not ready after the fix | state='${REPLY}' cmd='${cmd[*]}'"
      return 1
    fi
    case "${REPLY}" in
      none)
        log::err "building AltTab needs the Xcode app, not only Command Line Tools, and none is installed | app='${XCODE_APP}'"
        log::err "install it, then run this again | fix=\"open 'macappstores://apps.apple.com/app/id497799835' (or: mas install 497799835)\""
        return 1 ;;
      not_selected) cmd=(sudo xcode-select -s "${XCODE_APP}"); alttab::_say "Selecting ${XCODE_APP} for builds (xcode-select points at $(xcode-select -p 2>/dev/null || print -r -- nothing))" ;;
      license) cmd=(sudo xcodebuild -license accept); alttab::_say "Accepting the Xcode license" ;;
      first_launch) cmd=(sudo xcodebuild -runFirstLaunch); alttab::_say "Installing Xcode's first-launch packages (a new or updated Xcode needs them to build)" ;;
    esac
    print -r -- "  ${cmd[*]}"
    if is_dry_run; then
      # Nothing changes in a dry run, so the next state is unknown: the rest of the plan is shown unchecked.
      case "${REPLY}" in
        not_selected) print -r -- "  sudo xcodebuild -license accept   (if not accepted yet)"; print -r -- "  sudo xcodebuild -runFirstLaunch   (if needed)" ;;
        license) print -r -- "  sudo xcodebuild -runFirstLaunch   (if needed)" ;;
      esac
      return 0
    fi
    "${cmd[@]}" || { log::err "Xcode setup command failed | cmd='${cmd[*]}'"; return 1; }
    last="${REPLY}"
  done
  return 0
}

alttab::install() {
  local -a build_args=()
  local dry=0
  while (( $# )); do
    case "${1}" in
      --dry-run) dry=1; build_args+=(--dry-run); export ARI_DOTFILES_DRY_RUN=1 ;;
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
  alttab::ready_xcode || return 1
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
