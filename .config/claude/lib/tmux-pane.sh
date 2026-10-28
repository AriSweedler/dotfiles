#!/bin/sh
# Source this file for tmux pane helpers. POSIX sh: zsh and bash scripts source it, and
# ari-driving-remote's run.zsh prepends its text to the script it runs on another host.
#
#   tmux_target_pane           the current pane as `session:window.pane` (empty outside tmux)
#   tmux_latest_session        the most recently active client's session
#   tmux_latest_client         the most recently active client
#   tmux_resolve_pane          W.P | %N | S:W[.P] to a pane ID, exact matches only
#   tmux_pane_input_refusal    why keys sent to a pane would not reach its program as typed
#   tmux_pane_gate_refusal     why Claude must not type into a pane (opt-in, input, idle shell prompt)
#   tmux_pane_is_claude        whether a pane runs Claude Code
#   tmux_text_refusal          why a command text must not be typed (control characters, a leading clear)
#   tmux_pane_lock / _unlock   a short per-pane lock around gate-and-type
#   tmux_switch_to_pane        switch a client (default: the most recently active) to a pane
#   tmux_paste_line            paste one line into a pane's prompt, bracketed, no Enter
#
# Refusal functions print the reason on stdout and return non-zero; they print nothing and
# return 0 when the action may go ahead. No `readonly`: callers may source this twice.

# `ari-driving on` sets this pane option; only the pane's own value grants anything.
ARI_DRIVING_OPTION=@ari_driving
ARI_DRIVING_LABEL_FORMAT='ID=#{pane_id}|pane=#{window_index}.#{pane_index}'
ARI_DRIVING_EXIT_NOT_OPTED_IN=77
ARI_DRIVING_EXIT_BUSY=75
ARI_DRIVING_LOCK_ROOT=/tmp/ari-driving-locks
# A lock older than this belongs to a process that died holding it.
ARI_DRIVING_LOCK_STALE_SECONDS=10

tmux_target_pane() {
  [ -n "${TMUX:-}" ] || return 0
  [ -n "${TMUX_PANE:-}" ] || return 0
  command -v tmux >/dev/null 2>&1 || return 0
  tmux display-message -p -t "$TMUX_PANE" '#{session_name}:#{window_index}.#{pane_index}' 2>/dev/null || true
}

# awk reads every line, so no upstream command dies of SIGPIPE under pipefail.
tmux_latest_session() {
  tmux list-clients -F '#{client_activity} #{client_session}' 2>/dev/null | sort -rn | awk 'NR == 1 {sub(/^[^ ]* /, ""); print}'
}

tmux_latest_client() {
  tmux list-clients -F '#{client_activity} #{client_name}' 2>/dev/null | sort -rn | awk 'NR == 1 {sub(/^[^ ]* /, ""); print}'
}

# Print the pane ID a target names. tmux's own target lookup is fuzzy and would land keys in
# some other pane, so every form is matched exactly. A bare W.P is looked up in $2, else in
# the most recently active client's session.
# Returns: 1 when no pane matches; 2 when W.P has no session to resolve against.
tmux_resolve_pane() {
  _trp_target="$1" _trp_session="${2:-}" _trp_pane=""
  case "$_trp_target" in
    %*)
      _trp_pane="$_trp_target" ;;
    *:*)
      _trp_pane=$(tmux list-panes -a -F '#{session_name}:#{window_index}.#{pane_index} #{pane_id}' | awk -v t="$_trp_target" '$1 == t {print $2}')
      [ -n "$_trp_pane" ] || _trp_pane=$(tmux list-windows -a -F '#{session_name}:#{window_index} #{pane_id}' | awk -v t="$_trp_target" '$1 == t {print $2}') ;;
    *)
      [ -n "$_trp_session" ] || _trp_session=$(tmux_latest_session)
      [ -n "$_trp_session" ] || return 2
      _trp_pane=$(tmux list-panes -a -F '#{session_name}:#{window_index}.#{pane_index} #{pane_id}' | awk -v t="$_trp_session:$_trp_target" '$1 == t {print $2}') ;;
  esac
  tmux list-panes -a -F '#{pane_id}' | awk -v p="$_trp_pane" '$1 == p {found = 1} END {exit !found}' || return 1
  printf '%s\n' "$_trp_pane"
}

# Copy mode would eat the keys (and Enter there copies a selection to the clipboard);
# synchronized panes would repeat them into every pane of the window. pane_in_mode counts the
# stacked modes (a view mode under a copy mode reads 2), so anything but 0 is a mode.
tmux_pane_input_refusal() {
  _tpi_flags=$(tmux display-message -p -t "$1" '#{pane_in_mode} #{pane_synchronized}' 2>/dev/null) || {
    echo "no such pane"
    return 1
  }
  case "$_tpi_flags" in
    0\ 0) return 0 ;;
    0\ *) echo "synchronize-panes is on"; return 1 ;;
  esac
  echo "in copy mode (press q there)"
  return 1
}

# Login shells show a leading '-'.
tmux_is_shell_command() {
  case "$1" in
    zsh|bash|sh|fish|-zsh|-bash|-sh|-fish) return 0 ;;
  esac
  return 1
}

