# dotfiles/lib/plan.zsh — one shape for every `--edit` plan file (like `git rebase -i`'s todo).
#
#   plan::define KIND --actions "a b|global add|…" [--default ACTION] [--note "ACTION.."]
#                [--danger "ACTION.."] [--item HINT]
#     Declares a plan type. Actions are '|'-separated (one may be several words); --note lists, the
#     same way, the actions whose line needs a trailing `# note` (an ignore's reason, a commit's
#     message); --danger the ones that discard something (highlighted as such, confirmed by name).
#   plan::header KIND [TEXT..]   line 1, machine-readable (Neovim reads it), then the action key
#   plan::line ACTION ITEM [NOTE]   one plan line, columns aligned
#   plan::comment TEXT..   comment lines
#   plan::parse KIND FILE [ITEM_CHECK_FN]
#     Reads every line: `ACTION  ITEM  [# note]`; comments and blank lines skipped. `reply` gets one
#     `action\titem\tnote\tline` per line, in file order. Each problem goes to stderr as
#     `line N: …`; an unknown action, a missing or extra item, a missing note, an item listed twice,
#     and whatever ITEM_CHECK_FN ITEM ACTION prints (it returns non-zero for a bad item). Returns 1
#     when any line is bad.
#   plan::edit KIND FILE [ITEM_CHECK_FN] [--plan-check FN] [--resume CMD] [--changed]
#     edit::session on FILE with plan::parse as its check, then FN over the whole plan (rules that
#     span lines; it reads PLAN_LINES): 0 parsed (in `reply`), 2 unchanged, 1 left bad.
#
# Line 1 of a plan is `# dotfiles-plan: KIND · actions: a | b c | … · danger: x · note: y`; the
# `dotfilesplan` Neovim filetype reads it to highlight any plan, including ones added later.

typeset -gA PLAN_ACTIONS PLAN_DEFAULT PLAN_NOTE PLAN_DANGER PLAN_ITEM

plan::define() {
  local kind="${1:?plan::define: KIND}"; shift
  PLAN_DEFAULT[${kind}]="" PLAN_NOTE[${kind}]="" PLAN_DANGER[${kind}]="" PLAN_ITEM[${kind}]="ITEM"
  while (( $# )); do
    case "${1}" in
      --actions) PLAN_ACTIONS[${kind}]="${2}"; shift 2 ;;
      --default) PLAN_DEFAULT[${kind}]="${2}"; shift 2 ;;
      --note) PLAN_NOTE[${kind}]="${2}"; shift 2 ;;
      --danger) PLAN_DANGER[${kind}]="${2}"; shift 2 ;;
      --item) PLAN_ITEM[${kind}]="${2}"; shift 2 ;;
      *) print -u2 -r -- "plan::define: bad argument '${1}'"; return 64 ;;
    esac
  done
}

# plan::header KIND [TEXT..]: the machine line, the TEXT lines as comments, then the action key.
plan::header() {
  local kind="${1}"; shift
  local -a actions=("${(@s:|:)PLAN_ACTIONS[${kind}]}")
  print -r -- "# dotfiles-plan: ${kind} · actions: ${(j: | :)actions}${PLAN_DANGER[${kind}]:+ · danger: ${PLAN_DANGER[${kind}]}}${PLAN_NOTE[${kind}]:+ · note: ${PLAN_NOTE[${kind}]}}"
  local text
  for text in "$@"; do print -r -- "# ${text}"; done
  print -r -- "# One line per ${PLAN_ITEM[${kind}]}: <action>  <${PLAN_ITEM[${kind}]}>  [# note]. Actions: ${(j:, :)actions}."
  [[ -z "${PLAN_NOTE[${kind}]}" ]] || print -r -- "# A '# note' is required after: ${PLAN_NOTE[${kind}]}."
  [[ -z "${PLAN_DANGER[${kind}]}" ]] || print -r -- "# These discard something and are confirmed by name: ${PLAN_DANGER[${kind}]}."
  print -r -- "# Lines starting with # are comments."
  print -r -- ""
}

# PLAN_ITEM_WIDTH (optional): the item column's width, so the notes after it line up.
plan::line() {
  local item="${2}"
  [[ -z "${3:-}" || -z "${PLAN_ITEM_WIDTH:-}" ]] || item="${(r:PLAN_ITEM_WIDTH:)item}"
  print -r -- "${(r:14:)1}  ${item}${3:+  # ${3}}"
}
plan::comment() { local text; for text in "$@"; do print -r -- "#${text:+ ${text}}"; done; }

