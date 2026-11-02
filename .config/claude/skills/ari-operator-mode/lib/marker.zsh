# marker.zsh — one per-session marker file under <root>/operator-mode, shared by bin/mode.zsh (ON-),
# bin/pending.zsh (PENDING-) and bin/away.zsh (AWAY-): the state operator mode must not lose to a
# compaction lives on disk, never in the transcript. Sourced, never run; the caller owns parsing,
# validation and logging. A marker holds one text (a UTC time, the typed row, his words).

#######################################
# The marker's path.
# Arguments: $1 = root dir; $2 = key (ON, PENDING, AWAY); $3 = session id
#######################################
marker_path() { print -r -- "${1}/operator-mode/${2}-${3}"; }

#######################################
# Write the marker (idempotent: overwrites).
# Arguments: $1 = marker path; $2 = the text
#######################################
marker_set() {
  mkdir -p "${1:h}"
  print -r -- "${2}" > "${1}"
}

#######################################
# Remove the marker when it exists.
# Arguments: $1 = marker path
# Returns: 0 when it was removed; 3 when there was none
#######################################
marker_clear() {
  if [[ -f "${1}" ]]; then rm -f "${1}"; return 0; fi
  return 3
}

#######################################
# Print the marker's text.
# Arguments: $1 = marker path
# Returns: 0 when it exists; 3 when there is none (prints nothing)
#######################################
marker_show() {
  if [[ -f "${1}" ]]; then print -r -- "$(<"${1}")"; return 0; fi
  return 3
}
