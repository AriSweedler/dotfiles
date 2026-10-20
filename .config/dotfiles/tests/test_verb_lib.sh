#!/usr/bin/env bash
# lib/verb.zsh, lib/edit.zsh, lib/plan.zsh: a declared verb's help and parser, one edit session,
# one plan file — the three shapes every verb's --help and --edit are built from.
set -u
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

world_new

# zrun [VAR=value…] -- CODE: the kernel sourced in the hermetic env, then CODE; OUT, ERR, RC.
zrun() {
  local -a extra=()
  while [[ "$1" != -- ]]; do extra+=("$1"); shift; done
  shift
  hermetic_env
  RC=0
  env -i "${HERMETIC_ENV[@]}" "${extra[@]}" "${FIX}/tools/zsh" -c \
    'for f in "$1"/*.zsh(N); do source "${f}"; done; c_grey="" c_rst="" c_bold="" DF=dotfiles; eval "$2"' _ "${ORIG_CONFIG_DIR}/dotfiles/lib" "$1" \
    > "${FIX}/z.out" 2> "${FIX}/z.err" || RC=$?
  OUT="$(cat "${FIX}/z.out")"
  ERR="$(cat "${FIX}/z.err")"
}

DEMO='verb::define demo "a demo verb"
verb::usage demo "demo [list]" "demo run NAME [--trigger T]"
verb::about demo <<'"'"'X'"'"'
It lives in $(help::tilde "${HOME}/.config/x") and costs \$0.
X
verb::sub demo run '"'"'run one thing now; a description long enough that it has to wrap past the eightieth column'"'"'
verb::flag demo "--trigger T" '"'"'run: the trigger, as \$1'"'"'
verb::flag demo "--dry-run|-n" "print what would change"
verb::flag demo "--file [FILE]" "an optional value"
verb::flag demo "--a-very-long-flag" "too wide for the column"
verb::edit demo demo_edit "NAME [--new]" "a thing as a checked draft"
verb::env demo ARI_X "a variable" '"'"'$(help::tilde "${HOME}/x")'"'"'
typeset -A opts; typeset -a args'

# ── verb: help from the declaration ──
zrun -- "${DEMO}; verb::help demo"
assert_eq "help: exit 0" 0 "${RC}"
assert_eq "help: line 1 is the description" "a demo verb" "${OUT%%$'\n'*}"
assert_contains "help: Usage lines, entrypoint first" "${OUT}" $'Usage\n  dotfiles demo [list]\n  dotfiles demo run NAME [--trigger T]\n  dotfiles demo edit NAME [--new]'
assert_contains "help: prose expanded at print time, \\\$ literal" "${OUT}" "  It lives in ~/.config/x and costs \$0."
assert_contains "help: a long row wraps with a hanging indent" "${OUT}" $'  run   run one thing now; a description long enough that it has to wrap past\n        the eightieth column'
assert_contains "help: the edit subcommand row" "${OUT}" "  edit  a thing as a checked draft (also: demo --edit)"
assert_contains "help: a flag and its alias, the column as wide as the widest flag" "${OUT}" "  --dry-run|-n   print what would change"
assert_contains "help: a literal \$1" "${OUT}" "run: the trigger, as \$1"
assert_contains "help: a flag wider than 14 has its description on the next line" "${OUT}" $'  --a-very-long-flag\n                 too wide for the column'
assert_contains "help: --edit comes with verb::edit" "${OUT}" "  --edit         edit: the same as the edit subcommand"
assert_contains "help: Env, default expanded" "${OUT}" $'  ARI_X\n      a variable (default ~/x)'
assert_eq "help: no line wider than 80" "" "$(printf '%s\n' "${OUT}" | awk 'length($0) > 80')"

zrun -- 'verb::define bare "a bare verb"; verb::usage bare "bare"; verb::define other "o"; verb::section other T <<< "x"; verb::help bare; typeset -A opts; typeset -a args; verb::parse bare x; print -r -- "args=${args}"'
assert_eq "a verb with only a description and usage: help and parse under set -u" $'a bare verb\n\nUsage\n  dotfiles bare\nargs=x' "${OUT}"

# ── verb: the parser accepts exactly the declared flags ──
zrun -- "${DEMO}; verb::parse demo run a --trigger=unlock -n --file b c -- --raw; for k in \${(ok)opts}; do print -rn -- \"\${k} \${opts[\${k}]} \"; done; print -r -- \"|\${args}\""
assert_eq "parse: values, aliases under the first spelling, positionals in order, -- ends flags" \
  "--dry-run 1 --file b --trigger unlock |run a c --raw" "${OUT}"
