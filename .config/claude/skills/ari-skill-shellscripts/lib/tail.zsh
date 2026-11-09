#!/usr/bin/env zsh
# tail.zsh — a running command's output as a scrolling window of its last lines, under a spinner.
# Source it; do not execute. Its companion for a wait with no output to show is await.zsh.
#
#   source "${SKILLS_DIR}/ari-skill-shellscripts/lib/tail.zsh"
#   tail::run --title "building nvim" -- nix build .#nvim       # 0, or the command's code
#   tail::start <file> "<title>"; …; tail::stop                  # a window over a file another process writes
#
# Interactive (stderr is a tty; TAIL_INTERACTIVE=1|0 overrides): the title with a spinner, then the
# last TAIL_LINES (default 10) non-empty lines of the output, dim. Each line is what a terminal would
# show: the text after its last carriage return (a progress bar's latest state), escapes stripped,
# clipped to the width. The window redraws every TAIL_TICK_S (default 0.25) as the output grows; it
# never scrolls the terminal past its own height. When it ends, the window is cleared; tail::run then
# prints one line, `✓ <title>` or `✗ <title> (rc=N)` followed by the window's last lines, so whatever
# comes next lands right under it. While a sudo with no child process exists (it is asking for a
# password), the window holds still, so the prompt stays readable.
#
# Plain (stderr is not a tty, or TAIL_INTERACTIVE=0): tail::run streams the command's output (stdout
# and stderr, merged) as it comes, and tail::start/stop do nothing.
#
# tail::run keeps the whole output in --log FILE (appended), else in a temporary file it removes.
# TAIL_SPIN_COLOR is the spinner's 256-colour index (default 37). Names with `_` after `::` are internal.

[[ -n "${_ARI_TAIL_ZSH:-}" ]] && return 0
readonly _ARI_TAIL_ZSH=1
zmodload zsh/zselect 2>/dev/null || true
zmodload -F zsh/files b:zf_rm 2>/dev/null || true
zmodload -F zsh/system p:sysparams 2>/dev/null || true
zmodload -F zsh/datetime p:EPOCHREALTIME 2>/dev/null || true

typeset -ga _TAIL_SPINNER=(⣾ ⣽ ⣻ ⢿ ⡿ ⣟ ⣯ ⣷)
typeset -g _tail_pid="" _tail_sentinel=""

tail::_is_interactive() {
  [[ -n "${TAIL_INTERACTIVE:-}" ]] && { (( TAIL_INTERACTIVE )); return; }
  [[ -t 2 ]]
}

# True while a sudo has no child: it is still asking for the password (or has only just started).
tail::_is_sudo_asking() {
  local pid
  for pid in ${(f)"$(pgrep -x sudo 2>/dev/null)"}; do
    [[ -n "$(pgrep -P "${pid}" 2>/dev/null)" ]] || return 0
  done
  return 1
}

# The last <n> lines of <file> as a terminal shows them, one per line.
tail::_lines() {
  tail -n $(( ${2} * 6 + 20 )) -- "${1}" 2>/dev/null \
    | sed -E -e $'s/.*\r//' -e $'s/\e\\[[0-9;?]*[ -/]*[@-~]//g' -e $'s/\e[]PX^_][^\a\e]*(\a|\e\\\\)//g' \
    | grep -v -E '^[[:space:]]*$' | tail -n "${2}"
}

