#!/usr/bin/env zsh
# Lay out a one-line command for a human to read. Each command of a pipeline or list gets its own line, led
# by its | && || or ;; within one, words fill the line, and a new line starts only before a long argument;
# jq's program, and a JSON value given to a flag that parses JSON, is laid out inside its quotes. Only
# whitespace between words, and between a program's tokens, changes, so the shell runs the laid-out text as
# it runs the one line. link.zsh prints it in the chat code block; focus.zsh and handoff.zsh type or show
# the same text; /ari-driving-remote's bin/run.zsh sources it for wrap_run_log_text, so a change here also
# runs its tests/run-typed-text.test.zsh. Source it; no `readonly`, so a caller may source it twice.

# A command longer than this, or one with a long program argument, is laid out; no laid-out line passes it
# unless one word is longer.
WRAP_WIDTH=100
# A quoted argument longer than this starts its own line; a program argument longer than this is laid out.
WRAP_LONG=40
# Spaces per indent level: a pipeline stage is one in, a continued line two past its stage, a program's
# entries one past its closer.
WRAP_STEP=2
# (z) words that end one command of a list or pipeline: the next command starts its own line.
WRAP_LIST_OPERATORS=('|' '|&' '||' '&&' ';' '&' '&!' '&|')
# A compound command first in its command stays on that line whole, with everything after it.
WRAP_COMPOUND_WORDS=(for foreach while until if case select repeat function coproc '{' '(' '((' '[[' '!')
# Words before the program that run it (their flags are skipped too): the program is the next word.
WRAP_COMMAND_WRAPPERS=(env time command builtin exec nohup noglob sudo run_log)
# Flags whose value is parsed as JSON; a flag ending in -json counts too. Any other quoted text that looks
# like JSON (a grep pattern, a jq --arg string) is left as written: its bytes are its meaning.
WRAP_JSON_FLAGS=(--policy --policy-document --json --data --data-raw --data-binary -d --body --payload --patch
  -p --overrides --variables --input --params)
# The heredoc delimiter wrap_run_log_text uses, unless a line of the command is that word.
WRAP_HEREDOC_DELIMITER=RUN_LOG
# Where wrap_string_end and wrap_close_index put the index they found (no subshell per string).
typeset -gi WRAP_AT=0

#######################################
# Spaces.
# Arguments: $1 count
# Outputs: that many spaces on stdout
#######################################
wrap_pad() {
  local -i width="${1}"
  print -rn -- "${(l:width:)${:-}}"
}