zrun -- "${DEMO}; verb::parse demo --bogus"
assert_eq "parse: an undeclared flag is a usage error" 64 "${RC}"
assert_contains "parse: names it" "${ERR}" "demo: unknown flag | flag='--bogus'"
zrun -- "${DEMO}; verb::parse demo --dry-run=1"
assert_eq "parse: a value on a flag without one" 64 "${RC}"
zrun -- "${DEMO}; verb::parse demo --trigger"
assert_eq "parse: a missing value" 64 "${RC}"
zrun -- "${DEMO}; verb::parse demo --file; print -r -- \"\${opts[--file]}\""
assert_eq "parse: an optional value left out is 1" "1" "${OUT}"
zrun -- "${DEMO}; verb::parse demo --help; print -r -- \"\${opts[--help]}\""
assert_eq "parse: --help is declared for every verb" "1" "${OUT}"

# ── verb: --for scopes a flag to its subcommands; a declared --edit row replaces the generated one ──
SCOPED='verb::define sc "scoped"; verb::usage sc "sc decree|triage"
verb::flag sc "--reason TEXT" "decree: why" --for "decree undecree"
verb::flag sc "--edit [FILE]" "triage: a plan file"
verb::edit sc sc_edit "" "edit it"
typeset -A opts; typeset -a args'
zrun -- "${SCOPED}; verb::parse sc decree --reason because; print -r -- \"\${opts[--reason]}\""
assert_eq "--for: taken after its subcommand" "because" "${OUT}"
zrun -- "${SCOPED}; verb::parse sc triage --reason because"
assert_eq "--for: refused after another" 64 "${RC}"
assert_contains "--for: says which it goes with" "${ERR}" "sc triage: --reason goes with sc decree|undecree only"
zrun -- "${SCOPED}; verb::parse sc triage --edit plan.txt; print -r -- \"\${opts[--edit]}\""
assert_eq "a declared --edit takes its value" "plan.txt" "${OUT}"
zrun -- "${SCOPED}; verb::help sc"
assert_contains "a declared --edit row is the one shown" "${OUT}" "--edit [FILE]  triage: a plan file"
assert_not_contains "and the generated one is not" "${OUT}" "edit: the same as the edit subcommand"

# ── verb::edit --form writes the Usage line out; a blank prose line prints empty ──
zrun -- 'verb::define fw "f"; verb::usage fw "fw ARGS"; verb::about fw <<< $'"'"'one\n\ntwo'"'"'; verb::edit fw fw_edit "" "edit" --form "--local fw --edit" --flag-only; verb::help fw; print -r -- "flag-only=${VERB_EDIT_FLAG_ONLY[fw]}"'
assert_contains "--form: the Usage line as written" "${OUT}" "  dotfiles --local fw --edit"
assert_not_contains "--form: no generated one" "${OUT}" "dotfiles fw edit"
assert_contains "a blank prose line has no trailing spaces" "${OUT}" $'  one\n\n  two'
assert_contains "--flag-only is recorded" "${OUT}" "flag-only=1"

zrun -- 'verb::define lw "l"; verb::usage lw "lw edit NAME [--new] [--local|--global] [--dep] [--no-commit] [--no-push] [--more]"; verb::help lw'
assert_contains "a Usage form over 80 wraps under the words after the verb" "${OUT}" $'  dotfiles lw edit NAME [--new] [--local|--global] [--dep] [--no-commit]\n              [--no-push] [--more]'

