# dotfiles/cmd/alttab.zsh — `dotfiles alttab`: the Free-tier AltTab built from source. The build and
# the certificate are ~/.config/alttab/bin's scripts; this verb runs them the one way init will not:
# making the signing certificate, which asks for an admin password in a macOS dialog. `edit`
# (cmd/alttab/edit.zsh) changes free.patch.

verb::define alttab 'build, sign and install the Free-tier AltTab'
verb::usage alttab 'alttab install [--dry-run] [--no-launch]' 'alttab status'
verb::about alttab <<'EOF'
The alttab step checks for the patched AltTab; init rebuilds it when Xcode
is ready and the certificate exists, but runs no sudo and makes no
certificate, so a machine short of either is told to run 'alttab install'.
Sources: $(help::tilde "${HOME}/.config/alttab") (README.md has the whole story).
Needs the Xcode app from the App Store; Command Line Tools alone cannot
build a macOS app.
EOF
verb::sub alttab install "get Xcode ready (select it, accept its license, install its first-launch packages; each a sudo command, named first), create the local signing certificate 'AltTab Free Local' if it is missing (macOS asks for an admin password once to trust it), then clone, patch, build, sign, replace /Applications/AltTab.app, pin its updater to manual and open it; then run the alttab check"
verb::sub alttab status "the alttab step's check"
verb::edit alttab alttab::edit_cmd '[--header] [--no-commit]' \
  'open the files free.patch changes in \$EDITOR, in the clone the build keeps ($(help::tilde "${XDG_CACHE_HOME:-${HOME}/.cache}/alttab-free/src")); on save free.patch becomes its header plus "git diff HEAD" there. It must apply to a clean checkout of free.patch.ref, and its "What it changes" list must name every file it touches; then it is committed (shared tier). A save that fails is kept for the next edit. Refuses during an unfinished "alttab-free-build --rebase-patch", and when the clone is missing, at another ref or carries other changes. Pro stays locked except shortcut slot 2 (AGENTS.md). Builds nothing: run "alttab install" next'
verb::flag alttab '--dry-run' "install: print the build's plan, change nothing" --for install
verb::flag alttab '--no-launch' 'install: do not open AltTab afterwards' --for install
verb::flag alttab '--header' 'edit: open free.patch itself (its header names each file it changes); prints the change as a diff' --for edit
verb::flag alttab '--no-commit' 'edit: put free.patch in place, leave it uncommitted' --for edit

cmd_alttab() {
  local -A opts; local -a args
  verb::parse alttab "$@"
  (( ${+opts[--edit]} )) && { alttab::edit_cmd "${@:#--edit}"; return; }
  local sub="${args[1]:-}"
  [[ -n "${sub}" ]] || usage_error "alttab needs a subcommand | known='install status edit'"
  source "${ARI_DOTFILES_STEPS}/alttab.zsh" || return 3
  step::alttab::paths
  case "${sub}" in
    install)
      (( ${#args} == 1 )) || usage_error "alttab install takes no arguments | args='${args[*]:1}'"
      alttab::install ;;
    status)
      (( ${#args} == 1 )) || usage_error "alttab status takes no arguments | args='${args[*]:1}'"
      cmd_healthcheck --only alttab ;;
    *) usage_error "alttab: unknown subcommand | sub='${sub}' known='install status edit'" ;;
  esac
}

# alttab::edit_cmd ARGS: `alttab edit`, with the step's paths it needs.
alttab::edit_cmd() {
  source "${ARI_DOTFILES_STEPS}/alttab.zsh" || return 3
  step::alttab::paths
  need_lib "${ARI_DOTFILES_CMD}/alttab/edit.zsh" || return 3
  alttab::edit "$@"
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

# alttab::install: the caller's opts (--dry-run, --no-launch) passed to the build.
alttab::install() {
  local -a build_args=()
  local dry=${+opts[--dry-run]}
  (( dry )) && { build_args+=(--dry-run); export ARI_DOTFILES_DRY_RUN=1; }
  (( ${+opts[--no-launch]} )) && build_args+=(--no-launch)
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
