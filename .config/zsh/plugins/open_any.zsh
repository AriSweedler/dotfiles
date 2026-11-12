# open_any — open the clipboard (or $1) with the one opener whose --check accepts it.
#
# Openers are the open-* executables a switch lists in ~/.config/open-any/openers, one
# `name<TAB>path` line each, from both bin tiers (~/.config/dotfiles/nix/open-any.nix).
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
#      `source <plugin>; open_<kind> "$@"`. open-any sources the open_*.zsh plugins of the zsh
#      plugin list (~/.config/zsh/plugins.list.zsh) and probes the function in-process (a zsh
#      start per probe costs more than the whole dispatch); with no list it runs the scripts.
# A new opener joins the list at the next dotfiles switch (a local one: its flake's
# dotfiles.openAny.openers).
# `open-any --verify` checks 2 and 5 against every opener found; run it after adding one.
#
# Env: OPEN_ANY_LIST and OPEN_ANY_PLUGIN_LIST name another openers list and plugin list (tests).

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

function open_any::list() {
  print -r -- "${OPEN_ANY_LIST:-${XDG_CONFIG_HOME:-${HOME}/.config}/open-any/openers}"
}

# Output: one opener name per line, in the list's order (by name). An entry whose file is not
# executable is skipped; open-any is not an opener.
function open_any::openers() {
  local list name file
  list="$(open_any::list)"
  [[ -r "${list}" ]] || return 0
  while IFS=$'\t' read -r name file; do
    [[ -n "${name}" && "${name}" != open-any && -x "${file}" ]] && print -r -- "${name}"
  done < "${list}"
  return 0
}

# Input: opener name. Output: its path from the list, so an opener off PATH works.
function open_any::path_of() {
  local list name file
  list="$(open_any::list)"
  [[ -r "${list}" ]] || return 1
  while IFS=$'\t' read -r name file; do
    if [[ "${name}" == "${1}" ]]; then
      print -r -- "${file}"
      return 0
    fi
  done < "${list}"
  return 1
}

# Sources the opener plugins of the zsh plugin list (its open_*.zsh lines) so the open_<kind>
# functions exist in this shell. Idempotent enough: plugins are function definitions.
function open_any::load_plugins() {
  local list="${OPEN_ANY_PLUGIN_LIST:-${ZDOTDIR:-${HOME}/.config/zsh}/plugins.list.zsh}" line f
  [[ -r "${list}" ]] || return 0
  while IFS= read -r line; do
    [[ "${line}" == source_file\ * ]] || continue
    f="${(Q)line#source_file }"
    [[ "${f:t}" == open_*.zsh && "${f:t}" != open_any.zsh && -r "${f}" ]] && source "${f}"
  done < "${list}"
  return 0
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
    log::warn "No openers listed, nothing opened | list='$(open_any::list)'"
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
