# dotfiles/lib/spec.zsh — the command line as data, and its linter. The declarations (lib/verb.zsh,
# lib/kind.zsh, GLOBAL_FLAG_DESC in lib/dispatch.zsh) fill the tables; this module answers
# questions about them and checks that they say everything a reader needs. The completion
# (cmd/completion/emit.zsh) is compiled from the same answers and is refused while the linter
# has a finding, so the linter is the compiler's front end.
#
# A node is one command, the words after `dotfiles`: "jobs", "jobs run". Questions:
#   spec::verb_of NODE       REPLY = its verb
#   spec::children NODE      reply = the next words that make a longer node (the root '': the verbs)
#   spec::flags_at NODE      reply = the flag keys ("VERB --name") the node takes
#   spec::args_at NODE       reply = its positional value specs, in order
#   spec::completion_file    REPLY = where the compiled completion is kept
#   spec::lint               reply = the findings, each '<where>: <what is wrong>'; empty = clean
# Each rule is a spec::rule::<name> function appending to the caller's `findings`, run in
# SPEC_RULES order.

typeset -ga SPEC_RULES=(kinds nodes flags args usage globals)

# spec::completion_file: REPLY = where the compiled _dotfiles is kept, in the editable checkout.
spec::completion_file() { REPLY="${ARI_DOTFILES_SRC_CONFIG}/zsh/completions/_dotfiles"; }

spec::verb_of() { REPLY="${1%% *}"; }

spec::children() {
  local parent="${1}" node rest
  reply=()
  for node in "${NODES[@]}"; do
    if [[ -z "${parent}" ]]; then rest="${node}"
    elif [[ "${node}" == "${parent} "* ]]; then rest="${node#${parent} }"
    else continue; fi
    [[ "${rest}" != *' '* && -z "${NODE_FLAG_ONLY[${node}]:-}" ]] || continue
    reply+=("${rest}")
  done
}

spec::flags_at() {
  local node="${1}" key
  local -a nodes
  reply=()
  for key in "${FLAGS[@]}"; do
    [[ "${key%% *}" == "${node%% *}" ]] || continue
    if (( ${+FLAG_NODES[${key}]} )); then
      nodes=("${(@f)FLAG_NODES[${key}]}")
      (( ${nodes[(Ie)${node}]} )) || continue
    fi
    reply+=("${key}")
  done
}

spec::args_at() { reply=(${=NODE_ARGS[${1}]:-}); }

# spec::has_edit VERB: 0 when `VERB edit` is a node (verb::edit with a handler).
spec::has_edit() { (( ${+NODE_DESC[${1} edit]} )); }

# spec::kinds_of_verb VERB: reply = every kind VERB's flags and positionals name.
spec::kinds_of_verb() {
  local verb="${1}" key node spec
  local -a kinds=()
  for key in "${FLAGS[@]}"; do
    [[ "${key%% *}" == "${verb}" && -n "${FLAG_VALUE[${key}]:-}" ]] || continue
    kind::of_spec "${FLAG_VALUE[${key}]}"; kinds+=("${reply[@]}")
  done
  for node in "${(@k)NODE_ARGS}"; do
    [[ "${node%% *}" == "${verb}" ]] || continue
    for spec in ${=NODE_ARGS[${node}]}; do kind::of_spec "${spec}"; kinds+=("${reply[@]}"); done
  done
  reply=(${(u)kinds})
}

spec::lint() {
  local rule
  local -a findings=()
  for rule in "${SPEC_RULES[@]}"; do "spec::rule::${rule}"; done
  reply=("${findings[@]}")
}

# --- The rules ---

