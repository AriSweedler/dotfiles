# dotfiles/lib/kind.zsh — a kind is the type of one value on the command line: what a flag takes
# (`--only STEP,..`) or what a position holds (`jobs run JOB`). The catalog is cmd/kinds.zsh; a
# declaration names a kind by writing it where the value goes, and the completion offers a kind's
# values wherever it is named.
#
#   kind::define KIND "what one value is" SOURCE
#
# KIND is upper-case (A-Z, _). A kind has exactly one SOURCE, where its values come from:
#   --words "a b c"     a fixed set, written out (stored as written and expanded when read, like a
#                       help text: '${STEP_GROUPS}' follows the array)
#   --lister FN         FN prints the values this machine has now, one per line
#   --files             any path
#   --free              text nothing can list (a new name, a revision)
#   --delegate COMMAND  the rest of the line is COMMAND's own; its completion takes over
#
# Two values share a kind only when they are the same thing: a step and a job are both names, and
# they are two kinds.

typeset -ga KINDS=()                                  # every kind, in catalog order
typeset -gA KIND_DESC=()                              # kind → what one value is
typeset -gA KIND_WORDS=() KIND_LISTER=() KIND_DELEGATE=() KIND_FILES=() KIND_FREE=()   # one per source

kind::define() {
  setopt localoptions extendedglob
  local kind="${1}" desc="${2}" source="${3:-}"
  [[ "${kind}" == [A-Z][A-Z_]# ]] || { print -u2 -r -- "kind::define: a kind is upper-case | kind='${kind}'"; return 64; }
  # A file sourced twice declares twice: the later declaration replaces the earlier.
  if (( ${+KIND_DESC[${kind}]} )); then unset "KIND_WORDS[${kind}]" "KIND_LISTER[${kind}]" "KIND_DELEGATE[${kind}]" "KIND_FILES[${kind}]" "KIND_FREE[${kind}]"
  else KINDS+=("${kind}"); fi
  case "${source}" in
    --words)    KIND_WORDS[${kind}]="${4}" ;;
    --lister)   KIND_LISTER[${kind}]="${4}" ;;
    --delegate) KIND_DELEGATE[${kind}]="${4}" ;;
    --files)    KIND_FILES[${kind}]=1 ;;
    --free)     KIND_FREE[${kind}]=1 ;;
    *) print -u2 -r -- "kind::define: a kind has one source | kind='${kind}' source='${source}' valid='--words --lister --files --free --delegate'"; return 64 ;;
  esac
  KIND_DESC[${kind}]="${desc}"
}

kind::is_known() { (( ${+KIND_DESC[${1}]} )); }

# kind::source KIND: REPLY = words | lister | files | free | delegate.
kind::source() {
  local kind="${1}"
  if (( ${+KIND_WORDS[${kind}]} )); then REPLY=words
  elif (( ${+KIND_LISTER[${kind}]} )); then REPLY=lister
  elif (( ${+KIND_FILES[${kind}]} )); then REPLY=files
  elif (( ${+KIND_FREE[${kind}]} )); then REPLY=free
  elif (( ${+KIND_DELEGATE[${kind}]} )); then REPLY=delegate
  else REPLY=""; return 1; fi
}

# kind::words KIND: reply = the fixed set of a --words kind.
kind::words() { reply=(${(z)${(e)KIND_WORDS[${1}]}}); }

# kind::values KIND: the values that can be listed, one per line: a fixed set, or what the lister
# prints. A files, free or delegate kind has none to list.
kind::values() {
  local kind="${1}" REPLY
  local -a reply
  kind::source "${kind}" || return 1
  case "${REPLY}" in
    words)  kind::words "${kind}"; (( ! ${#reply} )) || print -rl -- "${reply[@]}" ;;
    lister) "${KIND_LISTER[${kind}]}" ;;
  esac
}

# kind::of_spec SPEC: reply = the kinds a value spec names. A spec is what a declaration writes
# where a value goes: KIND, [KIND] (optional), KIND.. (one or more words), KIND,.. (one word, a
# comma list), A|B (either).
kind::of_spec() {
  local spec="${1}"
  local alt
  reply=()
  spec="${${spec#\[}%\]}"
  for alt in "${(@s:|:)spec}"; do reply+=("${${alt%..}%,}"); done
}
