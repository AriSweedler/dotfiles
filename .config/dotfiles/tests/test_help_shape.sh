#!/usr/bin/env bash
# The help rule over the real tree: every verb's help_VERB and the top-level help have a one-line
# synopsis, a Usage section and every flag their parsers accept, and each renders cleanly; plus
# what the rule counts as a parsed flag (help::parser_flags) and what it calls a gap.
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

# ── the real tree: no gap ──
zrule 'help::verb_names; for v in "${reply[@]}"; do help::verb_gap "${v}"; [[ -z "${REPLY}" ]] || print -r -- "${v}: ${REPLY}"; done
       help::top_gap; [[ -z "${REPLY}" ]] || print -r -- "dotfiles: ${REPLY}"'
assert_eq "the rule ran" 0 "${RC}"
assert_eq "every verb's help and the top-level help pass the rule" "" "${OUT}${ERR}"

zrule 'help::verb_names; print -rl -- "${reply[@]}"'
VERBS="${OUT}"
assert_contains "the verbs are found by file" "${VERBS}" "help"
zrule 'verbs'
assert_eq "the rule's verbs are the dispatcher's" "$(sort <<< "${OUT}")" "$(sort <<< "${VERBS}")"

# Each help renders under the entrypoint, nothing on stderr, line 1 a synopsis, then a blank line.
while IFS= read -r verb; do
  # `help VERB`, not `VERB --help`: git hands its --help to git.
  nm help "${verb}"
  if [[ "${RC}" == 0 && -z "${ERR}" ]]; then pass "${verb} --help renders"
  else fail "${verb} --help renders" "rc=${RC} err=${ERR}"; fi
  line1="${OUT%%$'\n'*}"; rest="${OUT#*$'\n'}"; line2="${rest%%$'\n'*}"
  if [[ -n "${line1}" && "${line1}" != " "* && -z "${line2}" ]]; then pass "${verb} --help: line 1 is a synopsis"
  else fail "${verb} --help: line 1 is a synopsis" "${line1} / ${line2}"; fi
  assert_contains "${verb} --help: a Usage section" "${OUT}" $'\nUsage\n'
done <<< "${VERBS}"
nm --help
assert_eq "the top-level help renders" "0:" "${RC}:${ERR}"
assert_contains "the top-level help names -v" "${OUT}" "-v"
assert_contains "the top-level help names --local" "${OUT}" "--local"
assert_contains "the top-level help names --dir" "${OUT}" "--dir"

# ── what counts as a parsed flag ──
SAMPLE="${FIX}/sample.zsh"
cat > "${SAMPLE}" <<'EOF'
help_sample() {
  cat <<HELP
  --in-heredoc)  help text is not a parser
HELP
}
cmd_sample() {
  zparseopts -D -F -K -- -alpha=a -beta:=b v=verbose || usage_error "bad"
  while (( $# )); do case "${1}" in
    -h|--help) ;;
    --gamma) ;;
    --delta|--epsilon) ;;
    edit|--edit) ;;
    --zeta|-z) ;;
    -k) ;;
    -*) ;;
  esac; shift; done
  decide+=(--not-an-arm)
  [[ "${1}" == (--pattern|x) ]]
}
EOF
zrule 'help::parser_flags "$1"; print -r -- "${reply[*]}"' "${SAMPLE}"
assert_eq "parsed flags: zparseopts specs, case arms, alternatives, a short beside a long" \
  "--alpha --beta -v --gamma --delta --epsilon --edit --zeta -z" "${OUT}"
zrule 'help::doc_gap "$1" help_sample "$1"; print -r -- "${REPLY}"' "${SAMPLE}"
assert_eq "a help with no synopsis, no Usage and no flags: every gap" \
  "line 1 is not a one-line synopsis, no Usage section, flags not in it: --alpha --beta -v --gamma --delta --epsilon --edit --zeta -z" "${OUT}"
zrule 'help::doc_gap "$1" help_nobody "$1"; print -r -- "${REPLY}"' "${SAMPLE}"
assert_eq "no help function" "no help_nobody()" "${OUT}"
# A flag is named as a word: --edit inside --edit-all does not count.
cat > "${SAMPLE}" <<'EOF'
help_sample() {
  cat <<EOD
one line

${c_bold}Usage${c_rst}
  ${DF} sample [--edit-all] [--gamma]
EOD
}
cmd_sample() {
  case "${1}" in
    --edit) ;;
    --gamma) ;;
  esac
}
EOF
zrule 'help::doc_gap "$1" help_sample "$1"; print -r -- "${REPLY}"' "${SAMPLE}"
assert_eq "a flag counts only as a whole word" "flags not in it: --edit" "${OUT}"

report
