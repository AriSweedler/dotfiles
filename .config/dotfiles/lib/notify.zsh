# dotfiles/lib/notify.zsh — telling the human: verify's data trail and the terminal-notifier banner.
zmodload zsh/datetime

# One line per run in verify.log; grep it for history.
note() {
  local ts
  strftime -s ts '%Y-%m-%d %H:%M:%S' "${NEW_MACHINE_NOW}"
  local line="${ts} [verify] $*"
  mkdir -p "${VERIFY_TRAIL:h}"
  print -r -- "${line}" >> "${VERIFY_TRAIL}"
  log::info "${line}"
}

# hud <message> [seconds=2] [open_url]. seconds 0 leaves the banner up. Fires only under
# launchd (NEW_MACHINE_INVOKED_BY) and without --no-notify; interactive runs get a log line.
# terminal-notifier is addressed by absolute path because launchd's PATH lacks Homebrew;
# post/sleep/-remove gives an exact lifetime, and the remover is synchronous because launchd's
# process-group cleanup would kill a backgrounded one and orphan the banner.
hud() {
  local msg="${1}" seconds="${2:-2}" open_url="${3:-}"
  if [[ -z "${NEW_MACHINE_INVOKED_BY:-}" || "${DOTFILES_NO_NOTIFY:-0}" == 1 ]]; then
    log::info "hud | message='${msg}'"
    return 0
  fi
  if [[ -n "${NEW_MACHINE_NOTIFIER}" ]] && command -v "${NEW_MACHINE_NOTIFIER}" >/dev/null 2>&1; then
    local -a args=(-group "${CLI_NAME}" -title "${CLI_NAME}" -message "${msg}")
    # A file:// click via -open lands in the .md default app (Xcode); route it through the
    # editor-in-tmux-window script instead. The click runs under /bin/sh, hence (q) quoting.
    if [[ "${open_url}" == file://* ]]; then
      local report_file="${open_url#file://}"
      args+=(-execute "${(q)NEW_MACHINE_EDIT_WINDOW} -n ${CLI_NAME} ${(q)report_file}")
    elif [[ -n "${open_url}" ]]; then
      args+=(-open "${open_url}")
    fi
    "${NEW_MACHINE_NOTIFIER}" "${args[@]}" >/dev/null || return 0
    if (( seconds > 0 )); then
      sleep "${seconds}"
      "${NEW_MACHINE_NOTIFIER}" -remove "${CLI_NAME}" >/dev/null || true
    fi
    return 0
  fi
  osascript -e "display notification \"${msg}\" with title \"${CLI_NAME}\"" || true
}
