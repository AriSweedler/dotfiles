# dotfiles/lib/ui.zsh — how fancy human output is, decided once, and the one wrapper around gum.
# Every helper has a plain fallback that is the output when not fancy: no colour, no gum, no tty
# needed. JSON, verdicts, logs and anything a step or launchd runs never come through here.
# The globals (the ARI_DOTFILES_UI seam, ARI_DOTFILES_GUM, the palette, the cache) live in env.zsh.

# 0 when this process may draw: both streams ttys, NO_COLOR empty, TERM not dumb, not launchd, gum found.
# NO_COLOR wins even over ARI_DOTFILES_UI=fancy, so a step subprocess (env NO_COLOR=1) is never fancy.
# The first call decides for the process; call it before any $(…) so a capture inherits the answer.
ui::is_fancy() {
  if [[ -z "${UI_FANCY}" ]]; then
    if ui::_decide; then UI_FANCY=1; else UI_FANCY=0; fi
  fi
  (( UI_FANCY ))
}

ui::_decide() {
  [[ "${ARI_DOTFILES_UI}" != plain ]] || return 1
  [[ -z "${NO_COLOR:-}" ]] || return 1
  [[ -n "${ARI_DOTFILES_GUM}" && -x "${ARI_DOTFILES_GUM}" ]] || return 1
  [[ "${ARI_DOTFILES_UI}" != fancy ]] || return 0
  [[ -t 1 && -t 2 ]] || return 1
  [[ "${TERM:-dumb}" != dumb ]] || return 1
  [[ -z "${ARI_DOTFILES_INVOKED_BY:-}" ]]
}

# The only call site of gum; refuses when not fancy. CLICOLOR_FORCE keeps colour inside a $(…).
ui::_gum() {
  ui::is_fancy || return 1
  CLICOLOR_FORCE=1 "${ARI_DOTFILES_GUM}" "${@}"
}

# Display width wants a UTF-8 locale; launchd and `env -i` give none. Used as `ui::_utf8 || local LC_ALL=…`.
ui::_utf8() { [[ "${LC_ALL:-${LC_CTYPE:-${LANG:-}}}" == *([Uu][Tt][Ff]-8|[Uu][Tt][Ff]8)* ]]; }

# The 256-colour index for a status or house colour name (or an index itself); nothing when unknown.
ui::_index() {
  local name="${UI_STATUS_COLORS[${1}]:-${1}}"
  if [[ -n "${UI_COLORS[${name}]:-}" ]]; then print -r -- "${UI_COLORS[${name}]}"
  elif [[ "${name}" == <0-255> ]]; then print -r -- "${name}"
  fi
}

# Spinner on stderr while the caller works; one at a time, a second start retitles it. [no-op]
# gum runs a watcher that exits when the sentinel goes or this shell dies, so nothing outlives us.
ui::spin_start() {
  local title="${1:-}"
  ui::is_fancy || return 0
  ui::spin_stop
  zmodload -F zsh/system p:sysparams 2>/dev/null || true
  # Taken here: inside the & below, sysparams[pid] would name the subshell that parents gum.
  local sentinel parent="${sysparams[pid]:-$$}"
  sentinel="$(mktemp "${TMPDIR:-/tmp}/dotfiles-spin.XXXXXX" 2>/dev/null)" || return 0
  UI_SPIN_SENTINEL="${sentinel}"
  ui::_gum spin --spinner dot --spinner.foreground "${UI_SPIN_COLOR}" --title "${title}" -- \
    zsh -fc 'zmodload zsh/zselect
      trap '"'"'rm -f -- "${1}"; exit 130'"'"' INT TERM HUP
      while [[ -e "${1}" ]] && kill -0 "${2}" 2>/dev/null; do zselect -t 10; done
      rm -f -- "${1}"' ui-spin-watch "${sentinel}" "${parent}" < /dev/null > /dev/null &
  UI_SPIN_PID="${!}"
  return 0
}

# Stops the spinner and clears its line; idempotent, and returns only once gum has exited. [no-op]
ui::spin_stop() {
  [[ -n "${UI_SPIN_PID}" ]] || return 0
  local pid="${UI_SPIN_PID}"
  if [[ -n "${UI_SPIN_SENTINEL}" ]]; then rm -f -- "${UI_SPIN_SENTINEL}"; fi
  UI_SPIN_PID="" UI_SPIN_SENTINEL=""
  # wait only works in the shell that started it; elsewhere poll until the watcher has noticed.
  if ! wait "${pid}" 2>/dev/null; then
    zmodload zsh/zselect 2>/dev/null || true
    local -i tries=0
    while kill -0 "${pid}" 2>/dev/null && (( tries++ < 50 )); do zselect -t 5; done
  fi
  print -nu2 -- $'\r\e[2K'
  return 0
}

