# step chrome_exoskeleton — the dev repo checkout (dotfiles_repo clones it) has its
# dependencies, which wire its hooks through npm's prepare script, a built dist/, and that
# dist/ (or dist-personal/) loaded unpacked and enabled in at least one Chrome profile. Loading
# it is the one part only a human can do (chrome://extensions, Load unpacked), so it is a manual
# fail, which init at a terminal offers to walk through (assist::). Node comes from the local
# tier's env.zsh on a work machine; a personal machine needs it on PATH, hence a warn, not a fail.
step::declare chrome_exoskeleton --group tools --needs dotfiles_repo \
  --desc "the Chrome Exoskeleton checkout has its dependencies (which wire its hooks), a built dist/, and Chrome loads it, enabled, in at least one profile" \
  --apply "sets the checkout's commit identity, installs its node dependencies when missing (exo deps ci, which wires its hooks) and builds dist/ (exo build)" \
  --assist "when no profile loads it: asks y/N, then opens chrome://extensions, reveals dist/ in Finder and waits for the load"
step::watches chrome_exoskeleton '.config/dotfiles/nix/flake.lock'   # where its input is locked

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

#######################################
# Whether some Chrome profile loads the framework's dist/, enabled.
# Arguments: fw: the framework checkout
# Returns: 0 when one does, 1 otherwise
#######################################
step::chrome_exoskeleton::is_loaded() {
  local fw="${1}"
  local -a reply_loaded reply_disabled reply_without
  step::chrome_exoskeleton::profiles "${fw}"
  (( ${#reply_loaded} > 0 ))
}

#######################################
# await::until's probe for the load: success once a profile loads it, else the human's turn.
# Arguments: fw: the framework checkout; todo: what the human still has to do
# Outputs: one `<state> <message>` line on stdout
#######################################
step::chrome_exoskeleton::load_probe() {
  local fw="${1}" todo="${2}"
  if step::chrome_exoskeleton::is_loaded "${fw}"; then
    print -r -- "success Chrome loads the Chrome Exoskeleton"
    return 0
  fi
  print -r -- "user your turn: ${todo} · Ctrl-C to stop waiting"
}

#######################################
# The question and the instruction for the human, by what the profiles show: a card that is
# loaded but turned off needs only its switch; otherwise it needs Load unpacked.
# Globals: reply_disabled (read; step::chrome_exoskeleton::profiles fills it)
# Arguments: fw: the framework checkout
# Outputs: the question, then the instruction, one per line
#######################################
step::chrome_exoskeleton::assist_text() {
  local fw="${1}"
  if (( ${#reply_disabled} > 0 )); then
    log::info "chrome_exoskeleton: loaded but turned off | profiles='${(j:, :)reply_disabled}'"
    print -r -- "Turn the Chrome Exoskeleton on in Chrome now?"
    print -r -- "in chrome://extensions, turn the Chrome Exoskeleton card on"
    return 0
  fi
  log::info "chrome_exoskeleton: no profile loads it | dist='${fw}/dist'"
  print -r -- "Load the Chrome Exoskeleton into Chrome now?"
  print -r -- "in chrome://extensions, turn on Developer mode, click Load unpacked, pick $(ui::paths "${fw}/dist") (Finder shows it)"
}

#######################################
# Make a tab in the front Chrome window (a new window when none is open) and point it at <url>
# through Chrome's AppleScript dictionary. `open` hands Chrome a URL as an outside link, and
# Chrome does not open its own chrome:// pages from one; a tab's URL set by script it does.
# The first run asks to let the terminal control Google Chrome (Privacy & Security › Automation).
# Arguments: url: what the tab loads
# Outputs: the tab's URL as Chrome reports it a second later, on stdout
# Returns: osascript's exit code
#######################################
step::chrome_exoskeleton::chrome_new_tab() {
  local url="${1}"
  osascript - "${url}" <<'EOF'
on run argv
  tell application "Google Chrome"
    activate
    if (count of windows) is 0 then
      make new window
      set new_tab to active tab of front window
      set URL of new_tab to (item 1 of argv)
    else
      set new_tab to make new tab at end of tabs of front window with properties {URL:(item 1 of argv)}
    end if
    delay 1
    return URL of new_tab
  end tell
end run
EOF
}

#######################################
# Open chrome://extensions in Chrome and check that the tab landed there.
# Returns: 0 when the new tab shows the extensions page, 1 otherwise (logged with the manual fix)
#######################################
step::chrome_exoskeleton::open_extensions_tab() {
  local tab_url exit_code=0
  tab_url="$(step::chrome_exoskeleton::chrome_new_tab "chrome://extensions" 2>&1)" || exit_code=$?
  if (( exit_code != 0 )); then
    log::warn "chrome_exoskeleton: Chrome refused the scripted tab | exit_code='${exit_code}' error='${tab_url}' fix='allow the terminal to control Google Chrome (System Settings › Privacy & Security › Automation), or type chrome://extensions into Chrome'"
    return 1
  fi
  if [[ "${tab_url}" != chrome://extensions* ]]; then
    log::warn "chrome_exoskeleton: the new tab is not the extensions page | tab_url='${tab_url}' fix='type chrome://extensions into Chrome'"
    return 1
  fi
  log::info "chrome_exoskeleton: opened the extensions page | tab_url='${tab_url}'"
}

#######################################
# Show the human where to act: chrome://extensions in Chrome, and dist/ in Finder unless the
# card is already loaded (then only its switch is missing). A failure to open either is logged
# and the wait goes on: the instruction on the await line names both places.
# Globals: reply_disabled (read)
# Arguments: fw: the framework checkout
#######################################
step::chrome_exoskeleton::open_extensions_page() {
  local fw="${1}"
  if (( ${#reply_disabled} == 0 )); then
    open -R "${fw}/dist" || log::warn "chrome_exoskeleton: could not reveal dist in Finder | dist='${fw}/dist'"
  fi
  step::chrome_exoskeleton::open_extensions_tab || true
}

#######################################
# The one manual part, walked through when init meets it at a terminal: asks y/N; on y opens
# chrome://extensions (and dist/ in Finder), then waits, on the await line, until a profile
# loads it enabled; Chrome writes its prefs within seconds of the click. N moves on.
# Globals: ARI_DOTFILES_CONFIG, ARI_DOTFILES_ASSIST_WAIT_SECS, CLI_NAME (read)
# Returns: 0 once Chrome loads it (the runner re-checks); 1 on N, Ctrl-C or the deadline
#######################################
assist::chrome_exoskeleton() {
  local fw
  fw="$(step::chrome_exoskeleton::dir)"
  if [[ ! -f "${fw}/dist/manifest.json" ]]; then
    log::warn "chrome_exoskeleton: dist is not built; nothing to load | dist='${fw}/dist'"
    return 1
  fi
  local -a reply_loaded reply_disabled reply_without
  step::chrome_exoskeleton::profiles "${fw}"
  local -a text=("${(@f)$(step::chrome_exoskeleton::assist_text "${fw}")}")
  if ! ui::confirm "${text[1]}"; then
    log::info "chrome_exoskeleton: not now | fix='${CLI_NAME} init again, or Load unpacked ${fw}/dist by hand'"
    return 1
  fi
  need_lib "${ARI_DOTFILES_CONFIG}/claude/skills/ari-skill-shellscripts/lib/await.zsh" || return 1
  step::chrome_exoskeleton::open_extensions_page "${fw}"
  local exit_code=0
  await::until --interval 1 --timeout "${ARI_DOTFILES_ASSIST_WAIT_SECS}" -- \
    step::chrome_exoskeleton::load_probe "${fw}" "${text[2]}" || exit_code=$?
  if (( exit_code != 0 )); then
    log::warn "chrome_exoskeleton: stopped waiting; Chrome does not load it yet | exit_code='${exit_code}' fix='${CLI_NAME} init again once it is loaded'"
    return 1
  fi
  log::info "chrome_exoskeleton: Chrome loads it"
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
