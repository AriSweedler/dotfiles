#!/usr/bin/env bash
#
# Display a help popup for a tmux key table and optionally enact the
# pressed key's bound action.
#
# Searches for <name>.sh in help.bash.d directories under both
# XDG_CONFIG_HOME and XDG_DATA_HOME tmux plugin trees. The help file
# should populate an associative array called "help" mapping keys to
# descriptions (e.g. help[c]="create") and optionally "help_style" for
# per-key formatting overrides.
#
# After displaying the help entries, waits for a single keypress. If the
# key matches a help entry, the corresponding tmux binding is looked up
# via `tmux list-keys` and executed — so pressing a key in help behaves
# identically to pressing it directly.
#
# Usage:
#   bind-key -T <table> ? run-shell 'bash help.sh <table>'

# ─── Helpers ──────────────────────────────────────────────────────────

#######################################
# Locate the help definition file for a key table.
# Globals:
#   XDG_CONFIG_HOME, XDG_DATA_HOME, HOME
# Arguments:
#   name - key table name
# Outputs:
#   Prints the path to the help file, or nothing if not found.
#######################################
find_help_file() {
  local name="$1"
  local dir
  for dir in \
    "${XDG_CONFIG_HOME:-${HOME}/.config}/tmux/plugin/help.bash.d" \
    "${XDG_DATA_HOME:-${HOME}/.local/share}/tmux/plugin/help.bash.d"; do
    if [[ -f "${dir}/${name}.sh" ]]; then
      echo "${dir}/${name}.sh"
      return
    fi
  done
}

#######################################
# Compute popup dimensions from the help array.
# Expects the "help" associative array to already be populated.
# Arguments:
#   None (reads from the "help" array)
# Outputs:
#   Prints "width height" to stdout.
#######################################
compute_size() {
  local max_w=0 len
  local footer="[press any key]"

  for k in "${!help[@]}"; do
    # "  %-5s %s" → 2 + 5 + 1 + description length
    len=$(( 8 + ${#help[${k}]} ))
    (( len > max_w )) && max_w="${len}"
  done

  # The "?" help line: "  ?     this help"
  (( 17 > max_w )) && max_w=17

  # Footer line: "  [press any key]"
  len=$(( 2 + ${#footer} ))
  (( len > max_w )) && max_w="${len}"

  # +4 for popup border + padding
  local width=$(( max_w + 4 ))

  # entries + "? this help" + blank line above + blank line between + footer
  local height=$(( ${#help[@]} + 6 ))

  echo "${width} ${height}"
}

#######################################
# Read @_help_enact, and if set, enact that key's bound tmux command.
# Extracts the command from "tmux list-keys", converts bind-key "\;"
# separators to source-file compatible ";" separators, and executes
# via a temp source file. No-ops if @_help_enact is unset.
# Arguments:
#   table - tmux key table name
# Examples:
#   # Single command — list-keys output:
#   #   bind-key -T cloud-dev c new-window "source ..."
#   # Extracted and executed as:
#   #   new-window "source ..."
#   try_enact_key "cloud-dev"
#
#   # Chained command — list-keys output:
#   #   bind-key -T join W set-option -Fg @join_src "#{pane_id}" \; switch-client -T join-window
#   # "\;" converted to ";" for source-file, executed as two commands:
#   #   set-option -Fg @join_src "#{pane_id}" ; switch-client -T join-window
#   try_enact_key "join"
#######################################
try_enact_key() {
  local table="$1"

  local key
  key=$(tmux show-option -gqv @_help_enact)
  tmux set-option -gu @_help_enact 2>/dev/null
  [[ -z "${key}" ]] && return

  local line 
  line=$(tmux list-keys -T "${table}" "${key}" 2>/dev/null)
  [[ -z "${line}" ]] && return

  local cmd
  cmd=$(echo "${line}" | sed -E \
    's/^bind-key[[:space:]]+(-r[[:space:]]+)?-T[[:space:]]+[^[:space:]]+[[:space:]]+[^[:space:]]+[[:space:]]+//')
  [[ -z "${cmd}" ]] && return

  local tmp
  tmp=$(mktemp "${TMPDIR:-/tmp}/tmux-help-enact.XXXXXX")
  echo "${cmd}" | sed 's/ \\; / ; /g' > "${tmp}"
  tmux source-file "${tmp}"
  rm -f "${tmp}"
}

#######################################
# Render help entries, wait for a keypress. If the key matches a help
# or help_enact entry, signals it via @_help_enact for the caller
# to execute after the popup closes.
# Globals:
#   help, help_style, help_enact
# Arguments:
#   name - key table name
#######################################
render() {
  local name="$1"

  tput civis
  trap 'tput cnorm' EXIT

  printf '\n'
  local k style
  for k in "${!help[@]}"; do
    style="${help_style[${k}]:-${bold}}"
    printf "  %s%-5s%s %s\n" "${style}" "${k}" "${rst}" "${help[${k}]}"
  done
  printf "  %s%-5s %s%s\n" "${grey}" "?" "this help" "${rst}"
  printf '\n'

  printf "  %s[press any key]%s" "${dim}" "${rst}"
  local key
  read -r -n 1 -s key
  local replay_keys=" ${!help[*]} ${help_enact[*]} "
  if [[ "${replay_keys}" == *" ${key} "* ]]; then
    tmux set-option -g @_help_enact "${key}"
  fi
}

# ─── Args ─────────────────────────────────────────────────────────────

readonly NAME="$1"
readonly PHASE="${2:---launch}"  # --render (inside popup) or --launch (default)

# ─── Main ─────────────────────────────────────────────────────────────

main() {
  local help_file
  help_file="$(find_help_file "${NAME}")"
  if [[ -z "${help_file}" ]]; then
    echo "help file not found: ${NAME}" >&2
    return 1
  fi

  # Colors are defined before sourcing so help files can use them
  # in help_style entries (e.g. help_style[W]="${bold}${cyan}").
  bold=$(  tput bold)
  rst=$(   tput sgr0)
  dim=$(   tput dim    2>/dev/null || echo "")
  red=$(   tput setaf 1 2>/dev/null || echo "")
  green=$( tput setaf 2 2>/dev/null || echo "")
  yellow=$(tput setaf 3 2>/dev/null || echo "")
  blue=$(  tput setaf 4 2>/dev/null || echo "")
  purple=$(tput setaf 5 2>/dev/null || echo "")
  cyan=$(  tput setaf 6 2>/dev/null || echo "")
  white=$( tput setaf 7 2>/dev/null || echo "")
  grey=$(  tput setaf 8 2>/dev/null || echo "")

  # Sourced in both phases (phase 1 for sizing, phase 2 for rendering).
  # The help files are 2-4 lines so the duplication is simpler than
  # serializing state between processes.
  declare -A help
  declare -A help_style
  declare -a help_enact
  # shellcheck source=/dev/null
  . "${help_file}"

  # --render runs inside the popup to render help text.
  # --launch (default) sizes and opens the popup, then enacts the user keystroke
  # if needed. enact lives here because it runs tmux commands (e.g.
  # display-panes) that need the popup gone.
  case "${PHASE}" in
    --render)
      render "${NAME}"
      ;;
    --launch)
      local width height
      read -r width height <<< "$(compute_size)"
      tmux display-popup -E -h "${height}" -w "${width}" \
        -T " ${NAME} " \
        "bash $0 ${NAME} --render"
      try_enact_key "${NAME}"
      ;;
  esac
}

main "$@"
