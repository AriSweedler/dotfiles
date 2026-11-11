# pbcopy, pbpaste and clip-hist for a machine with no system clipboard (a Linux console): the
# same three commands a Mac has (the third stands in for Raycast's Clipboard History), so the
# tmux copy bindings, the git aliases and ari-driving work unchanged. One script under three
# names; it acts by the name it was called as.
#
# The clipboard is a directory of files, one per copy, named by the time of the copy: the
# newest file is the clipboard, the rest are its history. Copying the same text twice in a row
# keeps one entry. Empty input is ignored: tmux's copy-pipe with no selection would otherwise
# blank the clipboard.
#
#   pbcopy                     stdin becomes the clipboard
#   pbpaste                    print the clipboard
#   clip-hist [--paste-to P]   pick an earlier copy with fzf; it becomes the clipboard, and
#                              with --paste-to it is pasted into tmux pane P

dir="${CLIPBOARD_DIR:-${XDG_STATE_HOME:-${HOME}/.local/state}/clipboard}"
readonly dir
readonly keep=200
mkdir -p "${dir}"
chmod 700 "${dir}"

newest() { find "${dir}" -maxdepth 1 -type f -name '[0-9]*' | sort | tail -n 1; }

copy() {
  local incoming latest
  incoming="$(mktemp "${dir}/.incoming.XXXXXX")"
  cat > "${incoming}"
  latest="$(newest)"
  if [[ ! -s "${incoming}" ]] || { [[ -n "${latest}" ]] && cmp -s "${incoming}" "${latest}"; }; then
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

case "${0##*/}" in
  pbcopy) copy ;;
  pbpaste) paste ;;
  clip-hist) history "$@" ;;
  *) echo "clipboard.sh: called as '${0##*/}', expected pbcopy, pbpaste or clip-hist" >&2; exit 1 ;;
esac
