# fzf_groups.zsh — one screen of exclusive option groups: the builder behind tmux-oneshot's
# `groups`. Each group is a block, its label as the title, one row per option, "● [k] label",
# a blank line between blocks; the screen stays up while the selection changes and only ⏎
# leaves it with an answer. The Karabiner arg builder (karabiner.ts/src/utils/argbuilder.ts)
# has the same shape, drawn in Notification Center.
#
#   a key      selects that option within its group, from any row, in any order
#   space      selects the highlighted row
#   ⏎          accept: print the selection as JSON and exit 0
#   esc        back: exit FZF_GROUP_BACK_RC, nothing printed
#   ↑ ↓        move between options; the title rows are skipped
# The command the selection assembles shows at the bottom and follows every change.
# An option with a `prompt` asks for a value in place (a one-line fzf editor: ⏎ accepts, esc
# returns to the screen with the selection as it was); the answer replaces {} in its value
# and shows on the row, "other…: 300".
#
# Usage:
#   fzf_groups::pick '{"groups":[{"name":"words","default":"5","options":[
#       {"key":"5","label":"50 words","value":"--words 50"},
#       {"key":"o","label":"other…","prompt":"words: ","value":"--words {}"}]}]}' \
#       --title typing --cmd 'typing-test'
#   → {"words":"--words 50"}          (the footer read: typing-test --words 50)
# Spec: groups[]: name, label (default: name), default (an option key), options[]: key (one
# letter or digit, unique across groups), label, value (default "{}"), prompt (optional).
#
# fzf re-renders through bindings that run this file as a script (the guard at the bottom):
# `zsh fzf_groups.zsh render|pick|pick-row <state> …`. The state is one JSON file holding the
# spec, the selection and the typed answers, so every callback is one jq call. Items are
# NUL-separated (--read0) so a block's title item can carry the blank line above it; a
# title item has no key column, which is how the arrow bindings know to step over it.
# Needs fzf 0.62+ (--no-input).

(( ${+functions[log::info]} )) || source "${${(%):-%x}:A:h}/log.zsh"
(( ${+FZF_GROUP_BACK_RC} )) || source "${${(%):-%x}:A:h}/fzf_group.zsh"

typeset -g FZF_GROUPS_SELF="${${(%):-%x}:A}"

# Seam for tests. Input: fzf arguments; rows on stdin.
function fzf_groups::_fzf() {
  fzf "$@"
}

# The one-line editor a prompt option opens: fzf with no rows, the query is the value. ⏎
# prints it (rc 0); esc exits 130. Input: <prompt> <current value>. Seam for tests.
function fzf_groups::_editor() {
  local prompt="${1}" current="${2}" out
  out="$(fzf_groups::_fzf --layout=reverse --no-info --print-query --query "${current}" \
          --prompt "${prompt}" --header "⏎ accepts · esc: back" \
          --bind 'enter:print-query' --bind 'alt-enter:print-query' </dev/null)" || return $?
  print -r -- "${out%%$'\n'*}"
}

