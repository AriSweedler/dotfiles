# open_link — open the URL in the clipboard (or $1). An open-* opener, see open_any.zsh.

(( ${+functions[open_any::input_text]} )) || source "${${(%):-%x}:A:h}/open_any.zsh"

# Input: text. Output: the first URL in it. Claude Code's tool output (marked by ⎿) wraps a
# long URL across lines, so when the match ends at a line end the bare URL-safe tokens on
# the following lines are appended; a line with a space or other prose stops that. A GitHub
# pull request URL is ceded to open-pr when one is installed, so a PR link never satisfies
# two openers.
function open_link::url_from() {
  local text="${1}"
  [[ "${text}" =~ 'https?://[^[:space:]]+' ]] || return 1
  local url="${MATCH}" rest="${text[MEND+1,-1]}"
  if [[ "${text}" == *⎿* && "${rest}" == $'\n'* ]]; then
    local line
    for line in "${(@f)${rest#$'\n'}}"; do
      [[ "${line//⎿/}" =~ '^[[:space:]]*([A-Za-z0-9_./?=&%:#+~-]+)[[:space:]]*$' ]] || break
      url+="${match[1]}"
    done
  fi
  if [[ "${url}" =~ 'https://github.com/[^[:space:]]+/pull/[0-9]+' ]] && (( ${+commands[open-pr]} )); then
    return 1
  fi
  print -r -- "${url}"
}

# Usage: open_link [--check] [<url or text containing one>]   # no arg: clipboard
function open_link() {
  local check=0
  if open_any::take_check_flag "$@"; then check=1; shift; fi
  local text url
  text="$(open_any::input_text "$@")"
  if ! url="$(open_link::url_from "${text}")"; then
    (( check )) && return 1
    log::err "No URL found | text='$(open_any::snippet "${text}")'"
    return 1
  fi
  (( check )) && return 0
  log::info "Opening link | url='${url}'"
  open "${url}"
}