#######################################
# Whether a word is a redirection operator, which takes the next word as its target (2>, >>, &>, 2>&, <<<).
# Arguments: $1 word
#######################################
wrap_is_redirection() {
  setopt local_options extended_glob
  [[ "${1}" == [0-9]#[\<\>\&]##[\|\!]# && "${1}" == *[\<\>]* ]]
}

#######################################
# Whether a flag takes the next word as its value: a long flag without =, or a single-letter short one.
# A cluster such as -sS or -it is boolean switches.
# Arguments: $1 word
#######################################
wrap_flag_takes_value() {
  setopt local_options extended_glob
  [[ "${1}" == --[^=]## || "${1}" == -[^-] ]]
}

#######################################
# Whether a word can be a flag's value: not a flag (a lone - is stdin), operator or redirection.
# Arguments: $1 word
#######################################
wrap_is_value_word() {
  if [[ "${1}" == -?* ]] || wrap_is_redirection "${1}" || (( ${WRAP_LIST_OPERATORS[(Ie)${1}]} )); then
    return 1
  fi
}

#######################################
# Whether a flag's value is JSON (WRAP_JSON_FLAGS, or a long flag ending in -json).
# Arguments: $1 flag
#######################################
wrap_is_json_flag() {
  (( ${WRAP_JSON_FLAGS[(Ie)${1}]} )) || [[ "${1}" == --*-json ]]
}

#######################################
# The whitespace before each (z) word of the command, as written, so words that share a line keep their
# spacing (`2>/dev/null`, `b; do`). Fails when the words do not spell the command with only whitespace
# between them; such a text is left on one line.
# Arguments: $1 command  $2.. its (z) words
# Outputs: one gap per word on stdout, each followed by a NUL
#######################################
wrap_word_gaps() {
  local cmd="${1}" word rest gap
  local -i at=1 found
  shift
  for word in "${@}"; do
    rest="${cmd[at,-1]}"
    found="${rest[(i)${(b)word}]}"
    if (( found > ${#rest} )); then
      return 1
    fi
    gap="${rest[1,found-1]}"
    if [[ -n "${gap//[[:space:]]/}" ]]; then
      return 1
    fi
    print -rn -- "${gap}"$'\0'
    at=$(( at + found - 1 + ${#word} ))
  done
  if [[ -n "${${cmd[at,-1]}//[[:space:]]/}" ]]; then
    return 1
  fi
}

#######################################
# Where the double-quoted string opened at a position ends, its escapes skipped.
# Arguments: $1 text  $2 index of the opening "
# Globals: WRAP_AT = the index of the closing " (the text's length when unterminated)
#######################################
wrap_string_end() {
  local text="${1}" ch
  local -i i
  for (( i = ${2} + 1; i <= ${#text}; i++ )); do
    ch="${text[i]}"
    if [[ "${ch}" == \\ ]]; then
      i=$(( i + 1 ))
      continue
    fi
    if [[ "${ch}" == \" ]]; then
      WRAP_AT="${i}"
      return 0
    fi
  done
  WRAP_AT="${#text}"
}

#######################################
# Where the bracket opened at a position closes: { [ ( nest, strings are skipped.
# Arguments: $1 text  $2 index of the opener
# Globals: WRAP_AT = the index of its closer
# Returns: 1 when it never closes
#######################################
wrap_close_index() {
  local text="${1}" ch
  local -i i="${2}" depth=0
  while (( i <= ${#text} )); do
    ch="${text[i]}"
    case "${ch}" in
      \")
        wrap_string_end "${text}" "${i}"
        i="${WRAP_AT}" ;;
      [\{\[\(]) depth+=1 ;;
      [\}\]\)])
        depth=$(( depth - 1 ))
        if (( depth == 0 )); then
          WRAP_AT="${i}"
          return 0
        fi ;;
    esac
    i=$(( i + 1 ))
  done
  return 1
}

#######################################
# Split a container's inside at its own commas (not those of nested brackets or strings).
# Arguments: $1 text inside the brackets
# Outputs: the entries on stdout, NUL-separated
#######################################
wrap_top_split() {
  local text="${1}" ch entry=""
  local -i i=1 depth=0
  while (( i <= ${#text} )); do
    ch="${text[i]}"
    case "${ch}" in
      \")
        wrap_string_end "${text}" "${i}"
        entry+="${text[i,WRAP_AT]}"; i=$(( WRAP_AT + 1 ))
        continue ;;
      [\{\[\(]) depth+=1 ;;
      [\}\]\)]) depth=$(( depth - 1 )) ;;
      ,)
        if (( depth == 0 )); then
          print -rn -- "${entry}"$'\0'
          entry="" i=$(( i + 1 ))
          continue
        fi ;;
    esac
    entry+="${ch}" i=$(( i + 1 ))
  done
  print -rn -- "${entry}"
}

#######################################
# An object entry with one space after its key's colon: `"a":1` reads `"a": 1`.
# Arguments: $1 entry, trimmed
# Outputs: the entry on stdout
#######################################
wrap_entry_colon() {
  setopt local_options extended_glob
  local entry="${1}" ch
  local -i i=1 depth=0
  while (( i <= ${#entry} )); do
    ch="${entry[i]}"
    case "${ch}" in
      \")
        wrap_string_end "${entry}" "${i}"
        i="${WRAP_AT}" ;;
      [\{\[\(]) depth+=1 ;;
      [\}\]\)]) depth=$(( depth - 1 )) ;;
      :)
        if (( depth == 0 )); then
          print -rn -- "${${entry[1,i-1]}%%[[:space:]]#}: ${${entry[i+1,-1]}##[[:space:]]#}"
          return 0
        fi ;;
    esac
    i=$(( i + 1 ))
  done
  print -rn -- "${entry}"
}

#######################################
# Whether a container is laid out over several lines: an object longer than WRAP_LONG, or an array that
# long with several entries and an object among them. Others stay inline, their insides still laid out.
# Arguments: $1 opener  $2 text inside the brackets
#######################################
wrap_is_breakable() {
  local opener="${1}" inner="${2}"
  if [[ -z "${inner//[[:space:]]/}" ]] || (( ${#inner} + 2 <= WRAP_LONG )); then
    return 1
  fi
  if [[ "${opener}" == '{' ]]; then
    return 0
  fi
  local -a entries=("${(@0)$(wrap_top_split "${inner}")}")
  [[ "${opener}" == '[' && "${inner}" == *'{'* ]] && (( ${#entries} > 1 ))
}

#######################################
# Lay out one container: the opener, its entries one per line indented a step past the closer, the closer
# on its own line at the base indent. jq shorthand keys (`{name, id}`) share a line.
# Arguments: $1 opener  $2 inside  $3 closer  $4 base indent
# Outputs: the laid-out container on stdout
#######################################
wrap_program_break() {
  setopt local_options extended_glob
  local opener="${1}" inner="${2}" closer="${3}" entry piece line="" out="" pad_in
  local -i base="${4}" inner_indent j=0 short prev_short=0
  local -a entries=("${(@0)$(wrap_top_split "${inner}")}")
  inner_indent=$(( base + WRAP_STEP ))
  pad_in="$(wrap_pad "${inner_indent}")"
  for entry in "${entries[@]}"; do
    j+=1
    entry="${${entry##[[:space:]]#}%%[[:space:]]#}"
    short=0
    if [[ "${opener}" == '{' ]]; then
      entry="$(wrap_entry_colon "${entry}")"
      if [[ "${entry}" == (\$|)[A-Za-z_][A-Za-z0-9_]# ]]; then
        short=1
      fi
    fi
    piece="$(wrap_program_format "${entry}" "${inner_indent}")"
    if (( j < ${#entries} )); then
      piece+=","
    fi
    if (( short && prev_short )) && [[ -n "${line}" ]] && (( inner_indent + ${#line} + 1 + ${#piece} <= WRAP_WIDTH )); then
      line+=" ${piece}"
    else
      if [[ -n "${line}" ]]; then
        out+=$'\n'"${pad_in}${line}"
      fi
      line="${piece}"
    fi
    prev_short="${short}"
  done
  out+=$'\n'"${pad_in}${line}"$'\n'"$(wrap_pad "${base}")${closer}"
  print -rn -- "${opener}${out}"
}

#######################################
# Lay out a JSON or jq program: each breakable container per wrap_program_break, everything else as written.
# Whitespace is added or trimmed only beside { [ , } ] and a key's colon, never inside a string or a token.
# Arguments: $1 program text  $2 base indent (where a broken container's closer goes)
# Outputs: the laid-out text on stdout
#######################################
wrap_program_format() {
  local text="${1}" ch inner out=""
  local -i base="${2}" i=1 end
  while (( i <= ${#text} )); do
    ch="${text[i]}"
    case "${ch}" in
      \")
        wrap_string_end "${text}" "${i}"
        out+="${text[i,WRAP_AT]}"; i=$(( WRAP_AT + 1 )) ;;
      [\{\[\(])
        if ! wrap_close_index "${text}" "${i}"; then
          out+="${text[i,-1]}"
          break
        fi
        end="${WRAP_AT}" inner="${text[i+1,WRAP_AT-1]}"
        if wrap_is_breakable "${ch}" "${inner}"; then
          out+="$(wrap_program_break "${ch}" "${inner}" "${text[end]}" "${base}")"
        else
          out+="${ch}$(wrap_program_format "${inner}" "${base}")${text[end]}"
        fi
        i=$(( end + 1 )) ;;
      *)
        out+="${ch}"; i=$(( i + 1 )) ;;
    esac
  done
  print -rn -- "${out}"
}

#######################################
# A long single-quoted program argument laid out inside its quotes: jq's program (kind jq; one with a #
# comment or a \( interpolation is left as written), or a JSON object or array given to a JSON flag, alone
# or as --flag='…' (kind json). Single-quoted text only: its value is literal, so nothing else changes.
# Arguments: $1 word as written  $2 indent of the line it lands on  $3 kind (jq | json | empty)
# Outputs: the laid-out word on stdout
# Returns: 1 when the word is left as written
#######################################
wrap_program_word() {
  setopt local_options extended_glob
  local word="${1}" kind="${3}" prefix body
  local -i indent="${2}"
  if [[ -z "${kind}" || "${word}" != (#b)((-##[A-Za-z0-9_-]##)=|)\'([^\']#)\' ]]; then
    return 1
  fi
  prefix="${match[1]}" body="${match[3]}"
  if (( ${#body} <= WRAP_LONG )) || [[ "${body}" != *[\{\[]* ]]; then
    return 1
  fi
  if [[ "${kind}" == jq && ( "${body}" == *'#'* || "${body}" == *'\('* ) ]]; then
    return 1
  fi
  if [[ "${kind}" == json && "${body}" != [\{\[]*[\}\]] ]]; then
    return 1
  fi
  print -rn -- "${prefix}'$(wrap_program_format "${body}" $(( indent + WRAP_STEP )))'"
}

#######################################
# Whether a word is a quoted string longer than WRAP_LONG (a flag's value counts), which starts a line.
# Arguments: $1 word
#######################################
wrap_is_long_quoted() {
  setopt local_options extended_glob
  [[ "${1}" == ((-##[A-Za-z0-9_-]##|[A-Za-z_][A-Za-z0-9_]#)=|)(\'|\"|\$\')* ]] && (( ${#1} > WRAP_LONG ))
}

#######################################
# The program kind of each word of one command: jq for jq's program (its first operand), json for a value
# given to a JSON flag, empty otherwise. The program is the first word after VAR=value words and wrappers.
# Arguments: $1.. the command's words
# Outputs: one kind per word on stdout, NUL-separated
#######################################
wrap_word_kinds() {
  setopt local_options extended_glob
  local -a words=("${@}") kinds=()
  local -i n="${#words}" p=1 j k in_wrapper=0
  for (( k = 1; k <= n; k++ )); do
    kinds+=("")
  done
  while (( p <= n )); do
    if [[ "${words[p]}" == [A-Za-z_][A-Za-z0-9_]#=* ]] || (( ${WRAP_COMMAND_WRAPPERS[(Ie)${words[p]}]} )); then
      in_wrapper=1 p=$(( p + 1 ))
    elif (( in_wrapper )) && [[ "${words[p]}" == -* ]]; then
      p=$(( p + 1 ))
    else
      break
    fi
  done
  if [[ "${words[p]:-}" == (*/|)jq ]]; then
    j=$(( p + 1 ))
    while (( j <= n )); do
      case "${words[j]}" in
        --arg|--argjson|--slurpfile|--rawfile) j=$(( j + 3 )) ;;
        --indent|-L) j=$(( j + 2 )) ;;
        -f|--from-file) break ;;
        -*) j=$(( j + 1 )) ;;
        *) kinds[j]=jq; break ;;
      esac
    done
  fi
  for (( k = 1; k <= n; k++ )); do
    if (( k > 1 )) && wrap_is_json_flag "${words[k-1]}" && [[ "${words[k]}" == \'[\{\[]* ]]; then
      kinds[k]=json
    elif [[ "${words[k]}" == (#b)(-[^=]##)=\'[\{\[]* ]] && wrap_is_json_flag "${match[1]}"; then
      kinds[k]=json
    fi
  done
  print -rn -- "${(pj:\0:)kinds}"
}

#######################################
# Lay out one command (a stage of a pipeline or list): words fill the line from its head; a new line, two
# steps past the head, starts before a quoted string over WRAP_LONG, before a long flag with its value when
# the command does not fit on one line, and before anything that would overflow WRAP_WIDTH. A flag and its
# value, and a redirection and its target, stay together. Program arguments are laid out per wrap_program_word.
# Arguments: $1 head (indent and operator)  $2 indent of the head line  $3 whether a compound command (0|1)
#   $4 word count N  $5.. the command's N words, then their N gaps
# Outputs: the lines on stdout, NUL-separated
#######################################
wrap_stage() {
  local head="${1}" first unit_text
  local -i indent="${2}" compound="${3}" n="${4}" cont k u fits brk long_flag line_indent
  shift 4
  local -a words=("${(@)argv[1,n]}") gaps=("${(@)argv[n+1,2*n]}") kinds=()
  cont=$(( indent + 2 * WRAP_STEP ))
  local inline="" line="${head}"
  for (( k = 1; k <= n; k++ )); do
    if (( k == 1 )); then
      inline+="${words[k]}"
    else
      inline+="${gaps[k]}${words[k]}"
    fi
  done
  if (( compound )); then
    print -rn -- "${line}${inline}"
    return 0
  fi
  kinds=("${(@0)$(wrap_word_kinds "${words[@]}")}")
  fits=$(( ${#head} + ${#inline} <= WRAP_WIDTH ))
  for (( k = 1; k <= n; k++ )); do
    if wrap_is_long_quoted "${words[k]}" && ! wrap_program_word "${words[k]}" 0 "${kinds[k]:-}" >/dev/null; then
      fits=0
    fi
  done
  local -a lines=()
  k=1
  while (( k <= n )); do
    u=1
    if (( k < n )) && { wrap_is_redirection "${words[k]}" || wrap_flag_takes_value "${words[k]}"; } \
        && wrap_is_value_word "${words[k+1]}"; then
      u=2
    fi
    long_flag=0
    if [[ "${words[k]}" == --?* ]] && (( u == 2 )) || [[ "${words[k]}" == --?*=* ]]; then
      long_flag=1
    fi
    brk=0
    if (( k > 1 )); then
      if wrap_is_long_quoted "${words[k+u-1]}" && ! wrap_program_word "${words[k+u-1]}" 0 "${kinds[k+u-1]:-}" >/dev/null; then
        brk=1
      elif (( ! fits && long_flag )); then
        brk=1
      else
        unit_text="$(wrap_stage_unit 0 "${words[k]}" "${kinds[k]:-}" "${gaps[k+1]:-}" "${words[k+1]:-}" "${kinds[k+1]:-}" "${u}")"
        if (( ${#${line##*$'\n'}} + ${#gaps[k]} + ${#${unit_text%%$'\n'*}} > WRAP_WIDTH )); then
          brk=1
        fi
      fi
    fi
    if (( brk )); then
      lines+=("${line}")
      line="$(wrap_pad "${cont}")"
    elif (( k > 1 )); then
      line+="${gaps[k]}"
    fi
    first="${line##*$'\n'}"
    line_indent=$(( ${#first} - ${#${first##[[:space:]]#}} ))
    line+="$(wrap_stage_unit "${line_indent}" "${words[k]}" "${kinds[k]:-}" "${gaps[k+1]:-}" "${words[k+1]:-}" "${kinds[k+1]:-}" "${u}")"
    k=$(( k + u ))
  done
  lines+=("${line}")
  print -rn -- "${(pj:\0:)lines}"
}

#######################################
# One unit of a command, a word or a flag with its value, its program argument laid out.
# Arguments: $1 indent of the line it lands on  $2 first word  $3 its kind  $4 gap before the second
#   $5 second word  $6 its kind  $7 how many words (1|2)
# Outputs: the unit on stdout
#######################################
wrap_stage_unit() {
  local -i indent="${1}" count="${7}"
  local first="${2}" first_kind="${3}" gap="${4}" second="${5}" second_kind="${6}" formatted
  if formatted="$(wrap_program_word "${first}" "${indent}" "${first_kind}")"; then
    first="${formatted}"
  fi
  if (( count == 1 )); then
    print -rn -- "${first}"
    return 0
  fi
  if formatted="$(wrap_program_word "${second}" "${indent}" "${second_kind}")"; then
    second="${formatted}"
  fi
  print -rn -- "${first}${gap}${second}"
}

#######################################
# Lay out a command for reading (see the file's header). Printed unchanged: a command no longer than
# WRAP_WIDTH with no long program argument; one with a newline or a # word (with interactive_comments
# set, a comment would swallow the ` \`); one (z) cannot split exactly.
# Arguments: $1 command (one line)
# Outputs: the text on stdout, lines joined with ` \` and a newline
#######################################
wrap_command() {
  setopt local_options extended_glob
  local cmd="${1}" gap_text stage_text
  local -a words=("${(z)cmd}") gaps=() lines=() starts=() ends=() ops=("")
  if [[ "${cmd}" == *$'\n'* ]] || (( ${words[(I)[#]*]} )) || ! gap_text="$(wrap_word_gaps "${cmd}" "${words[@]}")"; then
    print -r -- "${cmd}"
    return 0
  fi
  gaps=("${(@0)gap_text}")
  local -i k s start=1 compound=0 n="${#words}" indent
  for (( k = 1; k <= n; k++ )); do
    if (( k == start && ! compound )) && (( ${WRAP_COMPOUND_WORDS[(Ie)${words[k]}]} )); then
      compound=$(( ${#starts} + 1 ))
    fi
    if (( ! compound )) && (( ${WRAP_LIST_OPERATORS[(Ie)${words[k]}]} )); then
      starts+=("${start}"); ends+=($(( k - 1 ))); ops+=("${words[k]}")
      start=$(( k + 1 ))
    fi
  done
  starts+=("${start}"); ends+=("${n}")
  local head
  for (( s = 1; s <= ${#starts}; s++ )); do
    indent=$(( s == 1 ? 0 : WRAP_STEP ))
    head="$(wrap_pad "${indent}")${ops[s]}"
    if (( starts[s] > ends[s] )); then
      lines+=("${head}")
      continue
    fi
    if [[ -n "${ops[s]}" ]]; then
      head+=" "
    fi
    stage_text="$(wrap_stage "${head}" "${indent}" $(( compound == s )) $(( ends[s] - starts[s] + 1 )) \
      "${(@)words[starts[s],ends[s]]}" "${(@)gaps[starts[s],ends[s]]}")"
    lines+=("${(@0)stage_text}")
  done
  if (( ${#cmd} <= WRAP_WIDTH )) && [[ "${(j::)lines}" != *$'\n'* ]]; then
    print -r -- "${cmd}"
    return 0
  fi
  print -r -- "${(pj: \\\n:)lines}"
}

#######################################
# The heredoc delimiter for a text: WRAP_HEREDOC_DELIMITER, or with a suffix when a line of the text is it.
# Arguments: $1 text
# Outputs: the delimiter on stdout
#######################################
wrap_heredoc_delimiter() {
  local text="${1}" delimiter="${WRAP_HEREDOC_DELIMITER}"
  local -i n=0
  while (( ${${(f)text}[(Ie)${delimiter}]} )); do
    n+=1
    delimiter="${WRAP_HEREDOC_DELIMITER}_${n}"
  done
  print -r -- "${delimiter}"
}

#######################################
# The text that hands a command to run_log as one shell string, quoted so a person reads it as written: in
# single quotes when it has none; in double quotes when it has single quotes but nothing double quotes act
# on (" $ ` \ !); else, and whenever it is laid out, a quoted heredoc read by `command cat` (no alias), which
# takes the text byte for byte. run_log's zsh joins the ` \` lines back into the one command.
# Arguments: $1 run_log flags, each followed by a space (may be empty)  $2 command (one line)
# Outputs: the text to type on stdout
#######################################
wrap_run_log_text() {
  local flags="${1}" cmd="${2}" display delimiter
  display="$(wrap_command "${cmd}")"
  if [[ "${display}" != *$'\n'* && "${cmd}" != *\'* ]]; then
    print -r -- "run_log ${flags}'${cmd}'"
    return 0
  fi
  if [[ "${display}" != *$'\n'* && "${cmd}" != *[\"\$\`\\\!]* ]]; then
    print -r -- "run_log ${flags}\"${cmd}\""
    return 0
  fi
  delimiter="$(wrap_heredoc_delimiter "${display}")"
  print -r -- "run_log ${flags}\"\$(command cat <<'${delimiter}'"
  print -r -- "${display}"
  print -r -- "${delimiter}"
  print -r -- ')"'
}
