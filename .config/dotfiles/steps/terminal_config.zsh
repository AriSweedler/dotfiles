# step terminal_config — Terminal.app's settings: every profile uses Option as the Meta key, so
# Option-p reaches the shell as ESC p (alt-p) instead of typing π. The active profiles (the
# default for new windows and the startup one) are checked by name first: a built-in profile
# that was never edited is not saved in the plist, so the apply cannot set it and the fail is
# manual. The apply writes through cfprefsd (defaults export, plutil, defaults import), which a
# running Terminal.app picks up; writing the plist file directly would be overwritten from
# cfprefsd's cache.
step::declare terminal_config --group tools \
  --desc "Terminal.app: the active profiles, and every other saved one, use Option as the Meta key (alt-p sends ESC p, not π)" \
  --apply "sets useOptionAsMetaKey on every Terminal.app profile through defaults import"
step::watches terminal_config --none "reads Terminal.app's preferences, no repo file"

# step::terminal_config::missing <plist>: reply is each profile under 'Window Settings' whose
# useOptionAsMetaKey is not true. A name with a '.' cannot be a plutil keypath and is left out.
step::terminal_config::missing() {
  local plist="${1}" name value
  typeset -ga reply=()
  local -a names=(${(f)"$(plutil -extract 'Window Settings' raw -o - "${plist}" 2>/dev/null)"})
  for name in "${names[@]}"; do
    [[ "${name}" == *.* ]] && continue
    value="$(plutil -extract "Window Settings.${name}.useOptionAsMetaKey" raw -o - "${plist}" 2>/dev/null || true)"
    [[ "${value}" == (1|true) ]] || reply+=("${name}")
  done
}

# step::terminal_config::active <plist>: reply is the default and startup profile names, unique.
step::terminal_config::active() {
  local plist="${1}" key name
  typeset -gUa reply=()
  for key in 'Default Window Settings' 'Startup Window Settings'; do
    name="$(plutil -extract "${key}" raw -o - "${plist}" 2>/dev/null || true)"
    [[ -n "${name}" ]] && reply+=("${name}")
  done
}

check::terminal_config() {
  local plist="${ARI_DOTFILES_TERMINAL_PLIST}"
  if [[ "${OSTYPE}" != darwin* ]]; then
    verdict skip not_macos -d "Terminal.app is macOS only"
    return 0
  fi
  if ! plutil -extract 'Window Settings' raw -o - "${plist}" >/dev/null 2>&1; then
    verdict skip no_profiles -d "no Terminal.app profiles saved yet; open Terminal.app once, then ${CLI_NAME} apply terminal_config | plist='${plist}'"
    return 0
  fi
  local -a reply active unsaved
  step::terminal_config::active "${plist}"
  active=("${reply[@]}")
  local name
  for name in "${active[@]}"; do
    plutil -extract "Window Settings.${name}" raw -o - "${plist}" >/dev/null 2>&1 || unsaved+=("${name}")
  done
  if (( ${#unsaved} )); then
    verdict fail active_unsaved -m \
      -d "active profile ${(j:, :)unsaved} is a built-in Terminal.app has not saved, so init cannot set it | plist='${plist}'" \
      -f "Terminal.app: Settings -> Profiles -> ${unsaved[1]} -> Keyboard -> tick 'Use Option as Meta key'"
    return 0
  fi
  step::terminal_config::missing "${plist}"
  local -a off=(${reply:*active})
  if (( ${#off} )); then
    verdict fail active_not_meta -d "the active profile does not use Option as Meta: ${(j:, :)off} | plist='${plist}'" \
      -f "${CLI_NAME} apply terminal_config"
    return 0
  fi
  if (( ${#reply} )); then
    verdict fail option_not_meta -d "profiles without Option as Meta: ${(j:, :)reply} | plist='${plist}'" \
      -f "${CLI_NAME} apply terminal_config"
    return 0
  fi
  verdict ok option_is_meta -d "every profile uses Option as Meta; active: ${(j:, :)active:-none} | plist='${plist}'"
}

apply::terminal_config() {
  local plist="${ARI_DOTFILES_TERMINAL_PLIST}" domain="${ARI_DOTFILES_TERMINAL_PLIST%.plist}" name
  local -a reply
  step::terminal_config::missing "${plist}"
  (( ${#reply} )) || return 0
  local tmp
  tmp="$(mktemp)" || return 1
  run_mut defaults export "${domain}" "${tmp}" || { rm -f "${tmp}"; return 1; }
  for name in "${reply[@]}"; do
    run_mut plutil -replace "Window Settings.${name}.useOptionAsMetaKey" -bool true "${tmp}" || { rm -f "${tmp}"; return 1; }
  done
  run_mut defaults import "${domain}" "${tmp}" || { rm -f "${tmp}"; return 1; }
  rm -f "${tmp}"
}
