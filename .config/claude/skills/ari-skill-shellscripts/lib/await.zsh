#!/usr/bin/env zsh
# await.zsh — one status line for a wait, owned by the library, ended by the function's return.
# Source it; do not execute. Convention: /ari-skill-shellscripts § Waiting with a visible state.
#
#   source "${SKILLS_DIR}/ari-skill-shellscripts/lib/await.zsh"     # before the functions that use it
#
# A wait is either the machine's turn (a grey spinner, "working…") or the person's turn (a magenta
# pulse and one bell, "your turn: press a key"), and it ends exactly once: a green ✓ when the step
# returns 0, a red ✗ with the step's code otherwise (124 for a timeout, 130 for ctrl-c). The
# spinner is a small background renderer, so it keeps moving while the step blocks.
#
#   (start) ──► computer ◄──► user ──► ✓ success   the step returned 0
#                  │            │
#                  └────────────┴───► ✗ failure   the step returned rc
#
# The default shape, await::run: the library calls your step and ends the line from its exit code.
#
#   step() {
#     frob || return 1
#     await::user "your turn: press a key"; {
#       read -k 1 -s < /dev/tty
#     }
#     await::computer "frobbing some more…"; {
#       frob_more
#     }
#   }
#   await::run --slots 3 "frobbing the widget…" -- step foo bar      # 0, or step's code; 124 with --timeout
#
# The primitive underneath, await::_guard, for a function that wants to own its own message. It is
# an alias: zsh expands it where the function is parsed, so this file must be sourced before that
# function is defined, and it installs the function's EXIT and INT traps (replacing any of its own):
#
#   step() {
#     await::_guard "frobbing the widget…" -- "$@"     # ends when step returns: ✓ on 0, ✗ with the code
#     frob || return 1
#     await::user "your turn: press a key"; {
#       read -k 1 -s < /dev/tty
#     }
#     await::computer "frobbing some more…"; {
#       frob_more
#     }
#   }
#
# Both take `[--timeout S] [--slots N] "<message>" -- <rest…>`: for await::run the rest is the
# command; for await::_guard it is the function's own "$@", shown as args='…' in plain mode and on
# a ✗ line. --timeout is enforced by await::run (the command is killed, 124) and await::until; in a
# bare await::_guard it only shows n/Ns on the line.
#
# Inside a wait, and only there: await::computer "msg", await::user "msg", await::progress N,
# await::note "text" (printed above the line), and by hand await::success "msg" / await::failure
# "msg" [rc]. They talk to the renderer through the descriptor in AWAIT_FD; called outside a wait
# they print `YOU MUST CALL <name> INSIDE await::run OR await::_guard (AWAIT_FD is unset)` and
# return 2. A wait inside a wait nests: the outer line is left frozen where it stands, the inner
# draws its own line one space further in, and when the inner ends the outer resumes on a fresh
# line with its elapsed time still counting (AWAIT_DEPTH is the nesting depth, 0 at the top):
#
#   ⠹ frobbing the widget…                 ← frozen while the inner runs
#    ✓ frobbing the sub-widget…            ← the inner's final line, indented one space
#   ⠼ frobbing the widget… (7s)            ← the outer, resumed
#   ✓ frobbing the widget…
#
# House style: every state call (computer, user) is followed by `; {` and an indented group holding
# that state's work, so whose turn it is reads at a glance. await::_is_shell_block checks the call
# site's line and warns once per site when the group is missing; a style warning changes nothing.
#
# The declarative loop, await::until [--interval S] [--timeout S] [--slots N] -- probe args…: the
# probe prints `<state> <message>` (computer|user|success|failure) and `progress <n>` lines; its
# words rule. Returns 0, 1, 124, 130, or 2 for an unknown state or flag.
#
# Renderings: interactive (stderr is a tty; AWAIT_INTERACTIVE=1|0 overrides) redraws one line in
# place; plain prints one `[AWAIT] …` line per state change and nothing on a tick, for logs, pipes
# and agents. AWAIT_BELL=0 silences the bell. Names with `_` after `::` are internal.

[[ -n "${_ARI_AWAIT_ZSH:-}" ]] && return 0
readonly _ARI_AWAIT_ZSH=1

