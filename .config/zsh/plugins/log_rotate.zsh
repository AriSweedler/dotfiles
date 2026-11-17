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
#
# Exec-free: mkdir/mv/rm are the zsh/files builtins. A rotation is up to six of
# them, and where process spawns are slow (~17 ms each) that adds up —
# this runs at the top of every Karabiner binding and every tmux-oneshot launch.
zmodload -F zsh/files b:zf_mkdir b:zf_mv b:zf_rm 2>/dev/null || {
  function zf_mkdir() { command mkdir "$@" }
  function zf_mv() { command mv "$@" }
  function zf_rm() { command rm "$@" }
}
function log_rotate() {
  emulate -L zsh
  local logfile="${1:?log_rotate: <logfile> required}"
  local keep="${2:-5}"

  if [[ "${keep}" != <-> ]] || (( keep < 1 )); then
    print -u2 "log_rotate: keep must be a positive integer | got='${keep}'"
    return 1
  fi

  local dir="${logfile:h}"
  [[ -d "${dir}" ]] || zf_mkdir -p "${dir}" || return 1

  # Nothing to rotate until the first log exists.
  [[ -e "${logfile}" ]] || return 0

  # Drop the oldest beyond `keep`, then shift each backup up one slot, newest
  # first so we never clobber a slot we still need.
  zf_rm -f "${logfile}.bak.${keep}"
  local i
  for (( i = keep - 1; i >= 1; i-- )); do
    [[ -e "${logfile}.bak.${i}" ]] && zf_mv -f "${logfile}.bak.${i}" "${logfile}.bak.$(( i + 1 ))"
  done
  zf_mv -f "${logfile}" "${logfile}.bak.1"
}

# log_rotate_at_size <logfile> <max_bytes> [files=3] — rotate <logfile> only once it has grown
# to <max_bytes>, keeping <files> files in all: the live one plus <files>-1 backups. For a log
# that one long-lived writer appends to (where log_rotate's once-per-run shift does not fit):
# with max_bytes=10M and files=3, the newest 20-30 MB are always on disk. No-op while the file
# is missing or under the cap. Exec-free: the size is zsh/stat's zstat.
zmodload -F zsh/stat b:zstat 2>/dev/null
function log_rotate_at_size() {
  emulate -L zsh
  local logfile="${1:?log_rotate_at_size: <logfile> required}"
  local max_bytes="${2:?log_rotate_at_size: <max_bytes> required}"
  local files="${3:-3}"

  if [[ "${max_bytes}" != <-> ]] || (( max_bytes < 1 )); then
    print -u2 "log_rotate_at_size: max_bytes must be a positive integer | got='${max_bytes}'"
    return 1
  fi
  if [[ "${files}" != <-> ]] || (( files < 2 )); then
    print -u2 "log_rotate_at_size: files counts the live file, so it is at least 2 | got='${files}'"
    return 1
  fi
  [[ -e "${logfile}" ]] || return 0

  local -a size
  zstat -A size +size -- "${logfile}" || return 1
  (( size[1] >= max_bytes )) || return 0
  log_rotate "${logfile}" $(( files - 1 ))
}

# log_append_capped <logfile> <max_bytes> <files> <line>.. — append each <line> to <logfile>,
# rotating it first when it has reached <max_bytes> (log_rotate_at_size). Creates the parent
# directory if needed.
function log_append_capped() {
  emulate -L zsh
  local logfile="${1:?log_append_capped: <logfile> required}"
  local max_bytes="${2:?log_append_capped: <max_bytes> required}" files="${3:?log_append_capped: <files> required}"
  shift 3
  [[ -d "${logfile:h}" ]] || zf_mkdir -p "${logfile:h}" || return 1
  log_rotate_at_size "${logfile}" "${max_bytes}" "${files}" || return 1
  print -rl -- "$@" >> "${logfile}"
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
