# log_rotate — rotate a log file, keeping the N most recent backups.
#
#   log_rotate <logfile> [keep=5]
#
# Call this BEFORE a run writes to <logfile>; it shifts the existing log aside
# so each run is preserved instead of truncated:
#
#   <logfile>              → <logfile>.bak.1
#   <logfile>.bak.1        → <logfile>.bak.2
#   …
#   <logfile>.bak.<keep-1> → <logfile>.bak.<keep>
#   <logfile>.bak.<keep>   → deleted (the oldest)
#
# Net result after the run writes again: the current log plus <keep> backups.
# Creates the parent directory if needed. No-op when <logfile> doesn't exist
# yet (nothing to rotate). Returns non-zero on a bad <keep> or mkdir failure.
function log_rotate() {
  emulate -L zsh
  local logfile="${1:?log_rotate: <logfile> required}"
  local keep="${2:-5}"

  if [[ "${keep}" != <-> ]] || (( keep < 1 )); then
    print -u2 "log_rotate: keep must be a positive integer | got='${keep}'"
    return 1
  fi

  local dir="${logfile:h}"
  [[ -d "${dir}" ]] || mkdir -p "${dir}" || return 1

  # Nothing to rotate until the first log exists.
  [[ -e "${logfile}" ]] || return 0

  # Drop the oldest beyond `keep`, then shift each backup up one slot, newest
  # first so we never clobber a slot we still need.
  rm -f "${logfile}.bak.${keep}"
  local i
  for (( i = keep - 1; i >= 1; i-- )); do
    [[ -e "${logfile}.bak.${i}" ]] && mv -f "${logfile}.bak.${i}" "${logfile}.bak.$(( i + 1 ))"
  done
  mv -f "${logfile}" "${logfile}.bak.1"
}
