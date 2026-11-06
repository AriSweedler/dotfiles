# step terminal_config — Terminal.app's settings: every profile uses Option as the Meta key, so
# Option-p reaches the shell as ESC p (alt-p) instead of typing π. The apply writes through
# cfprefsd (defaults export, plutil, defaults import), which a running Terminal.app picks up;
# writing the plist file directly would be overwritten from cfprefsd's cache.
step::declare terminal_config --group tools \
  --desc "Terminal.app: every profile uses Option as the Meta key (alt-p sends ESC p, not π)" \
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
  local -a reply
  step::terminal_config::missing "${plist}"
  if (( ${#reply} )); then
    verdict fail option_not_meta -d "profiles without Option as Meta: ${(j:, :)reply} | plist='${plist}'" \
      -f "${CLI_NAME} apply terminal_config"
    return 0
  fi
  verdict ok option_is_meta -d "every profile uses Option as Meta | plist='${plist}'"
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
