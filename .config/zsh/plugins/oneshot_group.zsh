# oneshot_group — publish a family of shell commands as a tmux-oneshot group (Hyper+O, C-a C-k)
# without writing JSON by hand. Groups land in the engine's generated tier,
# ${XDG_STATE_HOME}/tmux_oneshot/generated/<group>.json, rewritten only when the rows changed.
#
#   oneshot_group::aliases <group> <alias-prefix> [--fn-prefix P] [--window W] [--autodismiss]
#                          [--key K] [--text T]
#     One row per alias named <alias-prefix>*: leaf = the alias minus the prefix (the whole
#     alias when nothing is left), text = its target minus P, cmd = `irun <alias>` (aliases
#     live in interactive shells). Aliases whose target starts with P followed by _ are
#     machinery and skipped. --key K opens the group straight from the picker; --text T shows
#     on the group row ahead of its leaves, "▸ T · a, b, c". One line in a plugin, next to the family:
#       oneshot_group::aliases vi_ vi_ --fn-prefix vi_:: --window vi_ --key ctrl-v
#   oneshot_group::rows <group> [--window W] [--autodismiss] [--key K] [--text T]
#     The general form, rows on stdin as "leaf\ttext\tcmd" lines.
#
# Both defer to the first prompt, so families defined by later plugins (the local tier) are
# complete when the rows are computed. oneshot_group::flush runs the pending publishers now.

(( ${+functions[log::info]} )) || source "${${(%):-%x}:A:h}/log.zsh"

typeset -ga ONESHOT_GROUP_PENDING=()

# Input: group, window, autodismiss, key, text; rows on stdin. Writes <group>.json when the
# content differs. A key or text adds the "<group>/" header entry the engine folds into the
# group row.
function oneshot_group::_write() {
  local group="${1}" window="${2}" autodismiss="${3}" key="${4:-}" text="${5:-}" json
  json="$(jq -R -s --arg w "${window}" --argjson a "${autodismiss}" --arg g "${group}" --arg k "${key}" --arg t "${text}" '
    (if $k != "" or $t != "" then
       [{menu: ({name: ($g + "/")} + (if $t != "" then {text: $t} else {} end))} + (if $k != "" then {key: $k} else {} end)]
     else [] end)
    + (split("\n") | map(select(length > 0) | split("\t")
      | {menu: {name: ($g + "/" + .[0]), text: .[1]}, cmd: .[2]}
      + (if $w != "" then {window: $w} else {} end)
      + (if $a then {autodismiss: true} else {} end)))')" || return 1
  local file="${XDG_STATE_HOME:-${HOME}/.local/state}/tmux_oneshot/generated/${group}.json"
  if [[ -f "${file}" ]] && [[ "$(< "${file}")" == "${json}" ]]; then
    return 0
  fi
  mkdir -p "${file:h}" || return 1
  print -r -- "${json}" > "${file}"
}

# Sets ONESHOT_GROUP_OPT_*. Exit 1 on an unknown option.
function oneshot_group::_parse_opts() {
  ONESHOT_GROUP_OPT_WINDOW="" ONESHOT_GROUP_OPT_AUTODISMISS=false ONESHOT_GROUP_OPT_FN_PREFIX=""
  ONESHOT_GROUP_OPT_KEY="" ONESHOT_GROUP_OPT_TEXT=""
  while (( $# > 0 )); do
    case "${1}" in
      --window) ONESHOT_GROUP_OPT_WINDOW="${2:?--window needs a name}"; shift 2 ;;
      --autodismiss) ONESHOT_GROUP_OPT_AUTODISMISS=true; shift ;;
      --fn-prefix) ONESHOT_GROUP_OPT_FN_PREFIX="${2:?--fn-prefix needs a prefix}"; shift 2 ;;
      --key) ONESHOT_GROUP_OPT_KEY="${2:?--key needs an fzf key name}"; shift 2 ;;
      --text) ONESHOT_GROUP_OPT_TEXT="${2:?--text needs a description}"; shift 2 ;;
      *) log::err "oneshot_group: unknown option | option='${1}'"; return 1 ;;
    esac
  done
}

# Output: "leaf\ttext\tcmd" per matching alias, alias-sorted.
function oneshot_group::_alias_rows() {
  local prefix="${1}" fn_prefix="${2}" a target leaf
  for a in ${(ko)aliases}; do
    [[ "${a}" == ${prefix}* ]] || continue
    target="${aliases[${a}]}"
    if [[ -n "${fn_prefix}" ]]; then
      [[ "${target}" == ${fn_prefix}* ]] || continue
      [[ "${target}" == ${fn_prefix}_* ]] && continue
    fi
    leaf="${a#${prefix}}"
    [[ -n "${leaf}" ]] || leaf="${a}"
    print -r -- "${leaf}	${target#${fn_prefix}}	irun ${a}"
  done
}

function oneshot_group::aliases() {
  local group="${1:?group}" prefix="${2:?alias prefix}"; shift 2
  oneshot_group::_parse_opts "$@" || return 1
  ONESHOT_GROUP_PENDING+=("oneshot_group::_alias_rows ${(q)prefix} ${(q)ONESHOT_GROUP_OPT_FN_PREFIX} | oneshot_group::_write ${(q)group} ${(q)ONESHOT_GROUP_OPT_WINDOW} ${ONESHOT_GROUP_OPT_AUTODISMISS} ${(q)ONESHOT_GROUP_OPT_KEY} ${(q)ONESHOT_GROUP_OPT_TEXT}")
  oneshot_group::_arm
}

# Rows are captured now; the write still waits for the first prompt.
function oneshot_group::rows() {
  local group="${1:?group}"; shift
  oneshot_group::_parse_opts "$@" || return 1
  local rows; rows="$(cat)"
  ONESHOT_GROUP_PENDING+=("print -r -- ${(q)rows} | oneshot_group::_write ${(q)group} ${(q)ONESHOT_GROUP_OPT_WINDOW} ${ONESHOT_GROUP_OPT_AUTODISMISS} ${(q)ONESHOT_GROUP_OPT_KEY} ${(q)ONESHOT_GROUP_OPT_TEXT}")
  oneshot_group::_arm
}

function oneshot_group::_arm() {
  [[ -o interactive ]] || return 0
  autoload -Uz add-zsh-hook
  add-zsh-hook precmd oneshot_group::_flush_once
}

function oneshot_group::flush() {
  local job
  for job in "${ONESHOT_GROUP_PENDING[@]}"; do
    eval "${job}" || log::warn "oneshot_group: publish failed | job='${job}'"
  done
  ONESHOT_GROUP_PENDING=()
}

function oneshot_group::_flush_once() {
  add-zsh-hook -d precmd oneshot_group::_flush_once
  oneshot_group::flush
}
