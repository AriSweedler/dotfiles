# dotfiles/lib/verb.zsh — a verb is declared once; its help and its flag parser come from that.
#
#   verb::define VERB "one-line description"     the line `dotfiles --help` lists; -h/--help come free
#   verb::usage  VERB "FORM" ..                   one Usage line each, without the leading `dotfiles`
#   verb::about  VERB <<'EOF' … EOF               the paragraph(s) under Usage, wrapped by hand at 78
#   verb::sub    VERB NAME "description"          a Subcommands row
#   verb::flag   VERB "--name[|-n] [ARG]" "description" [--for "SUB, .."]   a Flags row, and what
#                                                 verb::parse accepts; ARG is a value spec naming
#                                                 the value's kind (lib/kind.zsh: STEP, STEP,.. for
#                                                 a comma list), in [brackets] when optional;
#                                                 --for: only with those subcommands, the verb's
#                                                 own name standing for the verb without one. A
#                                                 verb with a subcommand or an edit scopes every flag
#   verb::arg    VERB [--for "SUB, .."] SPEC..    the positional values, in order, of the verb (or
#                                                 of those subcommands): KIND, [KIND], KIND.. (one
#                                                 or more words), A|B (either kind)
#   verb::env    VERB VAR "description" ["default"]   an Env row
#   verb::edit   VERB HANDLER "ARGS" "description" [--form "USAGE"] [--flag-only]
#                                                 `dotfiles VERB edit ARGS` and `--edit ARGS` route
#                                                 to HANDLER; adds the Usage line (--form: written
#                                                 out instead), the edit Subcommands row and the
#                                                 --edit flag. --flag-only: only `--edit` routes (a
#                                                 verb that hands its words to another tool)
#   verb::edit   VERB --none "why it has nothing to edit"
#   verb::section VERB TITLE <<'EOF' … EOF        a free section after Env (exit codes, tiers)
#
# Texts are stored as written and expanded when help prints (${(e)…}): `$(help::tilde "${X}")`
# and `${VAR}` work and cost nothing at startup. Write the texts in single quotes, and \$ for a
# literal dollar sign (in double quotes the shell has already expanded them once, so there it is
# \\\$; a text with an apostrophe is easiest in double quotes with that). Rows are
# wrapped to 80 columns with a hanging indent, so a description is written as one line.
#
#   verb::parse VERB [--sub SUB] "$@"   the only flag parser (--sub: a subcommand's handler, its
#                           word already consumed, says which it is for the --for check): fills the caller's `opts` (opts[--name]=value, or
#                           1 for a flag without one; an alias lands under the first spelling) and `args` (the rest, in order). A word starting
#                           with '-' that VERB does not declare is a usage error; `--` ends flags.
#   verb::help VERB         the help, in the one shape every verb has.

typeset -gA VERB_DESC VERB_EDIT VERB_EDIT_ARGS VERB_EDIT_DESC VERB_EDIT_NONE VERB_ABOUT VERB_EDIT_FORM VERB_EDIT_FLAG_ONLY
typeset -gA VERB_USAGE VERB_SUBS VERB_FLAGS VERB_ENV VERB_SECTIONS
# What the linter and the completion read (lib/spec.zsh), one table per fact. A node is one
# command, the words after `dotfiles`: "jobs", "jobs run", "raycast link list". A flag's key is
# "VERB --name", its first spelling.
typeset -ga NODES=() FLAGS=()                   # every node, every flag key, in declaration order
typeset -gA NODE_DESC=()                        # node → its description
typeset -gA NODE_ARGS=()                        # node → its positional value specs, space separated
typeset -gA NODE_FLAG_ONLY=()                   # an edit node only `--edit` reaches
typeset -gA FLAG_DESC=() FLAG_SPELLINGS=()      # flag → description, every spelling (space separated)
typeset -gA FLAG_VALUE=()                       # flag → the spec of the value it takes; absent = none
typeset -gA FLAG_NODES=()                       # flag → the nodes it goes with, one per line; absent = unscoped
typeset -gA VERB_SUB_SEEN=()                    # verb → the subcommand this run is for, once known

