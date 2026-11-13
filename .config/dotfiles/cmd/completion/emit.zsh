# dotfiles/cmd/completion/emit.zsh — the compiler's back end: completion::emit prints _dotfiles,
# the zsh completion function, from the spec (lib/spec.zsh). The output is two parts: tables,
# one row per node, flag and kind, written here from the declarations; and a fixed engine that
# walks the words typed so far through those tables. Nothing about a particular verb is in the
# engine, so a new verb, flag or kind changes only the tables.

typeset -gi COMPLETION_BRIEF_WIDTH=64   # a description in a completion menu is cut to this

# completion::_brief TEXT: REPLY = TEXT as one menu line: expanded as the help expands it, cut at
# a word to COMPLETION_BRIEF_WIDTH, an ellipsis when cut.
completion::_brief() {
  local text="${(e)1}" word line=""
  for word in ${=text}; do
    if (( ${#line} + 1 + ${#word} > COMPLETION_BRIEF_WIDTH )); then REPLY="${line}…"; return 0; fi
    line+="${line:+ }${word}"
  done
  REPLY="${line}"
}

# completion::_table NAME KEY VALUE..: one associative array literal, a row per pair.
completion::_table() {
  local name="${1}" key value; shift
  print -r -- "typeset -gA ${name}=("
  for key value in "$@"; do print -r -- "  ${(qq)key} ${(qq)value}"; done
  print -r -- ")"
}

# completion::_rows WORD DESC..: REPLY = 'word:brief' lines, the form _describe takes.
completion::_rows() {
  local word desc
  local -a lines=()
  for word desc in "$@"; do
    completion::_brief "${desc}"
    lines+=("${word}:${REPLY}")
  done
  REPLY="${(F)lines}"
}

completion::emit() {
  local node verb key spelling kind child REPLY
  local -a reply pairs rows children_t=() flags_t=() values_t=() args_t=() nodes_t=() delegate_t=()
  local -a source_t=() desc_t=() words_t=()

  # The root: the verbs, and the flags main() takes.
  pairs=()
  for verb in ${(o)NODES:#* *}; do pairs+=("${verb}" "${NODE_DESC[${verb}]}"); done
  completion::_rows "${pairs[@]}"; children_t+=("-" "${REPLY}")
  pairs=()
  for key in "${(@ko)GLOBAL_FLAG_DESC}"; do
    for spelling in "${(@s:|:)key}"; do pairs+=("${spelling}" "${GLOBAL_FLAG_DESC[${key}]}"); done
  done
  pairs+=(--help "this help; after a verb, that verb's")
  completion::_rows "${pairs[@]}"; flags_t+=("-" "${REPLY}")

  # Rows in key order, so the output does not depend on the order the files were sourced in; the
  # words inside a row keep declaration order.
  for node in "${(@o)NODES}"; do
    nodes_t+=("${node}" "${${NODE_FLAG_ONLY[${node}]:+flag}:-word}")
    spec::children "${node}"
    if (( ${#reply} )); then
      pairs=()
      for child in "${reply[@]}"; do pairs+=("${child}" "${NODE_DESC[${node} ${child}]}"); done
      completion::_rows "${pairs[@]}"; children_t+=("${node}" "${REPLY}")
    fi
    spec::args_at "${node}"
    (( ! ${#reply} )) || args_t+=("${node}" "${reply[*]}")
    kind::of_spec "${reply[1]:-}"
    if [[ -n "${reply[1]:-}" && -n "${KIND_DELEGATE[${reply[1]}]:-}" ]]; then delegate_t+=("${node}" "${KIND_DELEGATE[${reply[1]}]}"); fi
    pairs=()
    spec::flags_at "${node}"
    for key in "${reply[@]}"; do
      for spelling in ${=FLAG_SPELLINGS[${key}]}; do pairs+=("${spelling}" "${FLAG_DESC[${key}]}"); done
    done
    # `VERB --edit` is `VERB edit`; a verb that declares its own --edit row keeps that one.
    if [[ "${node}" != *' '* ]] && spec::has_edit "${node}" && (( ! ${pairs[(Ie)--edit]} )); then
      pairs+=(--edit "${NODE_DESC[${node} edit]}")
    fi
    pairs+=(--help "the help of ${node%% *}")
    completion::_rows "${pairs[@]}"; flags_t+=("${node}" "${REPLY}")
  done

  for key in "${(@o)FLAGS}"; do
    (( ${+FLAG_VALUE[${key}]} )) || continue
    for spelling in ${=FLAG_SPELLINGS[${key}]}; do values_t+=("${key%% *} ${spelling}" "${FLAG_VALUE[${key}]}"); done
  done

  for kind in "${KINDS[@]}"; do
    kind::source "${kind}"
    source_t+=("${kind}" "${REPLY}")
    desc_t+=("${kind}" "${KIND_DESC[${kind}]}")
    [[ "${REPLY}" != words ]] || { kind::words "${kind}"; words_t+=("${kind}" "${reply[*]}"); }
  done

  print -r -- "#compdef dotfiles"
  print -r -- "# _dotfiles: tab completion for dotfiles. COMPILED by 'dotfiles completion write' from the verb"
  print -r -- "# declarations (cmd/*.zsh), the kinds (cmd/kinds.zsh) and the flags before the verb"
  print -r -- "# (lib/dispatch.zsh); never edited. Change a declaration, then write it again; the dotfiles_docs"
  print -r -- "# step fails while this file is not what the declarations compile to."
  print -r -- ""
  print -r -- "# --- The tables. A node is one command, the words after dotfiles; '-' is before any verb. ---"
  print -r -- "# node → how its last word is reached: word (typed), flag (an edit only --edit reaches)"
  completion::_table _dotfiles_nodes "${nodes_t[@]}"
  print -r -- "# node → the words that can follow it, each 'word:description'"
  completion::_table _dotfiles_children "${children_t[@]}"
  print -r -- "# node → the flags it takes, each 'flag:description'"
  completion::_table _dotfiles_flags "${flags_t[@]}"
  print -r -- "# 'verb flag' → the spec of the value the flag takes"
  completion::_table _dotfiles_flag_value "${values_t[@]}"
  print -r -- "# node → the specs of its positional values, in order"
  completion::_table _dotfiles_args "${args_t[@]}"
  print -r -- "# node → the command whose own completion takes the rest of the line"
  completion::_table _dotfiles_delegate "${delegate_t[@]}"
  print -r -- "# kind → where its values come from, what one value is, and the fixed set of a words kind"
  completion::_table _dotfiles_kind_source "${source_t[@]}"
  completion::_table _dotfiles_kind_desc "${desc_t[@]}"
  completion::_table _dotfiles_kind_words "${words_t[@]}"
  print -r -- ""
  completion::_engine
}

# completion::_engine: the fixed part, printed as written.
completion::_engine() {
  cat <<'ENGINE'
# --- The engine: the same for every verb ---

# _dotfiles_values SPEC CLI: offer the values of a value spec: KIND, [KIND], KIND.. (repeats),
# KIND,.. (a comma list in one word), A|B (either). A lister kind asks `CLI kinds KIND`.
_dotfiles_values() {
  local spec="${${1#\[}%\]}" cli="${2}" kind alt
  local -a values
  local -i ret=1
  for alt in "${(@s:|:)spec}"; do
    [[ "${alt}" != *,.. ]] || compset -P '*,'
    kind="${${alt%..}%,}"
    case "${_dotfiles_kind_source[${kind}]:-}" in
      words)  values=(${=_dotfiles_kind_words[${kind}]}) ;;
      lister) values=("${(@f)$("${cli}" kinds "${kind}" 2>/dev/null)}") ;;
      files)  _files && ret=0; continue ;;
      *)      _message "${kind}: ${_dotfiles_kind_desc[${kind}]:-}"; continue ;;
    esac
    values=("${(@)values:#}")
    values=("${(@)values//:/\\:}")
    _describe -t "${kind:l}" "${kind}: ${_dotfiles_kind_desc[${kind}]}" values && ret=0
  done
  return ret
}

_dotfiles() {
  local cli="${words[1]/#\~/${HOME}}" node="" verb="" word name key pending="" spec
  local -i i npos=0 verb_at=0 ret=1
  local -a seen flags children specs

  # Walk the words before the cursor: flags (and their values) aside, the first word is the verb,
  # then each word that makes a longer node is a subcommand, and the rest are positionals.
  for (( i = 2; i < CURRENT; i++ )); do
    word="${words[i]}"
    if [[ -n "${pending}" ]]; then pending=""; continue; fi
    if [[ -n "${verb}" && -n "${_dotfiles_delegate[${node}]:-}" && "${word}" != --edit ]]; then break; fi
    if [[ "${word}" == -?* ]]; then
      name="${word%%=*}"; seen+=("${name}")
      if [[ -n "${verb}" && "${name}" == --edit && -n "${_dotfiles_nodes[${verb} edit]:-}" ]]; then node="${verb} edit"; npos=0; continue; fi
      key="${verb:+${verb} }${name}"
      spec="${_dotfiles_flag_value[${key}]:-}"
      [[ -z "${spec}" || "${spec}" == \[* || "${word}" == *=* ]] || pending="${key}"
      continue
    fi
    if [[ -z "${verb}" ]]; then verb="${word:l}"; node="${verb}"; verb_at=i
    elif (( npos == 0 )) && [[ "${_dotfiles_nodes[${node} ${word}]:-}" == word ]]; then node="${node} ${word}"
    else (( npos++ )); fi
  done

  # A flag waiting for its value, or --flag=value.
  if [[ -n "${pending}" ]]; then _dotfiles_values "${_dotfiles_flag_value[${pending}]}" "${cli}"; return; fi
  if [[ "${PREFIX}" == --*=* ]]; then
    spec="${_dotfiles_flag_value[${verb:+${verb} }${PREFIX%%=*}]:-}"
    [[ -n "${spec}" ]] || return 1
    compset -P '*='
    _dotfiles_values "${spec}" "${cli}"; return
  fi

  flags=("${(@f)_dotfiles_flags[${node:--}]:-}")
  for name in "${seen[@]}"; do flags=("${(@)flags:#${name}:*}"); done
  children=("${(@f)_dotfiles_children[${node:--}]:-}")
  flags=("${(@)flags:#}"); children=("${(@)children:#}")

  # A node that hands its line on: that command's completion, from its own first word.
  if [[ -n "${verb}" && -n "${_dotfiles_delegate[${node}]:-}" ]]; then
    if (( CURRENT == verb_at + 1 )) && [[ "${PREFIX}" == -* ]]; then _describe -t flags 'dotfiles flag' flags && ret=0; fi
    words=("${_dotfiles_delegate[${node}]}" "${(@)words[verb_at+1,-1]}")
    (( CURRENT -= verb_at - 1 ))
    _normal && ret=0
    return ret
  fi

  if [[ "${PREFIX}" == -* ]]; then _describe -t flags flag flags; return; fi
  if (( npos == 0 && ${#children} )); then
    if [[ -z "${verb}" ]]; then _describe -t verbs verb children && ret=0
    else _describe -t subcommands subcommand children && ret=0; fi
  fi
  specs=(${=_dotfiles_args[${node}]:-})
  spec="${specs[npos+1]:-}"
  if [[ -z "${spec}" && "${specs[-1]:-}" == *..* ]]; then spec="${specs[-1]}"; fi
  if [[ -n "${spec}" ]]; then _dotfiles_values "${spec}" "${cli}" && ret=0; fi
  # Nothing else to say: the flags.
  if (( ret )) && [[ -z "${spec}" ]] && (( ! ${#children} || npos )); then _describe -t flags flag flags && ret=0; fi
  return ret
}

_dotfiles "$@"
ENGINE
}
