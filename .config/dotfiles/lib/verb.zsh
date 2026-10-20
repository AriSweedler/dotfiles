# dotfiles/lib/verb.zsh — a verb is declared once; its help and its flag parser come from that.
#
#   verb::define VERB "one-line description"     the line `dotfiles --help` lists; -h/--help come free
#   verb::usage  VERB "FORM" ..                   one Usage line each, without the leading `dotfiles`
#   verb::about  VERB <<'EOF' … EOF               the paragraph(s) under Usage, wrapped by hand at 78
#   verb::sub    VERB NAME "description"          a Subcommands row
#   verb::flag   VERB "--name[|-n] [ARG]" "description" [--for "SUB.."]   a Flags row, and what
#                                                 verb::parse accepts; ARG in [brackets] is optional;
#                                                 --for: only after those subcommands
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
typeset -gA VERB_USAGE VERB_SUBS VERB_FLAGS VERB_ENV VERB_SECTIONS VERB_FOR

verb::define() { VERB_DESC[${1}]="${2}"; }
verb::usage() { local v="${1}"; shift; local form; for form in "$@"; do VERB_USAGE[${v}]+="${form}"$'\n'; done; }
verb::about() { local text; IFS= read -rd '' text || true; VERB_ABOUT[${1}]+="${text%$'\n'}"$'\n'; }
verb::sub() { VERB_SUBS[${1}]+="${2}"$'\t'"${3}"$'\n'; }
# verb::flag VERB SPEC DESC [--for "SUB.."]: --for names the subcommands that take the flag; the
# parser refuses it after any other (and before none).
verb::flag() {
  VERB_FLAGS[${1}]+="${2}"$'\t'"${3}"$'\n'
  [[ "${4:-}" != --for ]] || VERB_FOR[${1}:${${2%% *}%%|*}]="${5}"
}
verb::env() { VERB_ENV[${1}]+="${2}"$'\t'"${3}"$'\t'"${4:-}"$'\n'; }
verb::section() { local text; IFS= read -rd '' text || true; VERB_SECTIONS[${1}]+="${2}"$'\t'"${text%$'\n'}"$'\x1f'; }

verb::edit() {
  local v="${1}"
  if [[ "${2}" == --none ]]; then VERB_EDIT_NONE[${v}]="${3}"; return 0; fi
  VERB_EDIT[${v}]="${2}" VERB_EDIT_ARGS[${v}]="${3}" VERB_EDIT_DESC[${v}]="${4}"
  shift 4
  while (( $# )); do
    case "${1}" in
      --form) VERB_EDIT_FORM[${v}]="${2}"; shift 2 ;;
      --flag-only) VERB_EDIT_FLAG_ONLY[${v}]=1; shift ;;
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
  # A flag declared --for some subcommands is refused after any other.
  local key
  (( given )) || sub="${args[1]:-}"
  for key in "${(@k)opts}"; do
    [[ -n "${VERB_FOR[${v}:${key}]:-}" ]] || continue
    (( ${${(z)VERB_FOR[${v}:${key}]}[(Ie)${sub}]} )) && continue
    usage_error "${v}${sub:+ ${sub}}: ${key} goes with ${v} ${VERB_FOR[${v}:${key}]// /|} only"
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
  for form in "${(@f)REPLY}"; do [[ -z "${form}" ]] || print -r -- "  ${DF} ${(e)form}"; done
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