# The gate before typing: opted in, keys reach the program, an idle shell, last line ends in $2.
# Returns: ARI_DRIVING_EXIT_NOT_OPTED_IN or ARI_DRIVING_EXIT_BUSY when refused.
tmux_pane_gate_refusal() {
  _tpg_pane="$1" _tpg_prompt_end="$2"
  if [ "$(tmux show-options -pqv -t "$_tpg_pane" "$ARI_DRIVING_OPTION" 2>/dev/null)" != on ]; then
    echo "not opted in; Ari runs 'ari-driving on' in that pane"
    return "$ARI_DRIVING_EXIT_NOT_OPTED_IN"
  fi
  tmux_pane_input_refusal "$_tpg_pane" || return "$ARI_DRIVING_EXIT_BUSY"
  _tpg_fg=$(tmux display-message -p -t "$_tpg_pane" '#{pane_current_command}')
  if ! tmux_is_shell_command "$_tpg_fg"; then
    echo "running $_tpg_fg, not a shell"
    return "$ARI_DRIVING_EXIT_BUSY"
  fi
  _tpg_last=$(tmux capture-pane -p -t "$_tpg_pane" | awk '{sub(/[[:space:]]+$/, "")} NF {l = $0} END {print l}')
  case "$_tpg_last" in
    *"$_tpg_prompt_end") ;;
    *) echo "last line does not end in the prompt (busy, or text already on the line)"
       return "$ARI_DRIVING_EXIT_BUSY" ;;
  esac
  return 0
}

# Claude Code shows up as its version (2.1.312) in #{pane_current_command}, or as claude.
tmux_pane_is_claude() {
  _tpc_cmd=$(tmux display-message -p -t "$1" '#{pane_current_command}' 2>/dev/null) || return 1
  [ "$_tpc_cmd" = claude ] && return 0
  printf '%s\n' "$_tpc_cmd" | awk '/^[0-9]+\.[0-9]+\.[0-9]+$/ {ok = 1} END {exit !ok}'
}

# A newline typed into a pane presses Enter; Tab completes, ESC switches zle to vi mode, ^D can
# exit the shell. A leading clear wipes the typed command from Ari's scrollback.
tmux_text_refusal() {
  case "$1" in
    *[[:cntrl:]]*) echo "contains a newline or control character; chain with && or ; on one line"; return 1 ;;
  esac
  _ttr_trimmed="${1#"${1%%[![:space:]]*}"}"
  case "$_ttr_trimmed" in
    clear|clear[[:space:]\;\&\|]*) echo "starts with clear, which wipes the typed command from Ari's scrollback; drop it"; return 1 ;;
  esac
  return 0
}

# Hold a per-pane lock so a double click or two callers cannot both pass the gate and type.
# Waits up to $2 seconds (default 2); a lock older than ARI_DRIVING_LOCK_STALE_SECONDS is broken.
# Returns: 1 when another process holds it.
tmux_pane_lock() {
  _tpl_dir=$(tmux_pane_lock_dir "$1") _tpl_tries=$(( ${2:-2} * 5 ))
  mkdir -p "$ARI_DRIVING_LOCK_ROOT" 2>/dev/null || true
  while ! mkdir "$_tpl_dir" 2>/dev/null; do
    _tpl_at=$(cat "$_tpl_dir/at" 2>/dev/null || echo 0)
    if [ $(( $(date +%s) - ${_tpl_at:-0} )) -gt "$ARI_DRIVING_LOCK_STALE_SECONDS" ]; then
      rm -rf "$_tpl_dir"
      continue
    fi
    [ "$_tpl_tries" -gt 0 ] || return 1
    _tpl_tries=$(( _tpl_tries - 1 ))
    sleep 0.2
  done
  date +%s > "$_tpl_dir/at"
}

tmux_pane_unlock() {
  rm -rf "$(tmux_pane_lock_dir "$1")"
}

# Keyed by the tmux server's pid too: pane IDs restart at %0 on every server.
tmux_pane_lock_dir() {
  printf '%s/%s-%s\n' "$ARI_DRIVING_LOCK_ROOT" "$(tmux display-message -p '#{pid}' 2>/dev/null)" "${1#%}"
}

# Switch a client to the pane's session, window and pane. $2 names the client; by default the most
# recently active one, which is the one Ari is looking at.
# Returns: 1 when there is no client to switch.
tmux_switch_to_pane() {
  _tsp_pane="$1" _tsp_client="${2:-}"
  [ -n "$_tsp_client" ] || _tsp_client=$(tmux_latest_client)
  [ -n "$_tsp_client" ] || return 1
  tmux switch-client -c "$_tsp_client" -t "$_tsp_pane" \; select-window -t "$_tsp_pane" \; select-pane -t "$_tsp_pane"
}

# Paste one line into a pane's prompt (an agent's): a bracketed paste, not keystrokes, so a busy
# prompt or a numbered permission dialog never reads the text's digits as answers. Nothing follows
# it, not even Enter; a leading space keeps two pastes in a row apart. Refuses a pane in copy mode
# or synchronized (the text would be eaten or repeated), with the reason on stdout.
# Returns: 1 when nothing was pasted.
tmux_paste_line() {
  _tpst_pane="$1" _tpst_text="$2" _tpst_buffer="ari-driving-$$"
  _tpst_refusal=$(tmux_pane_input_refusal "$_tpst_pane") || { echo "$_tpst_refusal"; return 1; }
  if ! printf ' %s' "$_tpst_text" | tmux load-buffer -b "$_tpst_buffer" - 2>/dev/null \
      || ! tmux paste-buffer -p -d -b "$_tpst_buffer" -t "$_tpst_pane" 2>/dev/null; then
    tmux delete-buffer -b "$_tpst_buffer" 2>/dev/null || true
    echo "paste-buffer failed"
    return 1
  fi
}
