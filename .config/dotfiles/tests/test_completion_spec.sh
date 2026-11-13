#!/usr/bin/env bash
# The declarations as data, over the real tree: the linter (lib/spec.zsh) has no finding and names each kind of gap in a broken declaration; _dotfiles is what the declarations compile to, and it offers every verb, subcommand, flag and value kind they declare.
set -u
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

world_new

# zrule SCRIPT ARGS...: SCRIPT in a zsh with the kernel and every verb loaded, as bin/dotfiles has.
zrule() {
  local script="$1"; shift
  hermetic_env
  RC=0
  env -i "${HERMETIC_ENV[@]}" "ARI_DOTFILES_LIB=${ORIG_CONFIG_DIR}/dotfiles/lib" "${FIX}/tools/zsh" -f -c '
    for f in "${ARI_DOTFILES_LIB}"/*.zsh(N) "${ARI_DOTFILES_LIB:h}"/cmd/*.zsh(N); do source "${f}"; done
    '"${script}" zrule "$@" > "${FIX}/z.out" 2> "${FIX}/z.err" || RC=$?
  OUT="$(cat "${FIX}/z.out")"
  ERR="$(cat "${FIX}/z.err")"
}

# ── the linter: the real tree is clean ──
nm completion lint
assert_eq "completion lint: exit 0 on the real tree" 0 "${RC}"
assert_eq "completion lint: no finding" "" "${OUT}${ERR}"
zrule 'spec::lint; print -r -- "${#reply}"; (( ${#NODES} > 20 && ${#FLAGS} > 20 && ${#KINDS} > 5 )) && print loaded'
assert_eq "the linter read the whole registry" $'0\nloaded' "${OUT}"

# ── the linter: each kind of gap is a finding ──
BROKEN='verb::define bad "a broken verb"; verb::usage bad "bad THING [--ghost]"
verb::flag bad "--only NOPE" "a value that names no kind"
verb::sub bad "deep sub" "a subcommand whose parent is not declared"
verb::arg bad --for nowhere "STEP.." "GROUP"
verb::flag bad "--scoped" "scoped to nothing declared" --for "missing"
kind::define ORPHAN "a kind nothing names" --free
kind::define NOLISTER "a kind whose lister is not a function" --lister no_such_function
verb::arg bad "NOLISTER"
GLOBAL_FLAG_DESC[--phantom]="a flag main() does not parse"
spec::lint; print -rl -- "${reply[@]}"'
zrule "${BROKEN}"
assert_contains "a flag value that names no kind" "${OUT}" "bad --only: its value 'NOPE' names no kind"
assert_contains "an unscoped flag in a verb with subcommands" "${OUT}" "bad --only: no --for"
assert_contains "a --for that names an undeclared node" "${OUT}" "bad --scoped: --for names 'bad missing', which is not declared"
assert_contains "a subcommand whose parent is not declared" "${OUT}" "bad deep sub: 'bad deep' is not declared"
assert_contains "a positional on an undeclared node" "${OUT}" "bad nowhere: verb::arg on a node that is not declared"
assert_contains "a repeating positional that is not the last" "${OUT}" "bad nowhere: 'STEP..' repeats but is not the last positional"
assert_contains "a Usage flag nothing declares" "${OUT}" "has --ghost, which is not a declared flag"
assert_contains "a Usage word that is no kind of the verb" "${OUT}" "has THING, which is no kind"
assert_contains "a kind nothing names" "${OUT}" "kind ORPHAN: no flag or position names it"
assert_contains "a lister that is not a function" "${OUT}" "kind NOLISTER: its lister is not a function"
assert_contains "a pre-verb flag main() does not parse" "${OUT}" "--phantom: GLOBAL_FLAG_DESC declares it and main()"
nm completion write --dry-run
assert_eq "completion takes no flag it does not declare" 64 "${RC}"

# ── the compiler: the kept _dotfiles is what the declarations compile to ──
KEPT="${ORIG_CONFIG_DIR}/zsh/completions/_dotfiles"
nm completion
assert_eq "completion: exit 0" 0 "${RC}"
if [[ "${OUT}" == "$(cat "${KEPT}")" ]]; then pass "the kept _dotfiles is the compiler's output"
else fail "the kept _dotfiles is the compiler's output" "stale: run 'dotfiles completion write' and commit ${KEPT}"; fi
printf '%s\n' "${OUT}" > "${FIX}/_dotfiles"
if "${FIX}/tools/zsh" -n "${FIX}/_dotfiles" 2> "${FIX}/n.err"; then pass "_dotfiles parses"; else fail "_dotfiles parses" "$(cat "${FIX}/n.err")"; fi

# ── the compiled function, driven: zsh's completion builtins are stubs that record what is offered ──
DRIVE='
typeset -ga OFFERED=()
_describe() { local name="${@[-1]}"; local -a rows=("${(@P)name}"); OFFERED+=("${(@)rows%%:*}"); (( ${#rows} )); }
_files() { OFFERED+=("<files>"); }
_message() { OFFERED+=("<${1%%:*}>"); return 1; }
_normal() { OFFERED+=("<${words[*]}>"); }
compset() { [[ "${1}" == -P ]] && PREFIX="${PREFIX##${~2}}"; return 0; }
dotfiles() { main "$@"; }
typeset -a words=(dotfiles); typeset -i CURRENT=1; typeset PREFIX=""
source "${1}" 2>/dev/null
# offer WORD..: OFFERED = what <TAB> gives with the cursor on the last word.
offer() { words=(dotfiles "$@"); CURRENT=${#words}; PREFIX="${words[-1]}"; OFFERED=(); _dotfiles; return 0; }
'
zrule "${DRIVE}"'
local node key spelling parent last
local -a reply nodes
for node in "${NODES[@]}"; do
  [[ -z "${NODE_FLAG_ONLY[${node}]:-}" ]] || continue
  parent="${node% *}"; last="${node##* }"; [[ "${node}" == *" "* ]] || parent=""
  offer ${=parent} ""
  (( ${OFFERED[(Ie)${last}]} )) || print -r -- "not offered: ${node}"
done
for key in "${FLAGS[@]}"; do
  if (( ${+FLAG_NODES[${key}]} )); then nodes=("${(@f)FLAG_NODES[${key}]}"); else nodes=("${key%% *}"); fi
  for node in "${nodes[@]}"; do
    [[ -z "${_dotfiles_delegate[${node}]:-}" ]] || continue
    if [[ "${node}" == *" edit" && -n "${NODE_FLAG_ONLY[${node}]:-}" ]]; then offer ${node%% *} --edit -; else offer ${=node} -; fi
    for spelling in ${=FLAG_SPELLINGS[${key}]}; do
      (( ${OFFERED[(Ie)${spelling}]} )) || print -r -- "flag not offered: ${spelling} at ${node}"
    done
    (( ! ${+FLAG_VALUE[${key}]} )) || { offer ${=node} "${key#* }" ""; (( ${#OFFERED} )) || print -r -- "no value offered: ${key} at ${node}"; }
  done
done
for key in "${(@k)GLOBAL_FLAG_DESC}"; do
  offer -
  for spelling in "${(@s:|:)key}"; do (( ${OFFERED[(Ie)${spelling}]} )) || print -r -- "pre-verb flag not offered: ${spelling}"; done
done
print -r -- "walked ${#NODES} nodes"' "${FIX}/_dotfiles"
assert_eq "driving ran" 0 "${RC}"
assert_contains "every node was walked" "${OUT}" "walked "
assert_eq "every node, every flag at each node that takes it, a value for every flag that takes one" "" "$(grep -v '^walked ' <<< "${OUT}")"

# offered WORDS...: OUT = what the compiled function offers with the cursor on the last word.
offered() { zrule "${DRIVE}"'shift; offer "$@"; print -r -- "${OFFERED[*]}"' "${FIX}/_dotfiles" "$@"; }
offered ""
assert_contains "no verb yet: the verbs" " ${OUT} " " healthcheck "
assert_not_contains "no verb yet: no subcommand" " ${OUT} " " list "
offered jobs run somejob --trigger ""
assert_eq "a flag's value: its kind's fixed words" "unlock load tick manual screenIsUnlocked" "${OUT}"
offered init --group=
assert_eq "--flag=: the same kind" "repo brew tools" "${OUT}"
offered init --only "dotfiles_repo,"
assert_contains "a comma list: the kind again after each comma" " ${OUT} " " machine_name "
offered apply ""
assert_contains "a positional: its kind, from the lister" " ${OUT} " " dotfiles_docs "
offered apply dotfiles_docs ""
assert_contains "a repeating positional: its kind at every position" " ${OUT} " " dotfiles_repo "
offered jobs run -
assert_eq "a flag only at the subcommands that take it" "--trigger --help" "${OUT}"
offered jobs run --trigger manual -
assert_eq "a flag already given is not offered again" "--help" "${OUT}"
offered steps --edit ""
assert_contains "--edit is the edit subcommand: its positional" " ${OUT} " " dotfiles_docs "
offered raycast snippets move somesnippet --to ""
assert_eq "a flag of a two-word subcommand" "shared local" "${OUT}"
offered machine-name ""
assert_eq "a free kind: a message naming it, beside the subcommands" "edit <MACHINE_NAME>" "${OUT}"
offered status edit ""
assert_eq "a files kind" "<files>" "${OUT}"
offered --local git log --on
assert_eq "git: the rest of the line is git's, from its own first word" "<git log --on>" "${OUT}"
offered help ""
assert_contains "the VERB kind lists the verbs" " ${OUT} " " completion "

# ── kinds: the catalog and one kind's values ──
nm kinds
assert_contains "kinds: the catalog names a kind and its source" "${OUT}" "GROUP"
nm kinds GROUP
assert_eq "kinds KIND: its values, one per line" $'repo\nbrew\ntools' "${OUT}"
nm kinds NOPE
assert_eq "kinds: an unknown kind is a usage error" 64 "${RC}"

report
