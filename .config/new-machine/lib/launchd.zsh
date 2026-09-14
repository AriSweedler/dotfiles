# The weekly `new-machine verify` launchd job. Requires common.zsh to be sourced first for the
# NEW_MACHINE_* paths, log::* and nm::is_dry_run. Side-effect-free at source time.
#
# Public contract:
#   launchd::label                   com.<id -un>.new-machine-verify
#   launchd::plist_path              <NEW_MACHINE_LAUNCH_AGENTS_DIR>/<label>.plist
#   launchd::render_plist            the plist XML on stdout (jq → plutil); what install writes,
#                                    byte for byte, so weekly_verify can diff it against the file
#   launchd::install   [--dry-run]   write + lint + bootout/bootstrap; idempotent
#   launchd::uninstall [--dry-run]   bootout + rm -f
#   launchd::is_loaded               rc 0 iff launchctl knows the job
#   launchd::status                  state / last exit code / runs, then last_result.json and last-ok
# Dry-run: the flag or NM_DRY_RUN=1 logs every mutation instead of running it and writes nothing.

launchd::label()       { print -r -- "com.$(id -un).new-machine-verify"; }
launchd::plist_path()  { print -r -- "${NEW_MACHINE_LAUNCH_AGENTS_DIR}/$(launchd::label).plist"; }
launchd::_domain()     { print -r -- "gui/$(id -u)"; }

# Truthy on --dry-run among the args or the CLI's exported NM_DRY_RUN.
launchd::_dry_run() {
  local arg
  for arg in "$@"; do
    if [[ "${arg}" == --dry-run ]]; then return 0; fi
  done
  nm::is_dry_run
}

launchd::render_plist() {
  local label state_dir="${NEW_MACHINE_STATE_DIR}"
  label="$(launchd::label)"
  jq -n --arg label "${label}" --arg script "${HOME}/.config/new-machine/bin/new-machine" \
        --arg out "${state_dir}/launchd.out.log" --arg err "${state_dir}/launchd.err.log" \
        --arg path "${HOME}/.local/bin:/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin" '{
    Label: $label,
    ProgramArguments: ["/bin/zsh", $script, "verify"],
    StartCalendarInterval: {Weekday: 1, Hour: 10, Minute: 5},
    RunAtLoad: false, ProcessType: "Background", LowPriorityIO: true,
    EnvironmentVariables: {PATH: $path, HOMEBREW_NO_AUTO_UPDATE: "1", HOMEBREW_NO_ANALYTICS: "1",
                           HOMEBREW_NO_ENV_HINTS: "1", HOMEBREW_NO_INSTALL_CLEANUP: "1",
                           GIT_TERMINAL_PROMPT: "0", GIT_OPTIONAL_LOCKS: "0", NO_COLOR: "1",
                           NEW_MACHINE_INVOKED_BY: "launchd"},
    StandardOutPath: $out, StandardErrorPath: $err }' | plutil -convert xml1 - -o -
}

launchd::install() {
  local label plist state_dir="${NEW_MACHINE_STATE_DIR}" domain
  label="$(launchd::label)"
  plist="$(launchd::plist_path)"
  domain="$(launchd::_domain)"
  if launchd::_dry_run "$@"; then
    log::info "dry-run, would write plist and bootstrap | plist='${plist}' label='${label}'"
    return 0
  fi
  # launchd creates the log files but not their directory.
  mkdir -p "${plist:h}" "${state_dir}"
  launchd::render_plist > "${plist}.tmp"
  if ! plutil -lint -s "${plist}.tmp"; then
    log::err "rendered plist failed lint | path='${plist}.tmp'"
    return 1
  fi
  mv -f "${plist}.tmp" "${plist}"
  launchctl bootout "${domain}/${label}" 2>/dev/null || true
  launchctl bootstrap "${domain}" "${plist}"
  log::info "installed launchd job | label='${label}' schedule='Monday 10:05' plist='${plist}'"
}

launchd::uninstall() {
  local label plist domain
  label="$(launchd::label)"
  plist="$(launchd::plist_path)"
  domain="$(launchd::_domain)"
  if launchd::_dry_run "$@"; then
    log::info "dry-run, would bootout and remove plist | plist='${plist}' label='${label}'"
    return 0
  fi
  launchctl bootout "${domain}/${label}" 2>/dev/null || true
  rm -f "${plist}"
  log::info "uninstalled launchd job | label='${label}' plist='${plist}'"
}

launchd::is_loaded() {
  launchctl print "$(launchd::_domain)/$(launchd::label)" >/dev/null 2>&1
}

launchd::status() {
  local label plist state_dir="${NEW_MACHINE_STATE_DIR}" out
  label="$(launchd::label)"
  plist="$(launchd::plist_path)"
  print -r -- "label:  ${label}"
  if [[ -f "${plist}" ]]; then
    print -r -- "plist:  ${plist}"
  else
    print -r -- "plist:  ${plist} (missing)"
  fi
  if out="$(launchctl print "$(launchd::_domain)/${label}" 2>/dev/null)"; then
    print -r -- "loaded: yes"
    print -r -- "${out}" | grep -E '^[[:space:]]*(state|last exit code|runs) = ' || true
  else
    print -r -- "loaded: no"
  fi
  print -r -- ""
  print -r -- "last_result.json (${state_dir}/last_result.json):"
  if [[ -f "${state_dir}/last_result.json" ]]; then
    jq . "${state_dir}/last_result.json"
  else
    print -r -- "  (none)"
  fi
  if [[ -f "${state_dir}/last-ok" ]]; then
    print -r -- "last-ok: $(<"${state_dir}/last-ok")"
  else
    print -r -- "last-ok: (none)"
  fi
}
