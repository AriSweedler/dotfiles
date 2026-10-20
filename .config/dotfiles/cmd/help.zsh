# dotfiles/cmd/help.zsh — `dotfiles help [VERB]`: the top-level help, or one verb's; `help --edit`
# opens one in $EDITOR. Also the help documentation rule (help::doc_gap), which the dotfiles_docs
# step runs over every verb and `help --edit` runs over its draft.

help_help() {
  cat <<EOF
the verbs, or one verb's help

${c_bold}Usage${c_rst}
  ${DF} help
  ${DF} help VERB
  ${DF} help --edit [VERB] [--no-commit]

  Without VERB, the same as 'dotfiles --help' (and a bare 'dotfiles'): every
  verb with its one-line description. With VERB, the same as
  'dotfiles VERB --help'. Any sub-verb answers --help with its verb's help,
  e.g. 'dotfiles jobs list --help'.

  A verb's help is help_VERB() in cmd/VERB.zsh, one heredoc: line 1 its
  one-line synopsis, then a Usage section, and every flag the verb's parsers
  accept (cmd/VERB.zsh and cmd/VERB/*.zsh: zparseopts specs and case arms,
  -h/--help aside) named somewhere in it. The top-level help is help() in
  lib/dispatch.zsh, held to the same rule for the flags main() takes. A help
  that breaks the rule fails the dotfiles_docs step.

  --edit opens that file in \$EDITOR (vi when unset) at the help function, as
  a draft (a verb without one gets a stub). On save the draft must pass
  zsh -n, the rule above, and render under 'set -euo pipefail' in a fresh
  zsh -f with the draft in place; then it replaces the file and is committed
  in the shared tier. A draft that does not pass is kept: offered for another
  edit on a terminal, else exit 1; the same command resumes it.

${c_bold}Flags${c_rst}
  --edit        edit VERB's help (no VERB: the top-level help)
  --no-commit   edit: put the file in place, leave it uncommitted
EOF
}

cmd_help() {
  local edit=0 commit=1
  local -a args=()
  while (( $# )); do
    case "${1}" in
      --edit) edit=1 ;;
      --no-commit) commit=0 ;;
      -*) usage_error "help: unknown flag | flag='${1}'" ;;
      *) args+=("${1}") ;;
    esac
    shift
  done
  (( ${#args} <= 1 )) || usage_error "help takes at most one verb | args='${args[*]}'"
  (( edit || commit )) || usage_error "help: --no-commit goes with --edit"
  local verb="${args[1]:-}"
  verb="${verb:l}"
  if [[ -n "${verb}" ]] && (( ! ${+functions[cmd_${verb}]} )); then
    usage_error "Unknown verb | verb='${verb}' valid='${(j:, :)${(f)$(verbs)}}'"
  fi
  if (( edit )); then
    need_lib "${ARI_DOTFILES_CMD}/help/edit.zsh" || return 3
    help_edit "${verb}" "${commit}"
    return
  fi
  if [[ -z "${verb}" ]]; then help; return 0; fi
  help_verb "${verb}"
}

# --- The help documentation rule ---

# help::parser_flags <file>..: reply = every flag the files' parsers accept, unique, in order of
# appearance. A zparseopts spec '-name' is --name ('v' is -v); a case arm's alternatives
# ('--x)', '--x|--y)', 'edit|--edit)') give their long flags, and a short one only beside a long
# one ('--verbose|-v)'; a lone '-k)' is a function's own argument). Heredoc bodies are help
# text, not parsers, and are skipped; -h and --help are exempt. Pure zsh: no fork per file.
help::parser_flags() {
  setopt localoptions extendedglob
  zmodload zsh/mapfile
  local f line term="" dash=0 rest w alt
  local -a words alts long short
  reply=()
  for f in "$@"; do
    [[ -r "${f}" ]] || continue
    term=""
    for line in "${(@f)mapfile[${f}]}"; do
      if [[ -n "${term}" ]]; then
        if (( dash )); then [[ "${line##$'\t'#}" == "${term}" ]] && term=""
        else [[ "${line}" == "${term}" ]] && term=""
        fi
        continue
      fi
      if [[ "${line}" != *'<<<'* && "${line}" == (#b)*'<<'(-|)[\'\"]#([A-Za-z_][A-Za-z0-9_]#)[\'\"]#* ]]; then
        term="${match[2]}"; dash=0; [[ "${match[1]}" == - ]] && dash=1
      fi
      if [[ "${line}" == [[:space:]]#zparseopts' '*' -- '* ]]; then
        rest="${line#*zparseopts* -- }"
        words=(${(z)rest})
        for w in "${words[@]}"; do
          [[ "${w}" == ('||'|'&&'|';'|'|'|')') ]] && break
          w="${w%%[:+=]*}"
          [[ -z "${w}" ]] || reply+=("-${w}")
        done
        continue
      fi
      [[ "${line}" == (#b)[[:space:]]#(\(|)([^[:space:]\(\)]##)\)* ]] || continue
      alts=(${(s:|:)match[2]})
      long=(${(M)alts:#--[a-z0-9][a-z0-9-]#})
      (( ${#long} )) || continue
      short=(${(M)alts:#-[a-zA-Z0-9]})
      reply+=("${long[@]}" "${short[@]}")
    done
  done
  reply=(${(u)reply})
  reply=(${reply:#(-h|--help)})
}

# help::doc_gap <file> <fn> <parser file>..: REPLY = what <fn>() in <file> lacks as a help, ''
# when it has it all: the function; line 1 of its heredoc a one-line synopsis (text, then a blank
# line); a '${c_bold}Usage${c_rst}' heading; every flag of the parser files named in it.
help::doc_gap() {
  setopt localoptions extendedglob
  zmodload zsh/mapfile
  local file="${1}" fn="${2}" line text flag usage='${c_bold}Usage${c_rst}'
  shift 2
  local -a block=() lacks=() missing=()
  local -i inside=0 i
  REPLY=""
  for line in "${(@f)mapfile[${file}]-}"; do
    if (( inside )); then
      block+=("${line}")
      [[ "${line}" == "}" ]] && break
    elif [[ "${line}" == "${fn}() {"* ]]; then
      inside=1
    fi
  done
  if (( ! inside )); then REPLY="no ${fn}()"; return 0; fi
  i=${block[(i)*<<*]}
  if (( i > ${#block} )); then
    lacks+=("${fn}() is not one heredoc")
  elif [[ -z "${block[i+1]// }" || "${block[i+1]}" == [[:space:]]* || "${block[i+1]}" == *'${c_bold}'* \
          || "${block[i+1]}" == EOF || -n "${block[i+2]:-}" ]]; then
    lacks+=("line 1 is not a one-line synopsis")
  fi
  (( ${block[(Ie)${usage}]} )) || lacks+=("no Usage section")
  text="${(F)block}"
  help::parser_flags "$@"
  for flag in "${reply[@]}"; do
    [[ "${text}" == (|*[^A-Za-z0-9-])"${flag}"(|[^A-Za-z0-9-]*) ]] || missing+=("${flag}")
  done
  (( ${#missing} )) && lacks+=("flags not in it: ${missing[*]}")
  REPLY="${(j:, :)lacks}"
}

# The parser files of a verb: its file and cmd/VERB/*.zsh. raycast hands its line to the raycast
# plugins, whose own flags are theirs: only cmd/raycast.zsh counts.
help::verb_files() {
  local verb="${1}" file="${2:-${ARI_DOTFILES_CMD}/${1}.zsh}"
  reply=("${file}")
  [[ "${verb}" == raycast ]] || reply+=("${ARI_DOTFILES_CMD}/${verb}/"*.zsh(N))
}

# help::verb_gap VERB [FILE]: REPLY = what VERB's help lacks, FILE standing in for cmd/VERB.zsh.
# A declared verb (verb::define in its file) is held to help::declared_gap; one still written as a
# help_VERB heredoc to help::doc_gap.
help::verb_gap() {
  local verb="${1}" file="${2:-${ARI_DOTFILES_CMD}/${1}.zsh}"
  local -a reply
  help::verb_files "${verb}" "${file}"
  if help::is_declared "${file}" "${verb}"; then
    help::declared_gap "${verb}" "${reply[@]}"
  else
    help::doc_gap "${file}" "help_${verb}" "${reply[@]}"
  fi
}

# help::is_declared FILE VERB: 0 when FILE declares VERB with verb::define (lib/verb.zsh).
help::is_declared() {
  zmodload zsh/mapfile
  [[ "${mapfile[${1}]-}" == (|*$'\n')"verb::define ${2} "* ]]
}

# help::declared_gap VERB <parser file>..: REPLY = what a declared verb lacks, '' when nothing: its
# help comes from the declaration, so the rule is that the declaration is whole (a description,
# a Usage form, a description on every flag and subcommand, an edit or a reason for none) and that
# nothing parses a flag outside verb::parse (help::parser_flags finds none in its files).
help::declared_gap() {
  local verb="${1}" row
  shift
  local -a lacks=() reply
  [[ -n "${VERB_DESC[${verb}]:-}" ]] || lacks+=("no description (verb::define ${verb} '…')")
  [[ -n "${VERB_USAGE[${verb}]:-}${VERB_EDIT[${verb}]:-}" ]] || lacks+=("no Usage form (verb::usage)")
  for row in "${(@f)VERB_FLAGS[${verb}]:-}" "${(@f)VERB_SUBS[${verb}]:-}"; do
    [[ -z "${row}" || -n "${row#*$'\t'}" ]] || lacks+=("'${row%%$'\t'*}' has no description")
  done
  [[ -n "${VERB_EDIT[${verb}]:-}${VERB_EDIT_NONE[${verb}]:-}" ]] || lacks+=("no edit (verb::edit ${verb} HANDLER … or verb::edit ${verb} --none '<why>')")
  help::parser_flags "$@"
  (( ${#reply} == 0 )) || lacks+=("parses flags outside verb::parse: ${reply[*]}")
  REPLY="${(j:, :)lacks}"
}

# help::top_gap [FILE]: REPLY = what help() in lib/dispatch.zsh (or FILE) lacks for main()'s flags.
help::top_gap() {
  local file="${1:-${ARI_DOTFILES_LIB}/dispatch.zsh}"
  help::doc_gap "${file}" help "${file}"
}

# help::verb_names: reply = every verb by its file, cmd/VERB.zsh defining cmd_VERB.
help::verb_names() {
  zmodload zsh/mapfile
  local f
  reply=()
  for f in "${ARI_DOTFILES_CMD}"/*.zsh(N); do
    [[ "${mapfile[${f}]}" == (|*$'\n')"cmd_${f:t:r}() "* ]] && reply+=("${f:t:r}")
  done
  return 0
}
