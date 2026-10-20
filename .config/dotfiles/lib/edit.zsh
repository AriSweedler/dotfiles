# dotfiles/lib/edit.zsh — one way to open a file in $EDITOR and keep it only when it checks out.
# Every `--edit` in the harness goes through edit::session: the editor lookup, the unchanged test,
# the check on save, the re-edit offer on a terminal and the resume line live here and nowhere else.
# Drafts (a live file edited as a copy, put in place only once it passes) are edit::draft and
# edit::install. Functions only.

# edit::editor: `reply` is $EDITOR split into words (vi when unset or not found).
edit::editor() {
  reply=(${(z)${EDITOR:-vi}})
  (( ${#reply} )) && (( ${+commands[${reply[1]}]} || ${+functions[${reply[1]}]} )) || [[ -x "${reply[1]:-}" ]] || reply=(vi)
}

# edit::open [--line N] [--readonly] FILE..: the editor on FILE.., at line N of the first (vi, vim,
# nvim, nano, emacs, micro, hx and kak take +N) and read-only for the vi family. Returns its rc.
edit::open() {
  local -i line=0 readonly=0
  while (( $# )); do
    case "${1}" in
      --line) line="${2}"; shift 2 ;;
      --readonly) readonly=1; shift ;;
      --) shift; break ;;
      *) break ;;
    esac
  done
  local -a reply cmd
  edit::editor
  cmd=("${reply[@]}")
  case "${cmd[1]:t}" in
    vi|vim|nvim|view)
      (( readonly )) && cmd+=(-R)
      (( line > 0 )) && cmd+=("+${line}") ;;
    nano|emacs|micro|hx|kak) (( line > 0 )) && cmd+=("+${line}") ;;
  esac
  "${cmd[@]}" "$@"
}

# edit::session FILE [--check FN] [--resume CMD] [--line N] [--also FILE..] [--what WORD]
#   Opens FILE (and --also files beside it), then: unchanged → 2. Otherwise FN FILE runs (it prints
#   each problem on stderr, returns non-zero on any); passing → 0. Failing on a terminal offers
#   "Edit WORD again?" and loops; otherwise logs the problems' fix, `CMD`, keeps FILE and returns 1.
#   The editor failing returns 1 with FILE kept. --changed treats the first open as already changed
#   (a resumed draft or plan: the user's earlier edit is what is being checked).
edit::session() {
  local file="${1:?edit::session: FILE}" check="" resume="" what="" before
  shift
  local -i line=0 changed=0 rc
  local -a also=()
  while (( $# )); do
    case "${1}" in
      --check) check="${2}"; shift 2 ;;
      --resume) resume="${2}"; shift 2 ;;
      --line) line="${2}"; shift 2 ;;
      --what) what="${2}"; shift 2 ;;
      --changed) changed=1; shift ;;
      --also) shift; also=("$@"); break ;;
      *) print -u2 -r -- "edit::session: bad argument '${1}'"; return 64 ;;
    esac
  done
  [[ -n "${what}" ]] || what="${file:t}"
  before="$(mktemp "${TMPDIR:-/tmp}/dotfiles-edit.XXXXXX")" || return 1
  while true; do
    cp -- "${file}" "${before}"
    if ! edit::open --line "${line}" -- "${file}" "${also[@]}"; then
      rm -f -- "${before}"
      log::err "editor exited non-zero; ${what} kept as it was saved | file='${file}'${resume:+ fix='${resume}'}"
      return 1
    fi
    if (( ! changed )) && cmp -s -- "${before}" "${file}"; then
      rm -f -- "${before}"
      return 2
    fi
    changed=1
    if [[ -z "${check}" ]] || "${check}" "${file}"; then
      rm -f -- "${before}"
      return 0
    fi
    if [[ -t 0 && -t 1 ]] && ui::confirm "Edit ${what} again?"; then continue; fi
    rm -f -- "${before}"
    log::err "${what} not used; fix the problems above, then | file='${file}'${resume:+ fix='${resume}'}"
    return 1
  done
}

# edit::draft LIVE DIR [TEMPLATE_FN]: REPLY is the draft of LIVE under DIR (named for LIVE): a kept
# draft from a failed edit is resumed (said on stderr, `EDIT_RESUMED=1`), else LIVE is copied, else
# (no LIVE yet) TEMPLATE_FN's output starts it.
edit::draft() {
  local live="${1}" dir="${2}" template="${3:-}"
  typeset -g EDIT_RESUMED=0
  REPLY="${dir}/${${live#${HOME}/}//\//%}"
  mkdir -p -- "${dir}" || return 1
  if [[ -f "${REPLY}" ]]; then
    EDIT_RESUMED=1
    log::info "resuming the draft a failed edit left | draft='${REPLY}'"
  elif [[ -f "${live}" ]]; then
    cp -- "${live}" "${REPLY}"
  elif [[ -n "${template}" ]]; then
    "${template}" > "${REPLY}"
  else
    : > "${REPLY}"
  fi
}

# edit::install DRAFT LIVE [MODE]: DRAFT renamed over LIVE, via a sibling, so a reader never sees
# half a file. MODE defaults to LIVE's own (a new file: 644). The draft is gone afterwards.
edit::install() {
  local draft="${1}" live="${2}" mode="${3:-}"
  if [[ -z "${mode}" ]]; then
    if [[ -f "${live}" ]]; then zmodload -F zsh/stat b:zstat; local -A st; zstat -H st -- "${live}"; mode="$(( [##8] st[mode] & 8#777 ))"; else mode=644; fi
  fi
  mkdir -p -- "${live:h}" || return 1
  if cp -- "${draft}" "${live}.edit.$$" && chmod "${mode}" "${live}.edit.$$" && mv -f -- "${live}.edit.$$" "${live}"; then
    rm -f -- "${draft}"
    return 0
  fi
  rm -f -- "${live}.edit.$$"
  log::err "could not put the edit in place; the draft is kept | file='${live}' draft='${draft}'"
  return 1
}

# edit::same A B: 0 when the two files have the same bytes.
edit::same() { cmp -s -- "${1}" "${2}"; }
