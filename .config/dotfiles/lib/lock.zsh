# dotfiles/lib/lock.zsh — one run at a time for the verbs that write RUN_DIR and state
# (healthcheck, setup, apply, verify). push, init and pull never take it. The caller installs
# `trap lock::release EXIT`.
zmodload zsh/datetime
zmodload -F zsh/stat b:zstat

typeset -g LOCK_DIR="${NEW_MACHINE_STATE_DIR}/lock.d"
typeset -g LOCK_HELD=0

# verify.log is verify's data trail (one line per verify run); interactive runs only log.
lock::trail() {
  if [[ "${1}" == verify ]] && (( ${+functions[note]} )); then note "${2}"; else log::warn "${2}"; fi
}

# lock::acquire <mode>: exits 4 while a live, young holder has it; a stale or dead holder is taken over.
lock::acquire() {
  local mode="${1}"
  mkdir -p "${NEW_MACHINE_STATE_DIR}"
  if ! mkdir "${LOCK_DIR}" 2>/dev/null; then
    local pid=""
    if [[ -s "${LOCK_DIR}/pid" ]]; then
      pid="$(<"${LOCK_DIR}/pid")"
    fi
    if [[ -n "${pid}" ]] && kill -0 "${pid}" 2>/dev/null; then
      local -i age
      age=$(( EPOCHSECONDS - $(zstat +mtime "${LOCK_DIR}") ))
      if (( age <= NEW_MACHINE_LOCK_MAX_AGE_SECS )); then
        lock::trail "${mode}" "busy | pid='${pid}' age='${age}'"
        hud "${CLI_NAME}: skipped, another run holds the lock" 3
        exit 4
      fi
      lock::trail "${mode}" "stale lock taken over | pid='${pid}' age='${age}'"
    else
      log::info "clearing lock of dead process | pid='${pid:-none}'"
    fi
    rm -rf -- "${LOCK_DIR}"
    mkdir "${LOCK_DIR}"
  fi
  print -r -- "$$" > "${LOCK_DIR}/pid"
  LOCK_HELD=1
}

lock::release() {
  (( LOCK_HELD )) || return 0
  if [[ -f "${LOCK_DIR}/pid" && "$(<"${LOCK_DIR}/pid")" == "$$" ]]; then
    rm -rf -- "${LOCK_DIR}"
  fi
  LOCK_HELD=0
}

# Sourced at top level by the entrypoint (and by every step subprocess, where the lock is never
# held), so this is the shell's EXIT trap: a run that ends by `exit` still releases its lock.
trap 'lock::release' EXIT
