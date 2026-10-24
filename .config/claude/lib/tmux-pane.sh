#!/bin/sh
# Source this file to define `tmux_target_pane`, which prints the current tmux
# pane in the canonical target-pane form `session:window.pane` (empty if not
# inside tmux). See tmux(1) "COMMANDS" → target-pane.

tmux_target_pane() {
  [ -n "${TMUX:-}" ] || return 0
  [ -n "${TMUX_PANE:-}" ] || return 0
  command -v tmux >/dev/null 2>&1 || return 0
  tmux display-message -p -t "$TMUX_PANE" '#{session_name}:#{window_index}.#{pane_index}' 2>/dev/null || true
}