# Pure. Input: the spec JSON. Output: the first problem, or nothing when the spec is sound.
function fzf_groups::_validate() {
  jq -r '
    def problems:
      (if (.groups // [] | length) == 0 then "no groups" else empty end),
      (.groups[] | select((.name // "") == "") | "a group has no name"),
      (.groups[] | select((.options // [] | length) == 0) | "group has no options | group=\(.name)"),
      (.groups[] | select(.default == null) | "group has no default | group=\(.name)"),
      (.groups[] | select(.default != null) | .default as $d
        | select(([.options[].key] | index($d)) == null)
        | "default is not an option key | group=\(.name) default=\($d)"),
      (.groups[].options[] | select((.key // "" | test("^[A-Za-z0-9]$")) | not)
        | "option key must be one letter or digit | key=\(.key // "")"),
      ([.groups[].options[].key] | group_by(.) | map(select(length > 1) | .[0])[]
        | "option key used twice | key=\(.)");
    [problems] | .[0] // empty' <<< "${1:?spec}"
}

# Input: <state file>. Output: NUL-terminated items, per group a title item "\t\t<bold
# label>" (with a leading newline from the second group on, the blank line between blocks)
# then one item per option, "<group>\t<key>\t● [k] text". Columns 3.. are what fzf shows.
function fzf_groups::_render() {
  jq -j '
    .sel as $sel | .typed as $typed
    | [.spec.groups | to_entries[] | .key as $i | .value as $g
       | ("\t\t" + (if $i == 0 then "" else "\n" end) + "\u001b[1m" + ($g.label // $g.name) + "\u001b[0m"),
         ($g.options[]
          | (if .prompt then .label + (if ($typed[.key] // "") != "" then ": " + $typed[.key] else "" end)
             else .label end) as $text
          | "\($g.name)\t\(.key)\t\(if $sel[$g.name] == .key then "●" else "○" end) [\(.key)] \($text)")]
    | .[] | . + "\u0000"' \
    "${1:?state}"
}

# Input: <state file> <jq filter> [jq args…]. Rewrites the state through the filter, whole
# file at a time, so a half-written state is never read.
function fzf_groups::_update() {
  local state="${1:?state}" filter="${2:?filter}"
  shift 2
  jq "$@" "${filter}" "${state}" > "${state}.tmp" && mv "${state}.tmp" "${state}"
}

# Input: <state file> <option key>. Selects the option in its group; a prompt option asks for
# its value first and is selected only when one was given. An unknown key is ignored.
function fzf_groups::_pick() {
  local state="${1:?state}" key="${2:?key}" group prompt
  group="$(jq -r --arg k "${key}" '[.spec.groups[] | select(any(.options[]; .key == $k)) | .name][0] // ""' "${state}")"
  [[ -n "${group}" ]] || return 0
  prompt="$(jq -r --arg k "${key}" '[.spec.groups[].options[] | select(.key == $k) | .prompt // ""][0] // ""' "${state}")"
  if [[ -z "${prompt}" ]]; then
    fzf_groups::_update "${state}" '.sel[$g] = $k' --arg g "${group}" --arg k "${key}"
    return 0
  fi
  local current typed rc=0
  current="$(jq -r --arg k "${key}" '.typed[$k] // ""' "${state}")"
  typed="$(fzf_groups::_editor "${prompt}" "${current}")" || rc=$?
  if (( rc != 0 )) || [[ -z "${typed}" ]]; then
    return 0
  fi
  fzf_groups::_update "${state}" '.typed[$k] = $t | .sel[$g] = $k' --arg g "${group}" --arg k "${key}" --arg t "${typed}"
}

# Input: <state file> <row as rendered>. The key is the row's second column; a title item has
# none and is ignored.
function fzf_groups::_pick_row() {
  local state="${1:?state}" row="${2?row}" key
  key="${row#*$'\t'}"
  key="${key%%$'\t'*}"
  [[ -n "${key}" && "${key}" != "${row}" ]] || return 0
  fzf_groups::_pick "${state}" "${key}"
}

# Input: <state file>. Output: the command the selection assembles, for the footer: --cmd, then
# each group's value in order, the values colored. Two lines (cmd, then the values indented)
# when one would not fit fzf's width, which fzf passes as FZF_COLUMNS.
function fzf_groups::_command() {
    local state="${1:?state}" cmd values line
    cmd="$(jq -r '.cmd // ""' "${state}")"
    values="$(jq -r '.sel as $sel | .typed as $typed
      | [.spec.groups[] | .name as $n | .options[] | select(.key == $sel[$n])
         | ($typed[.key] // "") as $t | ((.value // "{}") | gsub("\\{\\}"; $t))] | join(" ")' "${state}")"
    line="${cmd:+${cmd} }${values}"
    if [[ -n "${cmd}" && -n "${FZF_COLUMNS:-}" ]] && (( ${#line} > FZF_COLUMNS - 2 )); then
        print -r -- "${cmd}"
        print -r -- $'  \e[36m'"${values}"$'\e[0m'
    else
        print -r -- "${cmd:+${cmd} }"$'\e[36m'"${values}"$'\e[0m'
    fi
}

# Input: <state file>. Output: {group: value} with {} in a prompt option's value replaced by
# what was typed.
function fzf_groups::_selection() {
  jq -c '
    .sel as $sel | .typed as $typed
    | [.spec.groups[] | .name as $n | .options[] | select(.key == $sel[$n])
       | ($typed[.key] // "") as $t
       | {key: $n, value: ((.value // "{}") | gsub("\\{\\}"; $t))}]
    | from_entries' "${1:?state}"
}

# Input: <spec JSON> [--title T] [--cmd C]. Output: the selection JSON on ⏎ (rc 0); nothing
# and FZF_GROUP_BACK_RC on esc; nothing and rc 1 on a bad spec or a broken fzf. --cmd is the
# command the values complete, shown in the footer.
function fzf_groups::pick() {
  local spec="${1:?spec}" title="builder" cmd=""
  shift
  while (( $# > 0 )); do
    case "${1}" in
      --title) title="${2:?--title needs a value}"; shift 2 ;;
      --cmd)   cmd="${2?--cmd needs a value}"; shift 2 ;;
      *) log::err "fzf_groups::pick: unknown option | option='${1}'"; return 1 ;;
    esac
  done
  local problem
  problem="$(fzf_groups::_validate "${spec}")"
  if [[ -n "${problem}" ]]; then
    log::err "fzf_groups: bad spec | ${problem}"
    return 1
  fi

  local state
  state="$(mktemp "${TMPDIR:-/tmp}/fzf_groups.XXXXXX")" || return 1
  jq -c --arg cmd "${cmd}" '{spec: ., cmd: $cmd, sel: ([.groups[] | {key: .name, value: .default}] | from_entries), typed: {}}' <<< "${spec}" > "${state}"

  local cb="zsh ${(q)FZF_GROUPS_SELF}"
  # Every change re-renders the rows and the footer's command.
  local refresh="reload(${cb} render ${(q)state})+transform-footer(${cb} command ${(q)state})"
  local -a binds
  local line key has_prompt
  # A key with no prompt updates the state silently; one with a prompt takes the terminal.
  for line in ${(f)"$(jq -r '.groups[].options[] | "\(.key)\t\(if .prompt then 1 else 0 end)"' <<< "${spec}")"}; do
    key="${line%%$'\t'*}"; has_prompt="${line#*$'\t'}"
    if [[ "${has_prompt}" == 1 ]]; then
      binds+=(--bind "${key}:execute(${cb} pick ${(q)state} ${(q)key})+${refresh}")
    else
      binds+=(--bind "${key}:execute-silent(${cb} pick ${(q)state} ${(q)key})+${refresh}")
    fi
  done
  binds+=(--bind "space:execute(${cb} pick-row ${(q)state} {})+${refresh}")
  # ⏎ keeps fzf's accept. The cursor starts on the first option (item 1 is the first title,
  # --sync so the list is there when start fires), the footer is filled in, and the cursor
  # steps over a title item, which has no key column, in whichever direction it was moving.
  binds+=(--bind "start:pos(2)+transform-footer(${cb} command ${(q)state})")
  local k
  for k in down ctrl-j ctrl-n; do binds+=(--bind "${k}:down+transform([ -z {2} ] && echo down)"); done
  for k in up ctrl-k ctrl-p; do binds+=(--bind "${k}:up+transform([ -z {2} ] && echo up)"); done

  local rc=0
  fzf_groups::_render "${state}" | fzf_groups::_fzf --no-input --layout=reverse --no-info --cycle \
      --read0 --ansi --sync --delimiter $'\t' --with-nth '3..' --footer-border=top \
      --header "(${title}) — ⏎ run · esc back · a key or space selects" \
      "${binds[@]}" >/dev/null || rc=$?
  if (( rc == 0 )); then
    fzf_groups::_selection "${state}"
  elif (( rc == 130 )); then
    rc="${FZF_GROUP_BACK_RC}"
  else
    log::err "fzf_groups: fzf failed | rc='${rc}' (needs fzf 0.62+ for --no-input)"
    rc=1
  fi
  rm -f "${state}" "${state}.tmp"
  return "${rc}"
}

# The callbacks fzf's bindings run: `zsh fzf_groups.zsh <render|pick|pick-row> <state> …`.
# Sourcing the file (tmux-oneshot, tests) defines the functions only.
if [[ "${ZSH_EVAL_CONTEXT}" == "toplevel" ]]; then
  case "${1:-}" in
    render)   fzf_groups::_render "${2:?state}" ;;
    command)  fzf_groups::_command "${2:?state}" ;;
    pick)     fzf_groups::_pick "${2:?state}" "${3:?key}" ;;
    pick-row) fzf_groups::_pick_row "${2:?state}" "${3?row}" ;;
    *) print -u2 "usage: zsh fzf_groups.zsh render|command|pick|pick-row <state> …"; exit 2 ;;
  esac
fi
