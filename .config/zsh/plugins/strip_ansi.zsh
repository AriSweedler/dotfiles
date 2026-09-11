# strip_ansi — remove ANSI escape sequences (colors, cursor moves, erase) from text.
#
#   strip_ansi              stdin → stdout, stripped
#   strip_ansi_tee <file>   stdin → stderr verbatim (colors kept) and appended to <file> stripped:
#                           the one pipeline member a script needs to log a colored stream.
# Functions, not a script, so a pipeline forks the running shell instead of starting a new one.
# ~/.config/bin/strip-ansi wraps strip_ansi for use outside zsh.

# Input: one line. Output: the line without CSI sequences (ESC [ … final byte) and the
# two-byte escapes (ESC + one of @ … _).
function strip_ansi::line() {
  setopt localoptions extendedglob
  local csi=$'\e\\[[0-9;?]#[@-~]'
  print -r -- "${${1//${~csi}/}//$'\e'[@-Z\\-_]/}"
}

function strip_ansi() {
  local line
  while IFS= read -r line || [[ -n "${line}" ]]; do
    strip_ansi::line "${line}"
  done
}

function strip_ansi_tee() {
  local file="${1:?strip_ansi_tee: file required}" line
  while IFS= read -r line || [[ -n "${line}" ]]; do
    print -r -- "${line}" >&2
    strip_ansi::line "${line}"
  done >> "${file}"
}