zmodload zsh/zselect zsh/datetime zsh/mathfunc zsh/system 2>/dev/null || true

if ! typeset -f log::err >/dev/null; then
  print -u2 "[ERROR] await.zsh needs logging.zsh sourced first | lib='${XDG_CONFIG_HOME:-${HOME}/.config}/zsh/plugins/log.zsh'"
  return 1
fi

# The primitive. Expanded by the parser into the calling function: its EXIT trap ends the wait with
# the function's status, its INT trap turns ctrl-c into 130; both are local to that function.
alias await::_guard='setopt localoptions localtraps; trap '\''await::_end $?'\'' EXIT; trap '\''_await_interrupted=1; return 130'\'' INT; await::_begin'

typeset -ga _AWAIT_SPINNER=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏)
typeset -ga _AWAIT_PULSE=(◆ ◆ ◆ ◆ ◇ ◇ ◇ ◇)
typeset -g _await_fd='' _await_dir='' _await_renderer='' _await_child='' _await_msg='' _await_args=''
typeset -g _await_ended=0 _await_slots=0 _await_timeout=0 _await_started=0 _await_interactive=0 _await_interrupted=0

#######################################
# Open a wait: parse the grammar, make the channel, fork the renderer. Called by the alias.
# Arguments: [--timeout S] [--slots N] <message> -- <rest…>
# Returns: 0; 2 on a bad call (the caller runs on with no line)
#######################################
await::_begin() {
  local slots=0 timeout=0
  while (( $# > 0 )); do
    case "${1}" in
      --slots) slots="${2:?--slots needs a count}"; shift 2 ;;
      --timeout) timeout="${2:?--timeout needs seconds}"; shift 2 ;;
      --*) log::err "await: unknown flag | flag='${1}' known='--slots, --timeout'"; return 2 ;;
      *) break ;;
    esac
  done
  if (( $# < 2 )) || [[ "${2}" != -- ]]; then
    log::err "await: the grammar is [--timeout S] [--slots N] \"<message>\" -- <rest…> | got='${*}'"
    return 2
  fi
  if [[ -n "${AWAIT_FD:-}" ]]; then        # a wait inside a wait: freeze the outer line, go one space in
    await::_push
    print -u "${AWAIT_FD}" -- "pause"
    export AWAIT_DEPTH=$(( ${AWAIT_DEPTH:-0} + 1 ))
  else
    export AWAIT_DEPTH=0
  fi
  _await_msg="${1}"; shift 2
  _await_args="${*}"
  _await_slots="${slots}" _await_timeout="${timeout}" _await_started="${EPOCHREALTIME}" _await_ended=0 _await_child='' _await_interrupted=0
  _await_owner="${sysparams[pid]:-$$}"
  if [[ -t 2 ]]; then _await_interactive=1; else _await_interactive=0; fi
  [[ -n "${AWAIT_INTERACTIVE:-}" ]] && _await_interactive="${AWAIT_INTERACTIVE}"
  _await_dir="$(mktemp -d "${TMPDIR:-/tmp}/await.XXXXXX")" || { log::err "await: mktemp failed"; return 2; }
  mkfifo "${_await_dir}/channel" || { log::err "await: mkfifo failed | dir='${_await_dir}'"; return 2; }
  local fd
  exec {fd}<>"${_await_dir}/channel"
  _await_fd="${fd}"
  export AWAIT_FD="${fd}"
  ( await::_renderer "${fd}" ) &
  _await_renderer=$!
  print -u "${fd}" -- "computer ${_await_msg}"
  return 0
}

#######################################
# Close the wait with the function's status. Runs from the EXIT trap the alias installed.
# Arguments: $1 = the function's return code
#######################################
await::_end() {
  local rc="${1:-0}"
  (( _await_interrupted )) && rc=130        # a ctrl-c is a ctrl-c whatever status the return carried
  [[ -n "${_await_fd}" ]] || return 0
  if [[ -n "${_await_child}" ]] && kill -0 "${_await_child}" 2>/dev/null; then
    kill -TERM "${_await_child}" 2>/dev/null
  fi
  if (( ! _await_ended )); then
    if (( rc == 0 )); then print -u "${_await_fd}" -- "success ${_await_msg}"
    elif (( rc == 130 )); then print -u "${_await_fd}" -- "failure 130 interrupted: ${_await_msg}"
    elif (( rc == 124 )); then print -u "${_await_fd}" -- "failure 124 timed out: ${_await_msg}"
    else print -u "${_await_fd}" -- "failure ${rc} ${_await_msg}"; fi
  fi
  local i
  for (( i = 0; i < 20; i++ )); do
    kill -0 "${_await_renderer}" 2>/dev/null || break
    zselect -t 10 2>/dev/null || sleep 0.1
  done
  kill -0 "${_await_renderer}" 2>/dev/null && kill -KILL "${_await_renderer}" 2>/dev/null
  wait "${_await_renderer}" 2>/dev/null
  exec {_await_fd}>&-
  rm -rf "${_await_dir}"
  _await_fd='' _await_dir='' _await_renderer='' _await_child='' _await_ended=0
  if (( ${#_await_stack} > 0 )); then       # back to the outer wait: it resumes on a fresh line
    await::_pop
    export AWAIT_FD="${_await_fd}"
    export AWAIT_DEPTH=$(( AWAIT_DEPTH - 1 ))
    print -u "${_await_fd}" -- "resume"
  else
    unset AWAIT_FD AWAIT_DEPTH
  fi
  return 0
}

# The record of one wait, packed into one string so a stack of them is one array.
typeset -ga _await_stack
typeset -g _await_owner=''
await::_push() {
  local -a f
  f=("${_await_fd}" "${_await_dir}" "${_await_renderer}" "${_await_child}" "${_await_msg}" "${_await_args}" "${_await_ended}" "${_await_slots}" "${_await_timeout}" "${_await_started}" "${_await_interactive}" "${_await_owner}")
  _await_stack+=("${(pj:\x1f:)f}")
}
await::_pop() {
  local -a f
  f=("${(@ps:\x1f:)_await_stack[-1]}")
  _await_stack[-1]=()
  _await_fd="${f[1]}" _await_dir="${f[2]}" _await_renderer="${f[3]}" _await_child="${f[4]}" _await_msg="${f[5]}" _await_args="${f[6]}"
  _await_ended="${f[7]}" _await_slots="${f[8]}" _await_timeout="${f[9]}" _await_started="${f[10]}" _await_interactive="${f[11]}" _await_owner="${f[12]}"
}

# The check every in-scope helper runs first. Arguments: $1 = the helper's name.
await::_inside() {
  [[ -n "${AWAIT_FD:-}" ]] && return 0
  log::err "YOU MUST CALL ${1} INSIDE await::run OR await::_guard (AWAIT_FD is unset)"
  return 2
}

# Call sites already warned about, shared with the steps await::run forks ($$ is the main shell's
# pid in every subshell); removed when the main shell exits.
typeset -g _await_style_file="${TMPDIR:-/tmp}/await-style-$$"
await::_style_cleanup() { rm -f "${_await_style_file}"; }
autoload -Uz add-zsh-hook 2>/dev/null && add-zsh-hook zshexit await::_style_cleanup

#######################################
# The style check: is the state call at $2 followed by `; {` on its line, or by a lone `{` on the
# next non-blank line? Warns once per call site when not. Never changes behaviour.
# Arguments: $1 = the helper's name; $2 = the call site as funcfiletrace gives it, `path:line`
# Returns: 0 when conforming, unreadable (eval, zsh -c, a shell) or already warned; 1 once per site
#######################################
await::_is_shell_block() {
  local name="${1}" site="${2}" path line text next
  path="${site%:*}"; line="${site##*:}"
  [[ "${path}" == \(eval\)* || "${path}" == zsh* || -z "${line}" || ! -r "${path}" || "${line}" != <-> ]] && return 0
  local -a lines
  lines=("${(@f)$(<"${path}")}")          # builtins only: the check must not depend on PATH
  text="${lines[line]:-}"
  [[ "${text}" == *eval* ]] && return 0   # code from an eval string reports the eval's own line
  text="${text%%#*}"
  [[ "${text}" =~ ';[[:space:]]*\{[[:space:]]*$' ]] && return 0
  local i
  for (( i = line + 1; i <= ${#lines}; i++ )); do
    next="${lines[i]}"
    [[ "${next}" =~ '^[[:space:]]*$' ]] && continue
    [[ "${next}" =~ '^[[:space:]]*\{[[:space:]]*$' ]] && return 0
    break
  done
  [[ -r "${_await_style_file}" && "$(<"${_await_style_file}")" == *"|${site}|"* ]] && return 0
  print -r -- "|${site}|" >> "${_await_style_file}"
  log::warn "style: ${name} should be followed by an indented { } group | at='${site}'"
  return 1
}

# The machine is working. Arguments: $1 = what it is doing.
await::computer() {
  await::_inside await::computer || return 2
  [[ "${funcsourcetrace[2]:-}" == \(eval\)* ]] || await::_is_shell_block await::computer "${funcfiletrace[1]}" || true
  print -u "${AWAIT_FD}" -- "computer ${1:-working…}"
}

# The person must act. Rings once on entry when interactive. Arguments: $1 = what to do.
await::user() {
  await::_inside await::user || return 2
  [[ "${funcsourcetrace[2]:-}" == \(eval\)* ]] || await::_is_shell_block await::user "${funcfiletrace[1]}" || true
  print -u "${AWAIT_FD}" -- "user ${1:-your turn}"
}

# Mark progress through the slots. Arguments: $1 = cells done.
await::progress() { await::_inside await::progress || return 2; print -u "${AWAIT_FD}" -- "progress ${1:?await::progress needs a count}"; }

# Print a line above the status line without tearing it. Arguments: $1 = the text.
await::note() { await::_inside await::note || return 2; print -u "${AWAIT_FD}" -- "note ${1}"; }

# End the wait well by hand; the function's return then only reaps. Arguments: $1 = what is true.
await::success() {
  await::_inside await::success || return 2
  print -u "${AWAIT_FD}" -- "success ${1:-done}"
  _await_ended=1
  return 0
}

# End the wait badly by hand. Arguments: $1 = what went wrong; $2 = the code (default 1). Returns $2.
await::failure() {
  await::_inside await::failure || return 2
  local rc="${2:-1}"
  print -u "${AWAIT_FD}" -- "failure ${rc} ${1:-failed}"
  _await_ended=1
  return "${rc}"
}

#######################################
# Run a step under a wait; the line ends from the step's exit code.
# Arguments: [--timeout S] [--slots N] <message> -- <command> [args…]
# Returns: the command's code; 124 when --timeout kills it; 130 on ctrl-c; 2 on a bad call
#######################################
await::run() {
  local -a opts
  local timeout=0
  while (( $# > 0 )); do
    case "${1}" in
      --timeout) timeout="${2:?--timeout needs seconds}"; opts+=("${1}" "${2}"); shift 2 ;;
      --slots) opts+=("${1}" "${2:?--slots needs a count}"); shift 2 ;;
      --*) log::err "await::run: unknown flag | flag='${1}' known='--slots, --timeout'"; return 2 ;;
      *) break ;;
    esac
  done
  if (( $# < 3 )) || [[ "${2}" != -- ]]; then
    log::err "await::run: the grammar is [--timeout S] [--slots N] \"<message>\" -- <command> [args…] | got='${*}'"
    return 2
  fi
  local msg="${1}"; shift 2
  await::_guard "${opts[@]}" "${msg}" -- "$@" || return 2
  "$@" &
  _await_child=$!
  local deadline=0
  (( timeout > 0 )) && deadline=$(( EPOCHREALTIME + timeout ))
  while (( ! _await_interrupted )) && kill -0 "${_await_child}" 2>/dev/null; do
    if (( deadline > 0 && EPOCHREALTIME >= deadline )); then
      kill -TERM "${_await_child}" 2>/dev/null
      zselect -t 20 2>/dev/null || sleep 0.2
      kill -KILL "${_await_child}" 2>/dev/null
      wait "${_await_child}" 2>/dev/null
      _await_child=''
      return 124
    fi
    zselect -t 5 2>/dev/null || sleep 0.05
  done
  (( _await_interrupted )) && return 130
  local rc=0
  wait "${_await_child}" || rc=$?
  _await_child=''
  return "${rc}"
}

#######################################
# The declarative loop: call a probe until it reports a final state.
# Arguments: [--interval S] [--timeout S] [--slots N] -- PROBE [ARGS…]
#   PROBE prints one `<state> <message>` line per call (computer|user|success|failure) and may
#   print `progress <n>` lines before it. Its exit code is ignored; its words rule. It runs in a
#   command substitution, so state it keeps must live in a file or the world, never a variable.
# Returns: 0 success, 1 failure, 124 timeout, 130 ctrl-c, 2 unknown state or bad flag
#######################################
await::until() {
  local interval="${AWAIT_TICK_S:-0.1}" timeout=0
  local -a opts
  while (( $# > 0 )); do
    case "${1}" in
      --interval) interval="${2:?--interval needs seconds}"; shift 2 ;;
      --timeout) timeout="${2:?--timeout needs seconds}"; opts+=("${1}" "${2}"); shift 2 ;;
      --slots) opts+=("${1}" "${2:?--slots needs a count}"); shift 2 ;;
      --) shift; break ;;
      *) log::err "await::until: unknown flag | flag='${1}' known='--interval, --timeout, --slots, --'"; return 2 ;;
    esac
  done
  (( $# > 0 )) || { log::err "await::until: no probe after --"; return 2; }
  await::_guard "${opts[@]}" "probing…" -- "$@" || return 2
  local deadline=0
  (( timeout > 0 )) && deadline=$(( EPOCHREALTIME + timeout ))
  local out line state msg
  while true; do
    out="$("$@" 2>/dev/null || true)"
    for line in "${(@f)out}"; do
      [[ -z "${line}" ]] && continue
      state="${line%% *}"; msg="${line#* }"; [[ "${msg}" == "${line}" ]] && msg=''
      case "${state}" in
        progress) await::progress "${msg}" ;;
        computer) print -u "${AWAIT_FD}" -- "computer ${msg}" ;;   # the relay has no work of its own to group: straight to the channel
        user)     print -u "${AWAIT_FD}" -- "user ${msg}" ;;
        success)  await::success "${msg}"; return 0 ;;
        failure)  await::failure "${msg}" 1; return 1 ;;
        *) log::err "await::until: probe printed an unknown state | line='${line}' states='computer, user, success, failure, progress'"; return 2 ;;
      esac
    done
    if (( deadline > 0 && EPOCHREALTIME >= deadline )); then
      await::failure "timed out" 124; return 124
    fi
    zselect -t $(( int(interval * 100) )) 2>/dev/null || sleep "${interval}"
  done
}

