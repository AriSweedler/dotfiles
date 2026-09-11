# double_cd — short `c<name>` commands that jump to important dirs, defined by JSON.
#
# Sources: ${XDG_CONFIG_HOME}/double_cd/*.json (every machine), ${XDG_DATA_HOME}/double_cd/*.json
# (this machine), and DOUBLE_CD_DIRS (colon list of extra dirs). DOUBLE_CD_IGNORE_DIR_GLOBAL /
# DOUBLE_CD_IGNORE_DIR_LOCAL skip a tier. Same knobs as tmux-oneshot.
#
# Each file is a JSON list. Two entry shapes:
#   {"name": "tmp", "dir": "~/Desktop/workspace", "text": "scratch projects"}
#     ctmp                 pick a subdir with fzf ('.' is the dir itself)
#     ctmp <sub>           cd straight in when it exists, else fzf with that query
#     ctmp --new <sub>     create it first
#   {"name": "h", "dirs": ["~/h/source/a", "~/h/source/b"], "label": "hyp", "text": "…", "default": true}
#     ch                   cycle to the next checkout (wraps; the first when outside them)
#     ch <N>               the Nth checkout
#     ch <query>           fzf over the checkouts
#     The same entry drives `repo` (index / cycle / rename / hop / ready); `default` names the set
#     `repo` uses when $PWD is in none of them.
# A leading ~ in a path is expanded. Nothing else is: keep paths literal so `repo`, which runs
# outside the interactive shell, sees the same dirs.
# `dcd` lists every command with its dir and text.

(( ${+functions[log::info]} )) || source "${${(%):-%x}:A:h}/log.zsh"

typeset -gA DOUBLE_CD_DIR DOUBLE_CD_TEXT DOUBLE_CD_KIND

function double_cd::dirs() {
  [[ -z "${DOUBLE_CD_IGNORE_DIR_GLOBAL:-}" ]] && print -r -- "${XDG_CONFIG_HOME:-${HOME}/.config}/double_cd"
  [[ -z "${DOUBLE_CD_IGNORE_DIR_LOCAL:-}" ]]  && print -r -- "${XDG_DATA_HOME:-${HOME}/.local/share}/double_cd"
  local d
  for d in ${(s.:.)${DOUBLE_CD_DIRS:-}}; do
    print -r -- "${d/#\~/${HOME}}"
  done
  return 0
}

function double_cd::files() {
  local d
  for d in ${(f)"$(double_cd::dirs)"}; do
    print -rl -- "${d}"/*.json(N.)
  done
}

# Output: one compact JSON object per line, every entry from every file, in file order.
function double_cd::entries() {
  local -a files=(${(f)"$(double_cd::files)"})
  (( ${#files} )) || return 0
  jq -c -s 'add[]' "${files[@]}"
}

function double_cd::expand() {
  print -r -- "${1/#\~/${HOME}}"
}

# Seams: tests replace these.
function double_cd::_fzf() { fzf "$@" }
function double_cd::_after_cd() {
  ls
  (( ${+functions[tmux::rename-window]} )) && tmux::rename-window "$@"
  return 0
}

# Input: name, then the user's args. The `dir` shape.
function double_cd::single() {
  local name="${1}"; shift
  local base; base="$(double_cd::expand "${DOUBLE_CD_DIR[${name}]}")"
  local new_dirname="" query=""
  while (( $# > 0 )); do
    case "${1}" in
      --new) new_dirname="${2:?--new needs a name}"; shift 2 ;;
      *) query="${1}"; shift ;;
    esac
  done
  if [[ ! -d "${base}" ]]; then
    log::err "Base dir is missing | cmd='c${name}' dir='${base}'"
    return 1
  fi

  local selected=""
  if [[ -n "${new_dirname}" ]]; then
    if [[ -d "${base}/${new_dirname}" ]]; then
      log::info "Directory already exists | dir='${base}/${new_dirname}'"
    else
      mkdir -p "${base}/${new_dirname}" || return 1
      log::info "Created directory | dir='${base}/${new_dirname}'"
    fi
    selected="${new_dirname}"
  elif [[ -n "${query}" && -d "${base}/${query}" ]]; then
    selected="${query}"
  else
    local -a options=("${base}"/*(N/:t) .)
    selected="$(print -rl -- "${options[@]}" | double_cd::_fzf --select-1 --exit-0 --query="${query}")"
    if [[ -z "${selected}" ]]; then
      log::warn "Nothing selected | cmd='c${name}'"
      return 1
    fi
  fi

  cd "${base}/${selected}" || return 1
  [[ "${selected}" == . ]] && log::info "Use --new <name> to create and enter a subdir"
  double_cd::_after_cd "c${name} ${selected}"
}

# Input: name, then at most one arg. The `dirs` shape; `repo` owns the cycling logic.
function double_cd::multi() {
  local name="${1}"; shift
  local dest
  if (( $# == 0 )); then
    dest="$(repo cycle --set "${name}")" || return 1
  elif [[ "${1}" == <-> ]]; then
    dest="$(repo list --set "${name}" | sed -n "${1}p")"
    if [[ -z "${dest}" ]]; then
      log::err "No such checkout | cmd='c${name}' index='${1}'"
      return 1
    fi
  else
    dest="$(repo list --set "${name}" | double_cd::_fzf --select-1 --exit-0 --query="${1}")"
    if [[ -z "${dest}" ]]; then
      log::warn "Nothing selected | cmd='c${name}'"
      return 1
    fi
  fi
  cd "${dest}" || return 1
  ls
  repo rename --set "${name}"
}

function _double_cd() {
  local name="${words[1]#c}"
  [[ "${DOUBLE_CD_KIND[${name}]}" == dir ]] || return 1
  local base; base="$(double_cd::expand "${DOUBLE_CD_DIR[${name}]}")"
  _files -W "${base}" -/
}

# Defines c<name> for every entry. Names are restricted so they cannot break the eval below.
function double_cd::define() {
  DOUBLE_CD_DIR=() DOUBLE_CD_TEXT=() DOUBLE_CD_KIND=()
  local line name kind dir text
  while IFS=$'\t' read -r name kind dir text; do
    if [[ ! "${name}" =~ '^[A-Za-z0-9_-]+$' ]]; then
      log::warn "Skipping double_cd entry with a bad name | name='${name}'"
      continue
    fi
    DOUBLE_CD_DIR[${name}]="${dir}" DOUBLE_CD_TEXT[${name}]="${text}" DOUBLE_CD_KIND[${name}]="${kind}"
    if [[ "${kind}" == dir ]]; then
      eval "function c${name}() { double_cd::single '${name}' \"\$@\" }"
      (( ${+functions[compdef]} )) && compdef _double_cd "c${name}"
    else
      eval "function c${name}() { double_cd::multi '${name}' \"\$@\" }"
    fi
  done < <(double_cd::entries | jq -r '[.name, (if .dirs then "dirs" else "dir" end), (.dir // (.dirs | join(":"))), (.text // "")] | @tsv')
  return 0
}

# `dcd`: the commands this shell has.
function dcd() {
  local name
  for name in ${(ko)DOUBLE_CD_DIR}; do
    printf '  %-10s %-45s %s\n' "c${name}" "${DOUBLE_CD_DIR[${name}]}" "${DOUBLE_CD_TEXT[${name}]}"
  done
}

double_cd::define