# verb::_node NODE DESC: record a node once (a file sourced twice declares twice).
verb::_node() {
  (( ${NODES[(Ie)${1}]} )) || NODES+=("${1}")
  NODE_DESC[${1}]="${2}"
}
# verb::_nodes_for VERB "SUB, ..": reply = the nodes a --for list names; VERB itself is the verb
# without a subcommand.
verb::_nodes_for() {
  local v="${1}" item
  reply=()
  for item in "${(@s:,:)2}"; do
    item="${${item##[[:space:]]#}%%[[:space:]]#}"
    [[ -n "${item}" ]] || continue
    if [[ "${item}" == "${v}" ]]; then reply+=("${v}"); else reply+=("${v} ${item}"); fi
  done
}

verb::define() { VERB_DESC[${1}]="${2}"; verb::_node "${1}" "${2}"; }
verb::usage() { local v="${1}"; shift; local form; for form in "$@"; do VERB_USAGE[${v}]+="${form}"$'\n'; done; }
verb::about() { local text; IFS= read -rd '' text || true; VERB_ABOUT[${1}]+="${text%$'\n'}"$'\n'; }
verb::sub() { VERB_SUBS[${1}]+="${2}"$'\t'"${3}"$'\n'; verb::_node "${1} ${2}" "${3}"; }
# verb::flag VERB SPEC DESC [--for "SUB, .."]: --for names the subcommands that take the flag (VERB
# itself: the verb without one); the parser refuses it with any other.
verb::flag() {
  setopt localoptions extendedglob
  local v="${1}" spec="${2}" names="${${2%% *}}"
  local key="${v} ${names%%|*}"
  local -a reply
  VERB_FLAGS[${v}]+="${spec}"$'\t'"${3}"$'\n'
  (( ${FLAGS[(Ie)${key}]} )) || FLAGS+=("${key}")
  FLAG_DESC[${key}]="${3}"
  FLAG_SPELLINGS[${key}]="${names//|/ }"
  [[ "${spec}" != *' '* ]] || FLAG_VALUE[${key}]="${spec#* }"
  [[ "${4:-}" == --for ]] || return 0
  verb::_nodes_for "${v}" "${5}"
  FLAG_NODES[${key}]="${(F)reply}"
}
# verb::arg VERB [--for "SUB, .."] SPEC..: the positional values of VERB, or of those subcommands.
verb::arg() {
  setopt localoptions extendedglob
  local v="${1}" node; shift
  local -a reply=("${v}")
  if [[ "${1:-}" == --for ]]; then verb::_nodes_for "${v}" "${2}"; shift 2; fi
  for node in "${reply[@]}"; do NODE_ARGS[${node}]="$*"; done
}
verb::env() { VERB_ENV[${1}]+="${2}"$'\t'"${3}"$'\t'"${4:-}"$'\n'; }
verb::section() { local text; IFS= read -rd '' text || true; VERB_SECTIONS[${1}]+="${2}"$'\t'"${text%$'\n'}"$'\x1f'; }

verb::edit() {
  local v="${1}"
  if [[ "${2}" == --none ]]; then VERB_EDIT_NONE[${v}]="${3}"; return 0; fi
  VERB_EDIT[${v}]="${2}" VERB_EDIT_ARGS[${v}]="${3}" VERB_EDIT_DESC[${v}]="${4}"
  local edit_node="${v} edit"
  verb::_node "${edit_node}" "${4}"
  shift 4
  while (( $# )); do
    case "${1}" in
      --form) VERB_EDIT_FORM[${v}]="${2}"; shift 2 ;;
      --flag-only) VERB_EDIT_FLAG_ONLY[${v}]=1; NODE_FLAG_ONLY[${edit_node}]=1; shift ;;
      *) print -u2 -r -- "verb::edit: bad argument '${1}'"; return 64 ;;
    esac
  done
}

# verb::_rows_of VERB usage|subs|flags: REPLY is that table of VERB as declared, then the edit's own
# row last (wherever verb::edit was declared), so every verb's edit reads the same.
verb::_rows_of() {
  local v="${1}"
  case "${2}" in
    usage) REPLY="${VERB_USAGE[${v}]:-}" ;;
    subs) REPLY="${VERB_SUBS[${v}]:-}" ;;
    flags) REPLY="${VERB_FLAGS[${v}]:-}" ;;
  esac
  [[ -n "${VERB_EDIT[${v}]:-}" ]] || return 0
  # A verb that declares its own --edit row (a subcommand's --edit FILE) keeps that one.
  [[ "${2}" != flags || "${REPLY}" != (|*$'\n')--edit[[:space:]$'\t']* ]] || return 0
  case "${2}" in
    usage) REPLY+="${VERB_EDIT_FORM[${v}]:-${v} edit${VERB_EDIT_ARGS[${v}]:+ ${VERB_EDIT_ARGS[${v}]}}}"$'\n' ;;
    subs) REPLY+="edit"$'\t'"${VERB_EDIT_DESC[${v}]} (also: ${v} --edit)"$'\n' ;;
    flags) REPLY+="--edit"$'\t'"edit: the same as the edit subcommand"$'\n' ;;
  esac
}