#######################################
# The renderer, in the background for the life of one wait: reads the channel, draws, exits after
# a final state. Globals read: the _await_* fields set by _begin (inherited by the subshell).
# Arguments: $1 = the channel descriptor
#######################################
await::_renderer() {
  local fd="${1}" state=computer msg="${_await_msg}" done=0 tick=0 line word rest rc rang=0
  local -i final=0 paused=0
  local last_plain='' indent=''
  repeat ${AWAIT_DEPTH:-0} indent+=' '          # one space per nesting level
  trap '' INT
  await::_draw
  while (( ! final )); do
    if zselect -t 10 -r "${fd}" 2>/dev/null; then
      read -r -u "${fd}" line || break
      word="${line%% *}"; rest="${line#* }"; [[ "${rest}" == "${line}" ]] && rest=''
      case "${word}" in
        pause)  paused=1; (( _await_interactive )) && print -u2; continue ;;     # leave the line as it stands
        resume) paused=0; await::_draw force; continue ;;                        # a fresh line, same state, same clock
        computer) state=computer; msg="${rest}" ;;
        user)
          if [[ "${state}" != user ]] && (( _await_interactive )) && [[ "${AWAIT_BELL:-1}" != 0 ]]; then print -nu2 -- $'\a'; fi
          state=user; msg="${rest}" ;;
        progress)
          done="${rest}"; (( done < 0 )) && done=0; (( done > _await_slots )) && done=${_await_slots} ;;
        note)
          if (( _await_interactive )); then print -u2 -- $'\r\e[K'"${indent}${rest}"; else print -u2 -- "${indent}${c_grey}[AWAIT] note${c_rst}: ${rest}"; fi ;;
        success) state=success; msg="${rest}"; done=${_await_slots}; final=1 ;;
        failure) rc="${rest%% *}"; msg="${rest#* }"; [[ "${msg}" == "${rest}" ]] && msg=''; state=failure; final=1 ;;
        *) continue ;;
      esac
      (( paused )) || await::_draw
    else
      (( tick++ ))
      kill -0 "${_await_owner}" 2>/dev/null || break      # the shell that opened this wait is gone
      (( _await_interactive && ! paused )) && await::_draw
    fi
  done
}