# ── the help rule for a declared verb (cmd/help.zsh's help::declared_gap) ──
HELP_RULE="source '${ORIG_CONFIG_DIR}/dotfiles/cmd/help.zsh'"
cat > "${FIX}/good.zsh" <<'X'
verb::define good 'a whole declaration'
verb::usage good 'good [--x]'
verb::flag good '--x' 'what x does'
verb::edit good --none 'good has nothing to edit'
cmd_good() { local -A opts; local -a args; verb::parse good "$@"; }
X
cat > "${FIX}/bad.zsh" <<'X'
verb::define bad ''
verb::flag bad '--y' ''
verb::sub bad run ''
cmd_bad() {
  case "$1" in
    --hand) : ;;
  esac
}
X
zrun -- "${HELP_RULE}; source '${FIX}/good.zsh'; help::declared_gap good '${FIX}/good.zsh'; print -r -- \"[\${REPLY}]\""
assert_eq "declared rule: a whole declaration passes" "[]" "${OUT}"
zrun -- "${HELP_RULE}; source '${FIX}/bad.zsh'; help::declared_gap bad '${FIX}/bad.zsh'; print -r -- \"\${REPLY}\""
assert_contains "declared rule: no description" "${OUT}" "no description (verb::define bad"
assert_contains "declared rule: no Usage form" "${OUT}" "no Usage form"
assert_contains "declared rule: a flag without a description" "${OUT}" "'--y' has no description"
assert_contains "declared rule: a subcommand without one" "${OUT}" "'run' has no description"
assert_contains "declared rule: no edit and no reason for none" "${OUT}" "no edit (verb::edit bad HANDLER"
assert_contains "declared rule: a flag parsed by hand" "${OUT}" "parses flags outside verb::parse: --hand"
zrun -- "${HELP_RULE}; help::is_declared '${FIX}/good.zsh' good && print yes; help::is_declared '${FIX}/good.zsh' other || print no"
assert_eq "is_declared: by its verb::define line" $'yes\nno' "${OUT}"

# ── edit: one session ──
EDITORS="${FIX}/editors"
mkdir -p "${EDITORS}"
editor() { printf '#!/bin/sh\n%s\n' "$2" > "${EDITORS}/$1"; chmod +x "${EDITORS}/$1"; }
editor noop ':'
editor fails 'exit 3'
editor bad 'printf "bad\n" > "$1"'
editor good 'printf "good\n" > "$1"'
editor args 'printf "%s\n" "$@" > "'"${FIX}"'/argv"'
CHECK='good_only() { [[ "$(<"$1")" == good ]] || { print -u2 "only good will do"; return 1; }; }'
printf 'start\n' > "${FIX}/f.txt"
zrun EDITOR="${EDITORS}/noop" -- "${CHECK}; edit::session '${FIX}/f.txt' --check good_only; print rc=\$?"
assert_eq "session: unchanged is 2" "rc=2" "${OUT}"
zrun EDITOR="${EDITORS}/fails" -- "${CHECK}; edit::session '${FIX}/f.txt' --check good_only --resume 'dotfiles demo edit x'; print rc=\$?"
assert_eq "session: the editor failing is 1" "rc=1" "${OUT}"
assert_contains "session: and names the resume" "${ERR}" "fix='dotfiles demo edit x'"
zrun EDITOR="${EDITORS}/bad" -- "${CHECK}; edit::session '${FIX}/f.txt' --check good_only --resume 'dotfiles demo edit x' --what x; print rc=\$?"
assert_eq "session: a failing check without a terminal is 1" "rc=1" "${OUT}"
assert_contains "session: the check's problem is shown" "${ERR}" "only good will do"
assert_contains "session: the file kept and the resume named" "${ERR}" "x not used; fix the problems above, then | file='${FIX}/f.txt' fix='dotfiles demo edit x'"
assert_eq "session: the bad file is kept as saved" "bad" "$(cat "${FIX}/f.txt")"
zrun EDITOR="${EDITORS}/good" -- "${CHECK}; edit::session '${FIX}/f.txt' --check good_only; print rc=\$?"
assert_eq "session: a passing check is 0" "rc=0" "${OUT}"
zrun EDITOR="${EDITORS}/args" -- "edit::open --line 7 --readonly -- '${FIX}/f.txt'"
assert_eq "open: a non-vi editor gets neither +N nor -R" "${FIX}/f.txt" "$(cat "${FIX}/argv")"
ln -sf "${EDITORS}/args" "${EDITORS}/nvim"
zrun EDITOR="${EDITORS}/nvim" -- "edit::open --line 7 --readonly -- '${FIX}/f.txt'"
assert_eq "open: nvim gets -R and +N" "-R|+7|${FIX}/f.txt" "$(awk '{ printf "%s%s", (NR > 1 ? "|" : ""), $0 }' "${FIX}/argv")"
zrun EDITOR="no-such-editor-here" -- "edit::editor; print -r -- \"\${reply}\""
assert_eq "editor: a missing one falls back to vi" "vi" "${OUT}"