# verb::_flag_names VERB: `reply` is every spelling VERB accepts, `--edit` and -h/--help included;
# VERB_ARG (name → required|optional|"") says which take a value.
verb::_flag_names() {
  local row spec name arg
  typeset -gA VERB_ARG=() VERB_CANON=()
  reply=(-h --help)
  local REPLY
  verb::_rows_of "${1}" flags
  for row in "${(@f)REPLY}"; do
    [[ -n "${row}" ]] || continue
    spec="${row%%$'\t'*}"
    arg=""; [[ "${spec}" == *' '* ]] && arg="${spec#* }"
    for name in "${(@s:|:)spec%% *}"; do
      reply+=("${name}")
      VERB_CANON[${name}]="${${spec%% *}%%|*}"
      if [[ -z "${arg}" ]]; then VERB_ARG[${name}]=""
      elif [[ "${arg}" == '['*']' ]]; then VERB_ARG[${name}]=optional
      else VERB_ARG[${name}]=required; fi
    done
  done
}

verb::parse() {
  local v="${1}" word name value sub=""; shift
  local -i given=0
  # --sub SUB: a handler parsing a subcommand's words (the subcommand word already consumed).
  if [[ "${1:-}" == --sub ]]; then sub="${2}" given=1; shift 2; fi
  local -a reply
  verb::_flag_names "${v}"
  local -a known=("${reply[@]}")
  opts=() args=()
  while (( $# )); do
    word="${1}"; shift
    if [[ "${word}" == -- ]]; then args+=("$@"); break; fi
    if [[ "${word}" != -?* ]]; then args+=("${word}"); continue; fi
    name="${word%%=*}" value=""
    (( ${known[(Ie)${name}]} )) || usage_error "${v}: unknown flag | flag='${word}' known='${(j: :)known}'"
    case "${VERB_ARG[${name}]:-}" in
      required)
        if [[ "${word}" == *=* ]]; then value="${word#*=}"
        elif (( $# )); then value="${1}"; shift
        else usage_error "${v}: ${name} needs a value"; fi ;;
      optional)
        if [[ "${word}" == *=* ]]; then value="${word#*=}"
        elif (( $# )) && [[ "${1}" != -* ]]; then value="${1}"; shift
        else value=1; fi ;;
      *) [[ "${word}" != *=* ]] || usage_error "${v}: ${name} takes no value | flag='${word}'"; value=1 ;;
    esac
    opts[${VERB_CANON[${name}]:-${name}}]="${value}"
  done
  # Which subcommand this line is for: --sub, else what an earlier parse of this run found, else
  # --edit, else the longest declared subcommand the positional words start with, else none.
  if (( ! given )); then
    sub="${VERB_SUB_SEEN[${v}]:-}"
    if [[ -z "${sub}" ]] && (( ${+opts[--edit]} )); then sub=edit; fi
    if [[ -z "${sub}" ]]; then
      local -i n
      for (( n = ${#args}; n >= 1; n-- )); do
        (( ${+NODE_DESC[${v} ${(j: :)args[1,n]}]} )) || continue
        sub="${(j: :)args[1,n]}"; break
      done
    fi
  fi
  [[ -z "${sub}" ]] || VERB_SUB_SEEN[${v}]="${sub}"
  # A flag declared --for some subcommands is refused with any other.
  local key node="${v}${sub:+ ${sub}}"
  local -a nodes
  for key in "${(@k)opts}"; do
    [[ -n "${FLAG_NODES[${v} ${key}]:-}" ]] || continue
    nodes=("${(@f)FLAG_NODES[${v} ${key}]}")
    (( ${nodes[(Ie)${node}]} )) && continue
    usage_error "${node}: ${key} goes with ${(j:, :)nodes} only"
  done
}

# verb::_rows WIDTH: TSV rows (name\tdesc) on stdin as two columns, the name grey, each description
# wrapped to 80 with a hanging indent; a name wider than WIDTH puts its description on the next line.
verb::_rows() {
  local -i width="${1}" indent
  local name desc
  indent=$(( width + 4 ))
  while IFS=$'\t' read -r name desc; do
    [[ -n "${name}" ]] || continue
    desc="${(e)desc}"
    if (( ${#name} > width )); then
      print -r -- "  ${c_grey}${name}${c_rst}"
      verb::_wrap "${desc}" "${indent}"
    else
      verb::_wrap "${desc}" "${indent}" "  ${c_grey}${(r:width:)name}${c_rst}  "
    fi
  done
}

# verb::_wrap TEXT INDENT [PREFIX]: TEXT word-wrapped to 80 columns, every line but the first
# indented INDENT spaces; the first starts with PREFIX, which must print INDENT columns wide
# (default: the spaces).
verb::_wrap() {
  local text="${1}" prefix="${3:-}" word line
  local -i indent="${2}" col empty=1
  local pad; printf -v pad "%*s" "${indent}" ""
  line="${prefix:-${pad}}" col=${indent}
  for word in ${=text}; do
    if (( ! empty && col + 1 + ${#word} > 80 )); then
      print -r -- "${line}"; line="${pad}${word}"; col=$(( indent + ${#word} ))
    elif (( empty )); then
      line+="${word}"; col+=${#word}; empty=0
    else
      line+=" ${word}"; col+=$(( 1 + ${#word} ))
    fi
  done
  print -r -- "${line}"
}

verb::help() {
  local v="${1}" form row title text
  local -i w
  print -r -- "${(e)VERB_DESC[${v}]}"
  print -r -- ""
  print -r -- "${c_bold}Usage${c_rst}"
  local REPLY
  verb::_rows_of "${v}" usage
  # A form wider than 80 wraps, its continuation under the words after `dotfiles VERB`.
  local head rest
  for form in "${(@f)REPLY}"; do
    [[ -n "${form}" ]] || continue
    form="${(e)form}"
    if (( 11 + ${#form} <= 80 )) || [[ "${form}" != *' '* ]]; then print -r -- "  ${DF} ${form}"; continue; fi
    head="${form%% *}" rest="${form#* }"
    verb::_wrap "${rest}" $(( 12 + ${#head} )) "  ${DF} ${head} "
  done
  if [[ -n "${VERB_ABOUT[${v}]:-}" ]]; then
    print -r -- ""
    for text in "${(@f)${(e)${VERB_ABOUT[${v}]:-}%$'\n'}}"; do print -r -- "${text:+  ${text}}"; done
  fi
  local -a sections=(Subcommands subs 10 Flags flags 14)
  local i
  for (( i = 1; i <= ${#sections}; i += 3 )); do
    verb::_rows_of "${v}" "${sections[i+1]}"
    text="${REPLY}"
    [[ -n "${text}" ]] || continue
    print -r -- ""
    print -r -- "${c_bold}${sections[i]}${c_rst}"
    w=0
    for row in "${(@f)text}"; do (( ${#row%%$'\t'*} > w && ${#row%%$'\t'*} <= sections[i+2] )) && w=${#row%%$'\t'*}; done
    print -r -- "${text}" | verb::_rows "${w}"
  done
  if [[ -n "${VERB_ENV[${v}]:-}" ]]; then
    print -r -- ""
    print -r -- "${c_bold}Env${c_rst}"
    local var desc def
    while IFS=$'\t' read -r var desc def; do
      [[ -n "${var}" ]] || continue
      print -r -- "  ${c_grey}${var}${c_rst}"
      verb::_wrap "${(e)desc}${def:+ (default ${(e)def})}" 6
    done <<< "${VERB_ENV[${v}]:-}"
  fi
  for row in "${(@ps:\x1f:)VERB_SECTIONS[${v}]:-}"; do
    [[ -n "${row}" ]] || continue
    print -r -- ""
    print -r -- "${c_bold}${row%%$'\t'*}${c_rst}"
    for text in "${(@f)${(e)row#*$'\t'}}"; do print -r -- "  ${text}"; done
  done
}
