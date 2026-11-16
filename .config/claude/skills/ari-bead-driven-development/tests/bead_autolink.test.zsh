#!/usr/bin/env zsh
# Proves bead_autolink (the MessageDisplay hook) against a stub bd and a stub linker under mktemp:
# every mention bd knows (a bare id, a `[id]` shortcut reference, an inline link to its short URL) is
# shown as its card link and its definition line is removed, with the blank line before a removed
# trailing block; a card link, a link to another URL, a full reference, a non-bead definition, an id
# in inline code, in a URL, in a code fence (also one that spans two batches) or unknown to bd is
# left as written, an unknown id's definition line included; and a batch with nothing to change
# prints nothing. Never reads Ari's tracker or his beads.conf.
# Run: zsh $HOME/.claude/skills/ari-bead-driven-development/tests/bead_autolink.test.zsh
set -euo pipefail

readonly SCRIPT_DIR="${0:A:h}"
readonly SKILLS_DIR="${HOME}/.claude/skills"
readonly LIB_LOGGING="${SKILLS_DIR}/ari-skill-shellscripts/lib/logging.zsh"
if [[ ! -r "${LIB_LOGGING}" ]]; then
  print -u2 "[ERROR] missing shared logging lib | path='${LIB_LOGGING}'"
  exit 1
fi
source "${LIB_LOGGING}"

readonly AUTOLINK="${SCRIPT_DIR:h}/bin/bead_autolink.zsh"
readonly WORK_DIR="$(mktemp -d)"
trap 'rm -rf "${WORK_DIR}"' EXIT

typeset -i passed=0 failed=0

#######################################
# Write the stubs: a bd that knows beads-o27 and beads-xy9.2 only, and a linker that prints, per
# --bead, the definition line [ID]: https://x.example/p/beads?bead=ID, or [ID]: card://ID with --card.
#######################################
write_stubs() {
  cat > "${WORK_DIR}/bd" <<'STUB'
#!/usr/bin/env zsh
print -r -- "$*" >> "${0:A:h}/bd.calls"
typeset -a rows
for arg in "$@"; do
  case "${arg}" in
    beads-o27) rows+=('{"id":"beads-o27","title":"Graph view: toggle","status":"open","priority":2}') ;;
    beads-xy9.2) rows+=('{"id":"beads-xy9.2","title":"Doctor: check","status":"closed","priority":1}') ;;
  esac
