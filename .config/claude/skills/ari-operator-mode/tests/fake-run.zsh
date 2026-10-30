#!/usr/bin/env zsh
# A fake run.zsh for frontier.zsh's tests: answers --list from canned pane lines and answers typed
# reads from canned files, in the shape a real run.zsh prints (PANE:, TYPED:, SENT, the pane echo, the
# @@BEGIN/@@END stream a typed read produces on the host, the prompt). It never executes the typed
# line; it picks a canned answer by what the line reads. Knobs, all environment variables:
#   FAKE_DIR            where <section>.{json,txt} canned outputs live (required); typed.log collects every typed line
#   FAKE_LIST           the --list output, one pane per line (default: an opted-in zsh pane %18 and a second pane)
#   FAKE_LIST_RC        make --list exit with this code and print nothing (default: 0)
#   FAKE_PROMPT_LINE    the pane's idle prompt line after a read (default: 'at 01:00:02 UTC ❯')
#   FAKE_RC             refuse every typed read with this exit code and FAKE_REFUSED (default: unset)
#   FAKE_RC_TIMES       with FAKE_RC: refuse only the first N typed reads, counted in FAKE_DIR/refusals.count (default: every read)
#   FAKE_RC_FOR         '<substring>:<code>': refuse only reads whose host command contains the substring
#   FAKE_REFUSED        the REFUSED: line printed with a refusal (default: 'REFUSED: fake refusal')
#   FAKE_TAIL           a pane tail line printed after the refusal, as run.zsh does (default: none)
#   FAKE_HOST_RC        '<substring>:<code>': the host command's own exit code inside the stream (default 0)
#   FAKE_EMPTY          a substring; a read whose command contains it gets empty output (what bd prints for nothing)
#   FAKE_TRUNCATE       a substring; a read whose command contains it loses its @@END line (a capture that never finished)
#   FAKE_SHORT          a substring; a read whose command contains it loses its last payload line (a truncated capture)
#   FAKE_STDERR_NOISE   a count; print this many [INFO] lines to stderr after stdout (default: 1)
set -uo pipefail
: "${FAKE_DIR:?FAKE_DIR is required}"
: "${FAKE_LIST:=machine=personal|ID=%18|pane=3.1 ✦ bound=none zsh 0: homelab -- laptop
machine=personal|ID=%3|pane=1.1 - bound=none zsh 0: caf -- laptop
machine=personal|ID=%30|pane=11.1 - bound=none bash 0: superseedr -- laptop}"
: "${FAKE_LIST_RC:=0}"
: "${FAKE_PROMPT_LINE:=at 01:00:02 UTC ❯}"
: "${FAKE_RC:=}"
: "${FAKE_RC_TIMES:=}"
: "${FAKE_RC_FOR:=}"
: "${FAKE_REFUSED:=REFUSED: fake refusal}"
: "${FAKE_TAIL:=}"
: "${FAKE_HOST_RC:=}"
: "${FAKE_EMPTY:=}"
: "${FAKE_TRUNCATE:=}"
: "${FAKE_SHORT:=}"
: "${FAKE_STDERR_NOISE:=1}"

action='' cmd=''
while (( $# > 0 )); do
  case "${1}" in
    --list) action=list; shift ;;
    --cmd) action=cmd; cmd="${2-}"; shift 2 ;;
    --host-definition|--target|--lines|--timeout) shift 2 ;;
    *) shift ;;
  esac
done

noise() {
  local i
  for (( i = 0; i < FAKE_STDERR_NOISE; i++ )); do
    print -r -- "[INFO] fake run.zsh | action='${action}' line='${i}' padding='$(printf 'x%.0s' {1..80})'" >&2
  done
}

if [[ "${action}" == list ]]; then
  if (( FAKE_LIST_RC != 0 )); then print -r -- "ssh: connect to host laptop port 22: No route to host" >&2; exit "${FAKE_LIST_RC}"; fi
  print -r -- "${FAKE_LIST}"
  noise
  exit 0
fi

print -r -- "PANE: ${${(f)FAKE_LIST}[1]%% *}"
print -r -- "${cmd}" >> "${FAKE_DIR}/typed.log"
# the host command sits between '{ ' and '; printf' in the typed line; the marker's nonce after 'Q%sQ'
host_cmd="${cmd#*\{ }"; host_cmd="${host_cmd%%; printf*}"
nonce="${cmd#*printf \'Q%sQ\' }"; nonce="${nonce%% *}"; M="@${nonce}@"

refuse() {   # <code>
  print -r -- "${FAKE_REFUSED}"
  [[ -n "${FAKE_TAIL}" ]] && print -r -- "${FAKE_TAIL}"
  noise
  exit "${1}"
}
if [[ -n "${FAKE_RC}" ]]; then
  if [[ -z "${FAKE_RC_TIMES}" ]]; then refuse "${FAKE_RC}"; fi
  counter="${FAKE_DIR}/refusals.count"
  n=0; [[ -r "${counter}" ]] && n="$(<"${counter}")"
  if (( n < FAKE_RC_TIMES )); then print -r -- $(( n + 1 )) > "${counter}"; refuse "${FAKE_RC}"; fi
fi
if [[ -n "${FAKE_RC_FOR}" && "${host_cmd}" == *"${FAKE_RC_FOR%%:*}"* ]]; then refuse "${FAKE_RC_FOR##*:}"; fi

print -r -- "TYPED: ${cmd}"
print -r -- "SENT"
print -r -- "at 01:00:01 UTC ❯${cmd}"
canned=''
case "${host_cmd}" in
  *" ready "*) canned="${FAKE_DIR}/ready.json" ;;
  *" stale "*) canned="${FAKE_DIR}/stale.txt" ;;
  *"in_progress"*) canned="${FAKE_DIR}/in_progress.json" ;;
  *"human list"*) canned="${FAKE_DIR}/human.txt" ;;
  *" blocked"*) canned="${FAKE_DIR}/blocked.txt" ;;
  *"deferred"*) canned="${FAKE_DIR}/deferred.json" ;;
  *"git -C"*) canned="${FAKE_DIR}/hostgit.txt" ;;
esac
host_rc=0
if [[ -n "${FAKE_HOST_RC}" && "${host_cmd}" == *"${FAKE_HOST_RC%%:*}"* ]]; then host_rc="${FAKE_HOST_RC##*:}"; fi
body=''
if [[ -n "${canned}" && -r "${canned}" ]] && ! [[ -n "${FAKE_EMPTY}" && "${host_cmd}" == *"${FAKE_EMPTY}"* ]]; then
  body="$(<"${canned}")"
fi
print -r -- "@@BEGIN"                                   # a stale stream from an earlier read, which the reader must ignore
print -r -- "@@c3RhbGU="
print -r -- "@@END 8"
print -r -- "${M}BEGIN"
encoded="$(print -r -- "${body}"$'\n'"__RC=${host_rc}" | gzip -c | base64 | tr -d '\n')"
lines=("${(@f)$(print -r -- "${encoded}" | fold -w 60)}")
if [[ -n "${FAKE_SHORT}" && "${host_cmd}" == *"${FAKE_SHORT}"* ]]; then lines=("${(@)lines[1,-2]}"); fi
for line in "${lines[@]}"; do print -r -- "${M}${line}"; done
if ! [[ -n "${FAKE_TRUNCATE}" && "${host_cmd}" == *"${FAKE_TRUNCATE}"* ]]; then print -r -- "${M}END ${#encoded}"; fi
print -r -- "${FAKE_PROMPT_LINE}"
noise
exit 0