plan::parse() {
  setopt localoptions extendedglob
  local kind="${1}" file="${2}" check="${3:-}" line body note action item a out
  local -a actions=("${(@s:|:)PLAN_ACTIONS[${kind}]}") notes=("${(@s:|:)PLAN_NOTE[${kind}]}") words seen=() aw
  # Longest action first, so `global add` is tried before a one-word action that prefixes it.
  actions=("${(@O)actions}")
  local -i n=0 bad=0 nwords
  reply=()
  while IFS= read -r line || [[ -n "${line}" ]]; do
    n=$(( n + 1 ))
    body="${${line##[[:space:]]#}%%[[:space:]]#}"
    [[ -z "${body}" || "${body}" == '#'* ]] && continue
    note=""
    if [[ "${body}" == *'#'* ]]; then
      note="${${body#*\#}##[[:space:]]#}"; note="${note%%[[:space:]]#}"
      body="${${body%%\#*}%%[[:space:]]#}"
    fi
    words=(${=body}) action=""
    for a in "${actions[@]}"; do
      aw=(${=a}); nwords=${#aw}
      if [[ "${(j: :)words[1,nwords]}" == "${a}" ]]; then action="${a}"; words=("${(@)words[nwords+1,-1]}"); break; fi
    done
    if [[ -z "${action}" ]]; then
      print -u2 -r -- "line ${n}: unknown action; use ${(j:, :)${(@s:|:)PLAN_ACTIONS[${kind}]}} | line='${line}'"
      bad=1; continue
    fi
    if (( ${#words} != 1 )); then
      print -u2 -r -- "line ${n}: expected one ${PLAN_ITEM[${kind}]} after '${action}' | line='${line}'"
      bad=1; continue
    fi
    item="${words[1]}"
    if (( ${seen[(Ie)${item}]} )); then
      print -u2 -r -- "line ${n}: listed twice | item='${item}'"
      bad=1; continue
    fi
    seen+=("${item}")
    if [[ -n "${check}" ]] && ! out="$("${check}" "${item}" "${action}" 2>&1)"; then
      print -u2 -r -- "line ${n}: ${out:-not a ${PLAN_ITEM[${kind}]} here} | item='${item}'"
      bad=1; continue
    fi
    if (( ${notes[(Ie)${action}]} )) && [[ -z "${note}" ]]; then
      print -u2 -r -- "line ${n}: '${action}' needs a note: end the line with '# …' | item='${item}'"
      bad=1; continue
    fi
    reply+=("${action}"$'\t'"${item}"$'\t'"${note}"$'\t'"${n}")
  done < "${file}"
  return ${bad}
}

plan::edit() {
  local kind="${1}" file="${2}" check="" planfn=""
  shift 2
  if (( $# )) && [[ "${1}" != --* ]]; then check="${1}"; shift; fi
  local -a pass=()
  while (( $# )); do
    case "${1}" in
      --resume) pass+=(--resume "${2}"); shift 2 ;;
      --plan-check) planfn="${2}"; shift 2 ;;
      --changed) pass+=(--changed); shift ;;
      *) print -u2 -r -- "plan::edit: bad argument '${1}'"; return 64 ;;
    esac
  done
  typeset -g PLAN_CHECK="${check}" PLAN_KIND="${kind}" PLAN_WHOLE="${planfn}"
  local -i rc=0
  edit::session "${file}" --check plan::_check --what "the plan" "${pass[@]}" || rc=$?
  (( rc == 0 )) && plan::parse "${kind}" "${file}" "${check}" 2>/dev/null
  return ${rc}
}

# The session's check: every line (plan::parse), then the whole plan (--plan-check FN, which reads
# PLAN_LINES, the parsed lines, and prints a problem per line like plan::parse does).
plan::_check() {
  local -a reply
  plan::parse "${PLAN_KIND}" "${1}" "${PLAN_CHECK}" || return 1
  typeset -ga PLAN_LINES=("${reply[@]}")
  [[ -z "${PLAN_WHOLE}" ]] || "${PLAN_WHOLE}"
}