# The renderer, in a background subshell: writes its pid into the sentinel so tail::stop's USR1 ends
# it at once; exits when told, when the sentinel goes, or when the caller dies, clearing what it drew.
tail::_window() {
  local file="${1}" title="${2}" sentinel="${3}" parent="${4}" out line
  local -i n="${TAIL_LINES:-10}" i=0 k cols=80 rows=24
  local -i ticks=$(( ${TAIL_TICK_S:-0.25} * 100 ))   # zselect's unit is hundredths
  (( ticks > 0 )) || ticks=1
  local spin=$'\e[38;5;'"${TAIL_SPIN_COLOR:-37}"'m' dim=$'\e[2m' rst=$'\e[0m' size
  local -a shown
  # A script has no LINES or COLUMNS: ask the terminal once.
  size="$(stty size < /dev/tty 2>/dev/null)" && [[ "${size}" == <->' '<-> ]] && rows="${size% *}" cols="${size#* }"
  [[ "${LC_ALL:-${LC_CTYPE:-${LANG:-}}}" == *[Uu][Tt][Ff]* ]] || local LC_ALL=en_US.UTF-8
  trap 'print -nu2 -- $'"'"'\r\e[J\e[?25h'"'"'; zf_rm -f -- "${sentinel}"; exit 0' USR1 TERM INT HUP
  { unsetopt clobber; print -r -- "${sysparams[pid]}" >> "${sentinel}"; } 2>/dev/null || return 0
  print -nu2 -- $'\e[?25l'
  while [[ -e "${sentinel}" ]] && kill -0 "${parent}" 2>/dev/null; do
    if ! tail::_is_sudo_asking; then
      (( n > rows - 2 )) && n=$(( rows > 3 ? rows - 2 : 1 ))
      shown=("${(@f)$(tail::_lines "${file}" "${n}")}")
      out=$'\r\e[2K'"${spin}${_TAIL_SPINNER[i % ${#_TAIL_SPINNER} + 1]}${rst} ${title}"
      k=0
      for line in "${(@)shown:#}"; do out+=$'\n\e[2K'"${dim}  ${line[1,cols-4]}${rst}"; k+=1; done
      out+=$'\e[J'
      (( k > 0 )) && out+=$'\e'"[${k}A"
      print -nu2 -- "${out}"$'\r'
      i+=1
    fi
    zselect -t "${ticks}"
  done
  print -nu2 -- $'\r\e[J\e[?25h'
  zf_rm -f -- "${sentinel}"
}

# Start the window over <file>, titled <title>. One at a time: a second start replaces the first.
tail::start() {
  local file="${1:?tail::start needs a file}" title="${2:-}" parent sentinel
  tail::_is_interactive || return 0
  tail::stop
  parent="${sysparams[pid]:-$$}"
  sentinel="${TMPDIR:-/tmp}"
  sentinel="${sentinel%/}/tail-window.${parent}.${EPOCHREALTIME//[^0-9]/}"
  { setopt localoptions noclobber; : > "${sentinel}"; } 2>/dev/null || return 0
  _tail_sentinel="${sentinel}"
  tail::_window "${file}" "${title}" "${sentinel}" "${parent}" < /dev/null > /dev/null &
  _tail_pid="${!}"
  return 0
}

# Stop the window and clear it; idempotent, returns once the renderer has gone.
tail::stop() {
  [[ -n "${_tail_pid}" ]] || return 0
  local pid="${_tail_pid}" sentinel="${_tail_sentinel}" renderer=""
  _tail_pid="" _tail_sentinel=""
  [[ -r "${sentinel}" ]] && { IFS= read -r renderer < "${sentinel}" 2>/dev/null || true; }
  zf_rm -f -- "${sentinel}" 2>/dev/null || true
  if [[ "${renderer}" == <1-> ]]; then kill -USR1 "${renderer}" 2>/dev/null || true
  else kill -TERM "${pid}" 2>/dev/null || true; fi
  if ! wait "${pid}" 2>/dev/null; then
    local -i tries=0
    while kill -0 "${pid}" 2>/dev/null && (( tries++ < 50 )); do zselect -t 2; done
  fi
  print -nu2 -- $'\r\e[J'
  return 0
}

# tail::run [--title T] [--log FILE] -- <command…>: run it with its output in the window (interactive)
# or streamed (plain); returns its code.
tail::run() {
  local title="" log="" own_log=0
  while (( $# )); do
    case "${1}" in
      --title) title="${2}"; shift 2 ;;
      --log) log="${2}"; shift 2 ;;
      --) shift; break ;;
      *) print -u2 -- "tail::run: unknown flag | flag='${1}'"; return 64 ;;
    esac
  done
  (( $# )) || { print -u2 -- "tail::run: no command after --"; return 64; }
  [[ -n "${title}" ]] || title="${*}"
  if [[ -z "${log}" ]]; then log="$(mktemp "${TMPDIR:-/tmp}/tail-run.XXXXXX")" || return 1; own_log=1; fi
  local -i rc
  if tail::_is_interactive; then
    tail::start "${log}" "${title}"
    "$@" >> "${log}" 2>&1
    rc=$?
    tail::stop
    if (( rc == 0 )); then
      print -u2 -- $'\e[32m✓\e[0m '"${title}"
    else
      print -u2 -- $'\e[31m✗\e[0m '"${title} (rc=${rc})"
      tail::_lines "${log}" "${TAIL_LINES:-10}" | sed 's/^/  /' >&2
    fi
  else
    { "$@" } 2>&1 | tee -a "${log}"
    rc=${pipestatus[1]}
  fi
  (( own_log )) && rm -f "${log}"
  return "${rc}"
}