# Every kind says what it is, has values to give, and is named by some declaration.
spec::rule::kinds() {
  local kind node key spec REPLY
  local -a reply used=()
  for key in "${(@k)FLAG_VALUE}"; do kind::of_spec "${FLAG_VALUE[${key}]}"; used+=("${reply[@]}"); done
  for node in "${(@k)NODE_ARGS}"; do
    for spec in ${=NODE_ARGS[${node}]}; do kind::of_spec "${spec}"; used+=("${reply[@]}"); done
  done
  for kind in "${KINDS[@]}"; do
    [[ -n "${KIND_DESC[${kind}]}" ]] || findings+=("kind ${kind}: no description")
    (( ${used[(Ie)${kind}]} )) || findings+=("kind ${kind}: no flag or position names it (drop it from cmd/kinds.zsh, or name it where its value goes)")
    kind::source "${kind}"
    case "${REPLY}" in
      words)  kind::words "${kind}"; (( ${#reply} )) || findings+=("kind ${kind}: --words is empty") ;;
      lister) (( ${+functions[${KIND_LISTER[${kind}]}]} )) || findings+=("kind ${kind}: its lister is not a function | lister='${KIND_LISTER[${kind}]}'") ;;
    esac
  done
}

# Every node says what it is, and hangs off a declared node.
spec::rule::nodes() {
  local node
  for node in "${NODES[@]}"; do
    [[ -n "${NODE_DESC[${node}]}" ]] || findings+=("${node}: no description")
    [[ "${node}" != *' '* ]] || (( ${+NODE_DESC[${node% *}]} )) \
      || findings+=("${node}: '${node% *}' is not declared (verb::sub ${node%% *} '${${node% *}#* }' '…')")
    [[ "${node}" != *[^a-z0-9\ _-]* ]] || findings+=("${node}: a subcommand is words only; a value goes in verb::arg")
  done
}

# Every flag's value names kinds that exist; in a verb with more than one node, every flag says
# which nodes take it, and each of those is declared.
spec::rule::flags() {
  local key verb node kind REPLY
  local -a reply
  local -A node_count=()
  for node in "${NODES[@]}"; do verb="${node%% *}"; node_count[${verb}]=$(( ${node_count[${verb}]:-0} + 1 )); done
  for key in "${FLAGS[@]}"; do
    verb="${key%% *}"
    if (( ${+FLAG_VALUE[${key}]} )); then
      kind::of_spec "${FLAG_VALUE[${key}]}"
      for kind in "${reply[@]}"; do
        kind::is_known "${kind}" || findings+=("${key}: its value '${FLAG_VALUE[${key}]}' names no kind | unknown='${kind}' fix='name a kind of cmd/kinds.zsh, or add one'")
      done
    fi
    if (( ! ${+FLAG_NODES[${key}]} )); then
      (( ${node_count[${verb}]:-0} <= 1 )) || findings+=("${key}: no --for; ${verb} has subcommands, so the flag says which take it (${verb} itself: the verb without one)")
      continue
    fi
    [[ -n "${FLAG_NODES[${key}]}" ]] || findings+=("${key}: --for names nothing")
    for node in "${(@f)FLAG_NODES[${key}]}"; do
      (( ${+NODE_DESC[${node}]} )) || findings+=("${key}: --for names '${node}', which is not declared")
    done
  done
}

# Every positional sits on a declared node and names kinds that exist; only the last may repeat;
# a delegate kind stands alone.
spec::rule::args() {
  local node spec kind REPLY
  local -a reply specs
  local -i i
  for node in "${(@ko)NODE_ARGS}"; do
    (( ${+NODE_DESC[${node}]} )) || findings+=("${node}: verb::arg on a node that is not declared")
    specs=(${=NODE_ARGS[${node}]})
    for (( i = 1; i <= ${#specs}; i++ )); do
      spec="${specs[i]}"
      [[ "${spec}" != *..* || i -eq ${#specs} ]] || findings+=("${node}: '${spec}' repeats but is not the last positional")
      [[ "${spec}" != *,* ]] || findings+=("${node}: '${spec}': a comma list is a flag's value; a positional repeats with ..")
      kind::of_spec "${spec}"
      for kind in "${reply[@]}"; do
        if ! kind::is_known "${kind}"; then
          findings+=("${node}: its positional '${spec}' names no kind | unknown='${kind}' fix='name a kind of cmd/kinds.zsh, or add one'")
        elif (( ${+KIND_DELEGATE[${kind}]} )) && [[ ${#specs} -ne 1 || ${#reply} -ne 1 ]]; then
          findings+=("${node}: ${kind} hands the line to ${KIND_DELEGATE[${kind}]}; it is the node's only positional")
        fi
      done
    done
  done
}

# The Usage forms speak the declared language: every --flag in one is a flag of the verb (or one
# main() takes), and every upper-case word is a kind the verb's flags or positionals name.
spec::rule::usage() {
  setopt localoptions extendedglob
  local verb form word key REPLY
  local -a reply forms kinds spellings
  for verb in "${(@ko)VERB_DESC}"; do
    forms=("${(@f)VERB_USAGE[${verb}]:-}")
    if [[ -n "${VERB_EDIT[${verb}]:-}" ]]; then forms+=("${VERB_EDIT_FORM[${verb}]:-${verb} edit ${VERB_EDIT_ARGS[${verb}]}}"); fi
    spec::kinds_of_verb "${verb}"; kinds=("${reply[@]}")
    spellings=(--edit --help -h)
    for key in "${FLAGS[@]}"; do [[ "${key%% *}" != "${verb}" ]] || spellings+=(${=FLAG_SPELLINGS[${key}]}); done
    for key in "${(@k)GLOBAL_FLAG_DESC}"; do spellings+=(${(s:|:)key}); done
    for form in "${forms[@]}"; do
      for word in ${=form//[^A-Za-z0-9_-]/ }; do
        if [[ "${word}" == --[a-z0-9]* ]]; then
          (( ${spellings[(Ie)${word}]} )) || findings+=("${verb}: Usage '${form}' has ${word}, which is not a declared flag")
        elif [[ "${word}" == [A-Z][A-Z_]# ]]; then
          (( ${kinds[(Ie)${word}]} )) || findings+=("${verb}: Usage '${form}' has ${word}, which is no kind a flag or positional of ${verb} names (verb::flag, verb::arg)")
        fi
      done
    done
  done
}

# The flags declared for before the verb are the ones main() parses.
spec::rule::globals() {
  local key word
  local -a reply declared=() parsed
  for key in "${(@k)GLOBAL_FLAG_DESC}"; do
    declared+=(${(s:|:)key})
    [[ -n "${GLOBAL_FLAG_DESC[${key}]}" ]] || findings+=("${key}: no description (GLOBAL_FLAG_DESC, lib/dispatch.zsh)")
  done
  (( ${+functions[help::parser_flags]} )) || need_lib "${ARI_DOTFILES_CMD}/help.zsh" || return 0
  help::parser_flags "${ARI_DOTFILES_LIB}/dispatch.zsh"; parsed=("${reply[@]}")
  for word in "${parsed[@]}"; do
    (( ${declared[(Ie)${word}]} )) || findings+=("${word}: main() parses it and GLOBAL_FLAG_DESC (lib/dispatch.zsh) does not declare it")
  done
  for word in "${declared[@]}"; do
    (( ${parsed[(Ie)${word}]} )) || findings+=("${word}: GLOBAL_FLAG_DESC declares it and main() (lib/dispatch.zsh) does not parse it")
  done
}
