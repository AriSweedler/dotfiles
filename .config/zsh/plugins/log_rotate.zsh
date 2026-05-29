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

# log_init [name] [keep=4] — set $LOG_FILE for a per-script log and rotate the
# previous run aside (via log_rotate) instead of truncating, so each run is
# preserved. Call once at the start of a script; later writes append to
# $LOG_FILE. keep defaults to 4, so the current log plus 4 backups = 5 runs.
#
# Each script gets its own directory — ${dir}/<name>/log.txt — so a script's
# log and its rotated .bak.N backups stay grouped together, making successive
# runs easy to correlate.
#
#   name  defaults to this script ($ZSH_ARGZERO) — robust inside functions,
#         where $0 is the function name. The dir is named `name` with its
#         directory and extension stripped.
#   dir   $LOG_DIR if set, else /tmp.
#
# Pass an explicit name for a log not tied to the script filename.
function log_init() {
  emulate -L zsh
  local name="${1:-$ZSH_ARGZERO}"
  local keep="${2:-4}"
  typeset -g LOG_FILE="${LOG_DIR:-/tmp}/${name:t:r}/log.txt"
  log_rotate "${LOG_FILE}" "${keep}"
}