# Text in a status colour (ok warn fail error skip), a house colour name or an index. [text unchanged]
ui::paint() {
  local name="${1}" text="${2:-}" idx bold=""
  if ! ui::is_fancy; then print -r -- "${text}"; return 0; fi
  idx="$(ui::_index "${name}")"
  [[ "${name}" == (error|bold) ]] && bold=$'\e[1m'
  if [[ -z "${idx}" && -z "${bold}" ]]; then print -r -- "${text}"; return 0; fi
  local fg=""
  [[ -z "${idx}" ]] || fg=$'\e[38;5;'"${idx}m"
  print -r -- "${bold}${fg}${text}"$'\e[0m'
}

# A single-cell glyph for a status: ok ✓, warn !, fail ✗, error ‼, skip –. [the status word]
ui::glyph() {
  if ui::is_fancy && [[ -n "${UI_GLYPHS[${1}]:-}" ]]; then print -r -- "${UI_GLYPHS[${1}]}"
  else print -r -- "${1}"
  fi
}

# Text cut to <width> display cells with a trailing …; colour escapes cost nothing. Pure, both modes.
ui::clip() {
  local -i width="${1}"
  local text="${2:-}"
  setopt localoptions extendedglob
  ui::_utf8 || local LC_ALL=en_US.UTF-8
  local bare="${text//${~UI_ANSI_PAT}/}"
  if (( ${(m)#bare} <= width )); then print -r -- "${text}"; return 0; fi
  if (( width <= 0 )); then print -r -- ""; return 0; fi
  local out="" ch esc=0
  local -i used=0 i=1 n=${#text}
  while (( i <= n )); do
    ch="${text[i]}"
    if [[ "${ch}" == $'\e' && "${text[i,n]}" == (#b)(${~UI_ANSI_PAT})* ]]; then
      out+="${match[1]}"; esc=1; (( i += ${#match[1]} )); continue
    fi
    (( used + ${(m)#ch} <= width - 1 )) || break
    out+="${ch}"; (( used += ${(m)#ch} )); (( i++ ))
  done
  out+="…"
  (( esc )) && out+=$'\e[0m'
  print -r -- "${out}"
}

# Terminal width: COLUMNS, else tput cols when a stream is a tty, else 100.
ui::cols() {
  local cols=""
  if [[ "${COLUMNS:-}" == <1-> ]]; then cols="${COLUMNS}"
  elif [[ -t 1 || -t 2 ]]; then cols="$(tput cols 2>/dev/null || true)"
  fi
  [[ "${cols}" == <1-> ]] || cols=100
  print -r -- "${cols}"
}

# ui::box [--title T] [--color N] [--] <line>… — a rounded box, border in colour N, bold title.
# [the title line, then each line indented two spaces]
ui::box() {
  local title="" color="${UI_BOX_COLOR}"
  while (( $# )); do
    case "${1}" in
      --title) title="${2}"; shift 2 ;;
      --color) color="${2}"; shift 2 ;;
      --) shift; break ;;
      *) break ;;
    esac
  done
  if ! ui::is_fancy; then
    [[ -z "${title}" ]] || print -r -- "${title}"
    local line
    for line in "${@}"; do print -r -- "  ${line}"; done
    return 0
  fi
  local -a body=("${@}")
  [[ -z "${title}" ]] || body=($'\e[1m'"${title}"$'\e[0m' "${body[@]}")
  ui::_gum style --border rounded --padding "0 1" --border-foreground "$(ui::_index "${color}")" -- "${body[@]}"
}

# Blocks side by side, tops aligned. [the blocks one after another, a blank line between]
ui::join_h() {
  if ui::is_fancy; then ui::_gum join --horizontal --align top -- "${@}"; return; fi
  local -i i
  for (( i = 1; i <= $#; i++ )); do
    (( i == 1 )) || print -r -- ""
    print -r -- "${@[i]}"
  done
}

# ui::choose [--header H] <option>… — the picked option on stdout; needs a tty on stdin too.
# [returns 1, prints nothing]
ui::choose() {
  local -a header=()
  if [[ "${1:-}" == --header ]]; then header=(--header "${2}"); shift 2; fi
  [[ "${1:-}" != -- ]] || shift
  ui::is_fancy && [[ -t 0 ]] || return 1
  ui::_gum choose "${header[@]}" -- "${@}"
}

# ui::input [--header H] [--placeholder P] — one line of text on stdout; nonzero when cancelled.
# [needs a tty on stdin: the header and "> " on stderr, one line read; returns 1 at EOF or without one]
ui::input() {
  local -a opts=()
  local header="" placeholder=""
  while (( $# )); do
    case "${1}" in
      --header) header="${2}"; opts+=(--header "${2}"); shift 2 ;;
      --placeholder) placeholder="${2}"; opts+=(--placeholder "${2}"); shift 2 ;;
      *) break ;;
    esac
  done
  [[ -t 0 ]] || return 1
  if ui::is_fancy; then
    ui::_gum input "${opts[@]}" --prompt "> " --prompt.foreground "${UI_SPIN_COLOR}" \
      --header.foreground "${UI_BOX_COLOR}" --cursor.foreground "${UI_SPIN_COLOR}" --char-limit 200
    return
  fi
  [[ -z "${header}" ]] || print -ru2 -- "${header}"
  local line=""
  print -nu2 -- "> "
  IFS= read -r line || return 1
  print -r -- "${line}"
}

# ui::confirm <prompt> — a yes/no question: 0 yes, 1 no, 130 cancelled. Never assumes yes.
# [needs a tty on stdin: "<prompt> [y/N] " on stderr, 0 only for y or yes; returns 1 without one]
ui::confirm() {
  [[ -t 0 ]] || return 1
  if ui::is_fancy; then
    ui::_gum confirm --prompt.foreground "${UI_SPIN_COLOR}" --selected.background "${UI_SPIN_COLOR}" \
      --selected.foreground 255 --unselected.background 236 --unselected.foreground 252 -- "${1}"
    return
  fi
  local reply=""
  print -nu2 -- "${1} [y/N] "
  IFS= read -r reply || return 1
  [[ "${reply}" == ([Yy]|[Yy][Ee][Ss]) ]]
}

# A markdown file rendered for the terminal. [cat]
ui::markdown() {
  if ui::is_fancy; then ui::_gum format < "${1}"; else cat -- "${1}"; fi
}

# ui::table <tsv-file|-> [--widths a,b,…] [--no-header] [--no-clip] — aligned columns, two spaces
# apart, header row bold when fancy (--no-header: no header row); each cell clipped to its width
# (0 or missing = as wide as its widest cell), each line to ui::cols (--no-clip: lines kept whole).
# printf-built, not gum table: that strips colour and does not clip. Same layout both modes.
ui::table() {
  local src="-" widths_arg=""
  local -i header=1 clip=1
  while (( $# )); do
    case "${1}" in
      --widths) widths_arg="${2}"; shift 2 ;;
      --widths=*) widths_arg="${1#--widths=}"; shift ;;
      --no-header) header=0; shift ;;
      --no-clip) clip=0; shift ;;
      *) src="${1}"; shift ;;
    esac
  done
  setopt localoptions extendedglob
  ui::_utf8 || local LC_ALL=en_US.UTF-8
  local -a rows caps widths cells
  if [[ "${src}" == - ]]; then rows=("${(@f)$(cat)}"); else rows=("${(@f)$(<"${src}")}"); fi
  rows=("${(@)rows:#}")
  (( ${#rows} )) || return 0
  caps=("${(@s:,:)widths_arg}")
  local row cell bare
  local -i c ncols=0 w
  for row in "${rows[@]}"; do
    cells=("${(@ps:\t:)row}")
    (( ${#cells} > ncols )) && ncols=${#cells}
    for (( c = 1; c <= ${#cells}; c++ )); do
      bare="${cells[c]//${~UI_ANSI_PAT}/}"
      w=${(m)#bare}
      (( w > ${widths[c]:-0} )) && widths[c]=${w}
    done
  done
  for (( c = 1; c <= ncols; c++ )); do
    [[ "${caps[c]:-}" == <1-> ]] && (( caps[c] < ${widths[c]:-0} )) && widths[c]=${caps[c]}
  done
  local -i cols first=1
  cols="$(ui::cols)"
  local line pad fancy=0
  ui::is_fancy && fancy=1
  for row in "${rows[@]}"; do
    cells=("${(@ps:\t:)row}")
    line=""
    for (( c = 1; c <= ncols; c++ )); do
      cell="$(ui::clip "${widths[c]:-0}" "${cells[c]:-}")"
      (( c == 1 )) || line+="  "
      line+="${cell}"
      if (( c < ncols )); then
        bare="${cell//${~UI_ANSI_PAT}/}"
        printf -v pad '%*s' $(( ${widths[c]:-0} - ${(m)#bare} )) ''
        line+="${pad}"
      fi
    done
    line="${line%%[ ]##}"
    (( ! clip )) || line="$(ui::clip "${cols}" "${line}")"
    if (( first && fancy && header )); then line=$'\e[1m'"${line}"$'\e[0m'; fi
    first=0
    print -r -- "${line}"
  done
}
