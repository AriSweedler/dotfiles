# open_any — open the clipboard (or $1) with the one opener whose --check accepts it.
#
# Openers are the open-* executables in the global and local bin tiers, discovered by name.
# Zero or several matches warn and do nothing: a guess must never open the wrong thing.
#
# ── The open-* interface (hand this to whoever writes or audits an opener) ────────────────
# An opener is an executable open-<kind> (kebab-case) in ~/.config/bin or ~/.local/bin that:
#   1. Takes its subject from $1 when given, else from the clipboard (open_any::input_text).
#   2. `open-<kind> --check [text]` exits 0 iff the text is this opener's kind of thing, and
#      exits 1 otherwise. It prints nothing, opens nothing, needs no network or token, and
#      returns only 0 or 1 (a usage error, 64, counts as a bug). It must be fast: a regex, no
#      process spawns.
#   3. Without --check it opens the thing, logging what and where; exit 0 on success, else
#      non-zero with a log::err that names what it tried and why it failed.
#   4. Its acceptance rule is disjoint from every other opener's for realistic inputs, because
#      open-any refuses to guess when two say yes. When two kinds overlap (a URL that is also
#      some tracker's item), the broader opener must decline the overlap explicitly. Pick a
#      distinguishing shape (a prefix, a host) over a bare number or word.
#   5. The logic is a zsh function open_<kind> in a plugin file open_*.zsh under
#      ~/.config/zsh/plugins or ~/.local/share/zsh/plugins; the script is the thin wrapper
#      `source <plugin>; open_<kind> "$@"`. open-any sources those plugins and probes the
#      function in-process (a zsh start per probe costs more than the whole dispatch).
# `open-any --verify` checks 2 and 5 against every opener found; run it after adding one.
#
# Env: OPEN_ANY_IGNORE_DIR_GLOBAL / OPEN_ANY_IGNORE_DIR_LOCAL skip a tier; OPEN_ANY_DIRS is a
# colon list of extra opener dirs. The same three knobs exist for tmux-oneshot.

(( ${+functions[log::info]} )) || source "${${(%):-%x}:A:h}/log.zsh"

# Input: "$@" of the caller. Output: the arg, else the clipboard.
# Callers validate the content; this only picks the source.
function open_any::input_text() {
  if (( $# == 1 )); then
    print -r -- "${1}"
  else
    pbpaste 2>/dev/null
  fi
}

# One-line preview of the input for logs.
function open_any::snippet() {
  print -r -- "${${1//$'\n'/ }[1,60]}"
}

# Every opener takes `--check [text]`: 0 when the text is its kind of thing, no output, no
# side effects. Callers: `if open_any::take_check_flag "$@"; then check=1; shift; fi`.
function open_any::take_check_flag() {
  [[ "${1:-}" == --check ]]
}

function open_any::dirs() {
  [[ -z "${OPEN_ANY_IGNORE_DIR_GLOBAL:-}" ]] && print -r -- "${XDG_CONFIG_HOME:-${HOME}/.config}/bin"
  [[ -z "${OPEN_ANY_IGNORE_DIR_LOCAL:-}" ]]  && print -r -- "${HOME}/.local/bin"
  local d
  for d in ${(s.:.)${OPEN_ANY_DIRS:-}}; do
    print -r -- "${d/#\~/${HOME}}"
  done
  return 0
}

# Output: one opener name per line, first dir wins on a name clash. open-any is not an opener.
function open_any::openers() {
  local -A seen
  local d f
  for d in ${(f)"$(open_any::dirs)"}; do
    for f in "${d}"/open-*(N.x:t); do
      [[ "${f}" == open-any ]] && continue
      (( ${+seen[${f}]} )) && continue
      seen[${f}]=1
      print -r -- "${f}"
    done
  done
}

# Input: opener name. Output: its path in the first dir that has it, so a dir off PATH works.
function open_any::path_of() {
  local d
  for d in ${(f)"$(open_any::dirs)"}; do
    if [[ -x "${d}/${1}" ]]; then
      print -r -- "${d}/${1}"
      return 0
    fi
  done
  return 1
}

# Sources every opener plugin so the open_<kind> functions exist in this shell. Idempotent
# enough: plugins are function definitions.
function open_any::load_plugins() {
  local d f
  for d in "${ZDOTDIR:-${HOME}/.config/zsh}/plugins" "${XDG_DATA_HOME:-${HOME}/.local/share}/zsh/plugins"; do
    for f in "${d}"/open_*.zsh(N); do
      [[ "${f:t}" == open_any.zsh || "${f:t}" == *.test.zsh ]] && continue
      source "${f}"
    done
  done
}

# Input: opener name, then the opener's argv. Runs open_<kind> in-process when loaded, else
# the script. Exit: the opener's.
function open_any::run() {
  local opener="${1}" fn="${1//-/_}"
  shift
  if (( ${+functions[${fn}]} )); then
    "${fn}" "$@"
  else
    "$(open_any::path_of "${opener}")" "$@"
  fi
}

function open_any::verify() {
  local -a openers=(${(f)"$(open_any::openers)"})
  open_any::load_plugins
  local o fn rc out t bad=0 any_bad=0
  for o in "${openers[@]}"; do
    bad=0
    fn="${o//-/_}"
    if (( ! ${+functions[${fn}]} )); then
      log::err "no plugin function, breaks rule 5 | opener='${o}' expected_function='${fn}'"
      bad=1
    fi
    for t in 'zzz' '' 'two words'; do
      out="$("$(open_any::path_of "${o}")" --check "${t}" 2>/dev/null)"; rc=$?
      if (( rc > 1 )) || [[ -n "${out}" ]]; then
        log::err "breaks the --check contract, rule 2 | opener='${o}' text='${t}' rc='${rc}' stdout='${out}'"
        bad=1
      fi
    done
    (( bad )) && any_bad=1
    (( bad )) || log::info "ok | opener='${o}' function='${fn}'"
  done
  return ${any_bad}
}

# Usage: open_any [text]   |   open_any --list   |   open_any --verify     # no arg: clipboard
function open_any() {
  case "${1:-}" in
    --list)   open_any::openers; return 0 ;;
    --verify) open_any::verify; return $? ;;
  esac

  local -a openers=(${(f)"$(open_any::openers)"}) matched=() declined=()
  if (( ${#openers} == 0 )); then
    log::warn "No openers installed, nothing opened | looked_in='${(j:, :)${(f)"$(open_any::dirs)"}}'"
    return 1
  fi
  open_any::load_plugins

  local text opener snippet
  text="$(open_any::input_text "$@")"
  for opener in "${openers[@]}"; do
    if open_any::run "${opener}" --check "${text}" >/dev/null; then
      matched+=("${opener}")
    else
      declined+=("${opener}")
    fi
  done

  snippet="$(open_any::snippet "${text}")"
  case ${#matched} in
    1) log::info "Dispatching | opener='${matched[1]}' text='${snippet}'"
       open_any::run "${matched[1]}" "${text}" ;;
    0) log::warn "No opener accepts this, nothing opened | text='${snippet}' asked='${(j:, :)declined}'"; return 1 ;;
    *) log::warn "Ambiguous, nothing opened | accepted='${(j:, :)matched}' declined='${(j:, :)declined}' text='${snippet}'"; return 1 ;;
  esac
}