# ── edit: drafts ──
printf 'live\n' > "${FIX}/live.sh"; chmod 755 "${FIX}/live.sh"
zrun -- "edit::draft '${FIX}/live.sh' '${FIX}/drafts'; print -r -- \"\${REPLY}\""
DRAFT="${OUT}"
assert_eq "draft: a copy of the live file" "live" "$(cat "${DRAFT}")"
printf 'edited\n' > "${DRAFT}"
zrun -- "edit::draft '${FIX}/live.sh' '${FIX}/drafts'; print -r -- \"\${EDIT_RESUMED}\""
assert_eq "draft: a kept draft is resumed" "1" "${OUT}"
zrun -- "edit::install '${DRAFT}' '${FIX}/live.sh'"
assert_eq "install: in place" "edited" "$(cat "${FIX}/live.sh")"
assert_eq "install: the live file's mode kept" 1 "$([[ -x "${FIX}/live.sh" ]] && echo 1 || echo 0)"
assert_no_file "install: the draft is gone" "${DRAFT}"

# ── plan: one shape ──
PLAN='plan::define demo --actions "global add|local add|delete|skip" --default skip --note "global add|local add" --danger delete --item kind:name
known() { [[ "$1" == (formula|cask):* ]] || { print "not an item here"; return 1; }; }
typeset -a reply'
zrun -- "${PLAN}; { plan::header demo 'Two things to settle.'; plan::line skip formula:gh; plan::line 'global add' cask:x why; plan::comment 'a reference'; }"
assert_contains "plan: line 1 is machine-readable" "${OUT%%$'\n'*}" "# dotfiles-plan: demo · actions: global add | local add | delete | skip · danger: delete · note: global add|local add"
assert_contains "plan: a line, its note" "${OUT}" "global add      cask:x  # why"
printf '%s\n' '# dotfiles-plan: demo' 'skip  formula:a' 'global add  cask:b  # needed' 'local add formula:c' 'nope formula:d' 'delete  tap:e' 'delete  formula:a' 'skip formula:f extra' '' 'delete cask:g  # gone' > "${FIX}/p.plan"
zrun -- "${PLAN}; plan::parse demo '${FIX}/p.plan' known; print rc=\$?; print -rl -- \"\${reply[@]}\""
assert_contains "parse: rc 1 when a line is bad" "${OUT}" "rc=1"
assert_contains "parse: a multi-word action, its note, its line number" "${OUT}" $'global add\tcask:b\tneeded\t3'
assert_contains "parse: a note-required action without one" "${ERR}" "line 4: 'local add' needs a note"
assert_contains "parse: an unknown action" "${ERR}" "line 5: unknown action; use global add, local add, delete, skip"
assert_contains "parse: the item check" "${ERR}" "line 6: not an item here | item='tap:e'"
assert_contains "parse: an item twice" "${ERR}" "line 7: listed twice | item='formula:a'"
assert_contains "parse: an extra word" "${ERR}" "line 8: expected one kind:name after 'skip'"
assert_contains "parse: a good line after the bad ones" "${OUT}" $'delete\tcask:g\tgone\t10'
# ── plan::edit: --resume reaches the session, --plan-check sees the whole plan ──
WHOLE='no_two_deletes() { local -i n=0; local l; for l in "${PLAN_LINES[@]}"; do [[ "${l%%$'"'"'\t'"'"'*}" == delete ]] && (( ++n )); done; (( n < 2 )) || { print -u2 "line 0: at most one delete"; return 1; }; }'
printf '%s\n' '# dotfiles-plan: demo' 'delete  cask:a  # x' 'delete  cask:b  # y' > "${FIX}/w.plan"
zrun EDITOR="${EDITORS}/noop" -- "${PLAN}; ${WHOLE}; plan::edit demo '${FIX}/w.plan' known --plan-check no_two_deletes --changed --resume 'dotfiles demo --edit F'; print rc=\$?"
assert_eq "plan-check: a rule across lines fails the plan" "rc=1" "${OUT}"
assert_contains "plan-check: its problem is shown" "${ERR}" "at most one delete"
assert_contains "--resume: the resume line reaches the session" "${ERR}" "fix='dotfiles demo --edit F'"
printf '%s\n' '# dotfiles-plan: demo' 'delete  cask:a  # x' > "${FIX}/w.plan"
zrun EDITOR="${EDITORS}/noop" -- "${PLAN}; ${WHOLE}; plan::edit demo '${FIX}/w.plan' known --plan-check no_two_deletes --changed; print rc=\$? unchanged=\${EDIT_UNCHANGED}"
assert_eq "a plan run as written: checked, passes, and EDIT_UNCHANGED says it was not edited" "rc=0 unchanged=1" "${OUT}"
zrun -- "PLAN_ITEM_WIDTH=10; plan::line apply ab why; plan::line apply abcdefgh why2"
assert_eq "PLAN_ITEM_WIDTH: notes line up" $'apply           ab          # why\napply           abcdefgh    # why2' "${OUT}"
report