# Draw the current state: in place when interactive, one line per change when plain.
# Globals: the renderer's locals (state, msg, done, tick, rc, last_plain), the _await_* fields.
await::_draw() {
  local elapsed=$(( int(EPOCHREALTIME - _await_started) ))
  if (( ! _await_interactive )); then
    local key="${state}|${msg}|${done}" tag ctx=''
    [[ "${key}" == "${last_plain}" || "${1:-}" == force ]] && return 0
    last_plain="${key}"
    case "${state}" in
      computer) tag="${c_grey}[AWAIT] computer${c_rst}" ;;
      user)     tag="${c_magenta}[AWAIT] user${c_rst}" ;;
      success)  tag="${c_green}[AWAIT] ✓ success${c_rst}" ;;
      failure)  tag="${c_red}[AWAIT] ✗ failure${c_rst}" ;;
    esac
    local progress=''
    (( _await_slots > 0 )) && progress=" ${done}/${_await_slots}"
    [[ -n "${_await_args}" && ( "${state}" == failure || ${elapsed} -eq 0 && "${state}" == computer ) ]] && ctx=" | args='${_await_args}'"
    [[ "${state}" == failure ]] && ctx=" | rc='${rc}'${ctx}"
    print -u2 -- "${indent}${tag}${progress}: ${msg} | elapsed_s='${elapsed}'${ctx}"
    return 0
  fi
  local frame slots='' tail='' text
  # The current slot always carries the braille spinner; only the frame beside the message
  # switches to the magenta pulse on the person's turn.
  local spin="${c_yellow}${_AWAIT_SPINNER[tick % ${#_AWAIT_SPINNER} + 1]}${c_rst}" cell
  case "${state}" in
    computer) frame="${spin}" cell="${spin}" ;;
    user)     frame="${c_bold}${c_magenta}${_AWAIT_PULSE[tick % ${#_AWAIT_PULSE} + 1]}${c_rst}" cell="${spin}" ;;
    success)  frame="${c_green}✓${c_rst}" cell="${frame}" ;;
    failure)  frame="${c_red}✗${c_rst}" cell="${frame}" ;;
  esac
  if (( _await_slots > 0 )); then
    local i
    for (( i = 1; i <= _await_slots; i++ )); do
      if (( i <= done )); then slots+="${c_green}✓${c_rst}"
      elif (( i == done + 1 )); then slots+="${cell}"
      else slots+=' '; fi
    done
    slots="${c_green}[${c_rst}${slots}${c_green}]${c_rst} "
  fi
  if (( _await_timeout > 0 )); then tail=" ${c_grey}(${elapsed}/${_await_timeout}s)${c_rst}"
  elif (( elapsed >= 5 )); then tail=" ${c_grey}(${elapsed}s)${c_rst}"; fi
  case "${state}" in
    computer) text="${c_grey}${msg}${c_rst}" ;;
    user)     text="${c_bold}${c_magenta}${msg}${c_rst}" ;;
    success)  text="${c_green}${msg}${c_rst}" ;;
    failure)  text="${c_red}${msg}${c_rst}"; [[ -n "${_await_args}" ]] && tail+=" ${c_grey}args='${_await_args}'${c_rst}" ;;
  esac
  print -nu2 -- $'\r'"${indent}${slots}${frame} ${text}${tail}"$'\e[K'
  [[ "${state}" == success || "${state}" == failure ]] && print -u2
  return 0
}
