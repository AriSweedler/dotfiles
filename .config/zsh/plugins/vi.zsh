# vi_ — the family of editors for common files: `vi_cset`, `vi_kh`, `vi_dotfiles`, …
#
# ── The vi_ interface (hand this to whoever adds an editor) ───────────────────────────────
#   1. The editor is a zsh function vi_::<long> in a plugin. It opens ${EDITOR} on one fixed
#      file or dir, positions the cursor if that helps, and needs no arguments.
#   2. It has exactly one alias vi_<short>=vi_::<long>, defined right after the function. The
#      alias is what you type; the function name is what the menus show, minus the vi_:: prefix.
#   3. Names vi_::_<anything> are this file's machinery, never editors.
#   4. `vi_?` lists the family, `vi_` picks one with fzf, `vi_::_verify` enforces 1 and 2. Run
#      it after adding an editor.
#   5. Hyper+O and C-a C-k reach the family through tmux-oneshot: at shell start this file
#      publishes group vi/ (one row per alias, text = long name, opens in a tmux window named
#      vi) into the oneshot generated tier, rewriting it only when the family changed.

(( ${+functions[log::info]} )) || source "${${(%):-%x}:A:h}/log.zsh"

VI_ONESHOT_FILE="${XDG_STATE_HOME:-${HOME}/.local/state}/tmux_oneshot/generated/vi.json"

# Output: "short\tlong" per editor, alias-sorted. Derived from the live aliases, so nothing
# has to be registered twice.
function vi_::_editors() {
  local a
  for a in ${(ko)aliases}; do
    [[ "${a}" == vi_?* && "${aliases[${a}]}" == vi_::* && "${aliases[${a}]}" != vi_::_* ]] || continue
    print -r -- "${a#vi_}	${aliases[${a}]#vi_::}"
  done
}

function vi_::_list() {
  local short long
  while IFS=$'\t' read -r short long; do
    printf '  %-16s %s\n' "vi_${short}" "${long}"
  done < <(vi_::_editors)
}

function vi_::_fzf() { fzf "$@" }

function vi_::_pick() {
  local line
  line="$(vi_::_editors | vi_::_fzf --delimiter $'\t' --with-nth 1,2 --select-1 --exit-0 --query="${1:-}")" || return 1
  [[ -n "${line}" ]] || return 1
  "vi_::${line#*$'\t'}"
}

# Rules 1 and 2: every vi_* alias resolves to an existing vi_::* function, and every non-machinery
# vi_::* function has exactly one alias.
function vi_::_verify() {
  local bad=0 a fn short long
  local -A alias_count
  for a in ${(k)aliases}; do
    [[ "${a}" == vi_?* ]] || continue
    fn="${aliases[${a}]}"
    [[ "${fn}" == vi_::_* ]] && continue
    if [[ "${fn}" != vi_::* ]]; then
      log::err "vi_ alias must point at a vi_:: function | alias='${a}' target='${fn}'"
      bad=1
      continue
    fi
    if (( ! ${+functions[${fn}]} )); then
      log::err "vi_ alias points at a missing function | alias='${a}' target='${fn}'"
      bad=1
    fi
    (( alias_count[${fn}]++ ))
  done
  for fn in ${(k)functions}; do
    [[ "${fn}" == vi_::* && "${fn}" != vi_::_* ]] || continue
    case "${alias_count[${fn}]:-0}" in
      1) ;;
      0) log::err "editor has no vi_ alias | function='${fn}' fix='alias vi_<short>=${fn}'"; bad=1 ;;
      *) log::err "editor has several vi_ aliases | function='${fn}' count='${alias_count[${fn}]}'"; bad=1 ;;
    esac
  done
  (( bad )) || log::info "ok | editors='$(vi_::_editors | wc -l | tr -d ' ')'"
  return ${bad}
}

# Output: the oneshot JSON for the family. `irun` because aliases live in interactive shells.
function vi_::_oneshot_json() {
  vi_::_editors | jq -R -s 'split("\n") | map(select(length > 0) | split("\t")
    | {menu: {name: ("vi/" + .[0]), text: .[1]}, cmd: ("irun vi_" + .[0]), window: "vi"})'
}

function vi_::_publish() {
  local json
  json="$(vi_::_oneshot_json)" || return 1
  if [[ -f "${VI_ONESHOT_FILE}" ]] && [[ "$(< "${VI_ONESHOT_FILE}")" == "${json}" ]]; then
    return 0
  fi
  mkdir -p "${VI_ONESHOT_FILE:h}" || return 1
  print -r -- "${json}" > "${VI_ONESHOT_FILE}"
}

# Runs once, after every plugin (local ones included) has defined its aliases.
function vi_::_publish_once() {
  add-zsh-hook -d precmd vi_::_publish_once
  vi_::_publish
}

alias 'vi_?'=vi_::_list
alias vi_=vi_::_pick

if [[ -o interactive ]]; then
  autoload -Uz add-zsh-hook
  add-zsh-hook precmd vi_::_publish_once
fi
