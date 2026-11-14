# pbcopy, pbpaste, clip-hist and xclip for a machine with no system clipboard (a Linux console):
# the same three commands a Mac has (the third stands in for Raycast's Clipboard History), so
# the tmux copy bindings, the git aliases and ari-driving work unchanged, and an xclip for the
# tools that look for one by name (gh). One script under four names; it acts by the name it was
# called as.
#
# Two clipboards get every copy, because a Linux machine has two kinds of reader:
# - At its own console (kmscon on the monitor) there is no display server and no OSC 52, so the
#   clipboard is a directory of files, one per copy, named by the time of the copy: the newest
#   file is the clipboard, the rest are its history. Copying the same text twice in a row keeps
#   one entry. pbpaste and xclip -o read it.
# - Over ssh, the clipboard is the one on the machine Ari types at (a Mac), reached with an
#   OSC 52 escape written to the terminal. Inside tmux the escape is wrapped in tmux's
#   passthrough, which tmux.nix turns on off a Mac. The terminal is written to, never read, so
#   pbpaste over ssh still reads this machine's files.
# Empty input is ignored: tmux's copy-pipe with no selection would otherwise blank the clipboard.
#
#   pbcopy                     stdin becomes the clipboard
#   pbpaste                    print the clipboard
#   clip-hist [--paste-to P]   pick an earlier copy with fzf; it becomes the clipboard, and
#                              with --paste-to it is pasted into tmux pane P
#   xclip [-i|-o] [FILE…]      xclip's own flags, enough for gh (xclip_compat lists them)
#
# CLIPBOARD_TTY names where the escape goes (the tests point it at a file); it defaults to
# /dev/tty, and with no terminal there (a cron job, tmux's own copy-pipe) the copy writes only
# the file.

dir="${CLIPBOARD_DIR:-${XDG_STATE_HOME:-${HOME}/.local/state}/clipboard}"
readonly dir
readonly keep=200
# Each terminal drops an OSC 52 escape past a length of its own; past this one the copy goes
# only to the files.
readonly osc52_max=100000
mkdir -p "${dir}"
chmod 700 "${dir}"

newest() { find "${dir}" -maxdepth 1 -type f -name '[0-9]*' | sort | tail -n 1; }

# The OSC 52 escape that sets the terminal's clipboard to stdin, plain or wrapped for tmux's
# passthrough, which wants every ESC inside it doubled.
osc52() {
  local encoded
  encoded="$(base64 -w 0)"
  if (( ${#encoded} > osc52_max )); then
    return 0
  fi
  if [[ -n "${TMUX:-}" ]]; then
    # \134 is the backslash of the closing ESC \.
    printf '\ePtmux;\e\e]52;c;%s\a\e\134' "${encoded}"
  else
    printf '\e]52;c;%s\a' "${encoded}"
  fi
}

copy() {
  local incoming latest
  incoming="$(mktemp "${dir}/.incoming.XXXXXX")"
  cat > "${incoming}"
  if [[ ! -s "${incoming}" ]]; then
    rm -f "${incoming}"
    return 0
  fi
  # The terminal's clipboard gets even a repeated copy: something else may have set it since.
  { osc52 < "${incoming}" > "${CLIPBOARD_TTY:-/dev/tty}"; } 2>/dev/null || true
  latest="$(newest)"
  if [[ -n "${latest}" ]] && cmp -s "${incoming}" "${latest}"; then
    rm -f "${incoming}"
    return 0
  fi
  mv "${incoming}" "${dir}/$(date +%s%N)"
  find "${dir}" -maxdepth 1 -type f -name '[0-9]*' | sort | head -n "-${keep}" | xargs -r rm -f
}

paste() {
  local latest
  latest="$(newest)"
  if [[ -n "${latest}" ]]; then
    cat "${latest}"
  fi
}

history() {
  local pane="" entry picked
  if [[ "${1:-}" == "--paste-to" ]]; then
    pane="${2:?--paste-to needs a tmux pane}"
  fi
  # One line per copy, newest first: its file name, then its first line.
  picked="$(
    find "${dir}" -maxdepth 1 -type f -name '[0-9]*' | sort -r | while read -r entry; do
      printf '%s\t%s\n' "${entry##*/}" "$(head -n 1 "${entry}" | cut -c 1-200)"
    done | fzf --delimiter='\t' --with-nth=2.. --no-sort --prompt='clipboard> ' \
      --preview="cat ${dir@Q}/{1}" --preview-window='down,60%,wrap'
  )" || return 0
  entry="${dir}/${picked%%$'\t'*}"
  # The pick moves to the top of the history instead of appearing twice.
  if [[ "${entry}" != "$(newest)" ]]; then
    mv "${entry}" "${dir}/$(date +%s%N)"
  fi
  if [[ -n "${pane}" ]]; then
    tmux load-buffer -b clip-hist "$(newest)"
    tmux paste-buffer -d -p -b clip-hist -t "${pane}"
  fi
}

# xclip's flags as gh and similar tools pass them (`xclip -selection clipboard`, `xclip -o
# -selection clipboard`), with xclip's own short forms. Every selection is the one clipboard.
# -t, -d and -l take a value and change nothing here; -quiet, -silent, -verbose and -noutf8
# change nothing either.
xclip_compat() {
  local mode=in filter=false strip=false
  local -a files=()
  while (( $# > 0 )); do
    case "$1" in
      -i|-in) mode=in ;;
      -o|-out) mode=out ;;
      -se|-sel|-selection|-t|-target|-d|-display|-l|-loops)
        if (( $# < 2 )); then
          echo "xclip: $1 needs a value" >&2
          return 1
        fi
        shift ;;
      -f|-filter) filter=true ;;
      -r|-rmlastnl) strip=true ;;
      -q|-quiet|-silent|-verbose|-noutf8) ;;
      -h|-help) echo "xclip (linux-clipboard): -i|-in, -o|-out, -selection NAME, -f, -r, FILE..."; return 0 ;;
      -version) echo "xclip (linux-clipboard shim)"; return 0 ;;
      -*) echo "xclip: unsupported flag $1 (linux-clipboard)" >&2; return 1 ;;
      *) files+=("$1") ;;
    esac
    shift
  done
  if [[ "${mode}" == out ]]; then
    paste
    return 0
  fi
  local input
  input="$(mktemp)"
  cat -- "${files[@]:--}" > "${input}"
  if [[ "${strip}" == true ]] && [[ "$(tail -c 1 "${input}"; echo x)" == $'\nx' ]]; then
    truncate -s -1 "${input}"
  fi
  copy < "${input}"
  if [[ "${filter}" == true ]]; then
    cat "${input}"
  fi
  rm -f "${input}"
}

case "${0##*/}" in
  pbcopy) copy ;;
  pbpaste) paste ;;
  clip-hist) history "$@" ;;
  xclip) xclip_compat "$@" ;;
  *) echo "clipboard.sh: called as '${0##*/}', expected pbcopy, pbpaste, clip-hist or xclip" >&2; exit 1 ;;
esac