done
(( ${#rows} )) || { print -u2 "Issue not found"; exit 1; }
print -r -- "[${(j:,:)rows}]"
STUB
  cat > "${WORK_DIR}/linker.zsh" <<'STUB'
#!/usr/bin/env zsh
typeset -a ids
typeset card=false
while (( $# )); do
  [[ "${1}" == --card ]] && card=true
  [[ "${1}" == --bead ]] && ids+=("${2}")
  shift
done
for id in "${ids[@]}"; do
  if [[ "${card}" == true ]]; then
    print -r -- "[${id}]: card://${id}"
  else
    print -r -- "[${id}]: https://x.example/p/beads?bead=${id}"
  fi
done
STUB
  chmod +x "${WORK_DIR}/bd"
}

#######################################
# Run the hook on one batch and print the text it would display (the delta when it changes nothing).
# Arguments: $1 delta, $2 message id, $3 final (true|false)
#######################################
displayed() {
  local delta="${1}" message_id="${2}" final="${3}" payload output
  payload="$(jq -n --arg delta "${delta}" --arg id "${message_id}" --argjson final "${final}" \
    '{hook_event_name: "MessageDisplay", message_id: $id, index: 0, final: $final, delta: $delta}')"
  output="$(print -r -- "${payload}" | zsh "${AUTOLINK}" --workspace "beads=${WORK_DIR}" \
    --state-dir "${WORK_DIR}/state" --linker "${WORK_DIR}/linker.zsh" --bd "${WORK_DIR}/bd")"
  if [[ -z "${output}" ]]; then
    print -rn -- "${delta}"
    return 0
  fi
  print -r -- "${output}" | jq -rj '.hookSpecificOutput.displayContent'
}

#######################################
# Record one check: pass when the two strings are equal.
# Arguments: $1 test name, $2 wanted, $3 got
#######################################
expect_eq() {
  local name="${1}" want="${2}" got="${3}"
  if [[ "${want}" == "${got}" ]]; then
    passed=$(( passed + 1 ))
    log::info "ok | test='${name}'"
    return 0
  fi
  failed=$(( failed + 1 ))
  log::err "FAIL | test='${name}' want='${want}' got='${got}'"
}

main() {
  write_stubs

  expect_eq "a bare id is linked" \
    "Closed [beads-o27](card://beads-o27)." \
    "$(displayed "Closed beads-o27." m1 true)"
  expect_eq "a child id keeps its suffix, and a sentence's period stays outside" \
    "See [beads-xy9.2](card://beads-xy9.2). Done" \
    "$(displayed "See beads-xy9.2. Done" m2 true)"
  expect_eq "an inline link to its short URL is shown as the card link" \
    "[the toggle](card://beads-o27) is open" \
    "$(displayed "[the toggle](https://x.example/p/beads?bead=beads-o27) is open" m3 true)"
  expect_eq "a card link and a link to another URL are left alone" \
    "[beads-o27](https://x.example/p/beads?bead=beads-o27&tmux-tooltip=show&title=x) [beads-o27](https://x.example/p?bead=beads-o27)" \
    "$(displayed "[beads-o27](https://x.example/p/beads?bead=beads-o27&tmux-tooltip=show&title=x) [beads-o27](https://x.example/p?bead=beads-o27)" m14 true)"
  expect_eq "references become card links; their trailing definition block and its blank line are removed" \
    'Filed [beads-o27](card://beads-o27); see [Graph][beads-xy9.2].' \
    "$(displayed $'Filed [beads-o27]; see [Graph][beads-xy9.2].\n\n[beads-o27]: https://x.example/p/beads?bead=beads-o27\n[beads-xy9.2]: https://x.example/p/beads?bead=beads-xy9.2' m11 true)"
  expect_eq "a non-bead definition and an unknown id's definition stay; the unknown reference is left as written" \
    $'[beads-o27](card://beads-o27) and [beads-zzz], see [docs].\n\n[docs]: https://example.com/docs\n[beads-zzz]: https://x.example/p/beads?bead=beads-zzz' \
    "$(displayed $'[beads-o27] and [beads-zzz], see [docs].\n\n[beads-o27]: https://x.example/p/beads?bead=beads-o27\n[docs]: https://example.com/docs\n[beads-zzz]: https://x.example/p/beads?bead=beads-zzz' m15 true)"
  expect_eq "a definition line inside a fence and an id in inline code are left alone" \
    $'```\n[beads-o27]: https://x.example/p/beads?bead=beads-o27\n```\nrun `bd show beads-o27`' \
    "$(displayed $'```\n[beads-o27]: https://x.example/p/beads?bead=beads-o27\n```\nrun `bd show beads-o27`' m16 true)"
  expect_eq "a reference with no definition still opens on screen, beside a bare id" \
    "[beads-o27](card://beads-o27) blocks [beads-xy9.2](card://beads-xy9.2)" \
    "$(displayed "[beads-o27] blocks beads-xy9.2" m12 true)"
  expect_eq "an id inside other brackets is linked; an unknown reference and a labelled one are left alone" \
    "(see [blocked by [beads-o27](card://beads-o27)]) [beads-zzz] [beads-o27][x]" \
    "$(displayed "(see [blocked by beads-o27]) [beads-zzz] [beads-o27][x]" m13 true)"
  expect_eq "inline code and a bare URL are left alone" \
    'run `bd show beads-o27` or open https://x.example/beads-o27 now' \
    "$(displayed 'run `bd show beads-o27` or open https://x.example/beads-o27 now' m4 true)"
  expect_eq "an id bd does not know is left alone" \
    "beads-zzz and beads-related work" \
    "$(displayed "beads-zzz and beads-related work" m5 true)"
  expect_eq "a path and a longer word are not ids" \
    "~/beads-o27 and sub-beads-o27 and beads-o27-old" \
    "$(displayed "~/beads-o27 and sub-beads-o27 and beads-o27-old" m6 true)"
  expect_eq "a code fence is left alone, the prose around it is linked" \
    $'[beads-o27](card://beads-o27)\n```\nbd close beads-o27\n```\n[beads-o27](card://beads-o27) end' \
    "$(displayed $'beads-o27\n```\nbd close beads-o27\n```\nbeads-o27 end' m7 true)"
  displayed $'```zsh\n' m8 false >/dev/null
  expect_eq "a fence opened in one batch still covers the next batch" \
    "bd close beads-o27" \
    "$(displayed $'bd close beads-o27\n' m8 false)"
  expect_eq "after that fence closes, prose is linked again" \
    $'```\n[beads-o27](card://beads-o27) end' \
    "$(displayed $'```\nbeads-o27 end' m8 true)"

  : > "${WORK_DIR}/bd.calls"
  displayed "beads-o27 again" m9 true >/dev/null
  expect_eq "a link minted a moment ago comes from the cache, not bd" "" "$(<"${WORK_DIR}/bd.calls")"
  displayed "no ids in this line" m10 true >/dev/null
  expect_eq "a batch with no id does not call bd" "" "$(<"${WORK_DIR}/bd.calls")"

  log::info "bead_autolink tests | passed='${passed}' failed='${failed}'"
  (( failed == 0 ))
}

main "$@"
