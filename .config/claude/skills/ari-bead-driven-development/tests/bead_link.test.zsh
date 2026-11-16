#!/usr/bin/env zsh
# Proves bead_link.zsh's definitions against fixture configs under mktemp: a local prefix match is
# defined as its short Scotty page (no card, no tmux-tooltip needed), --card builds the card on that
# page, a workspace with no scotty line gets the tmux-only link with its card, a repeated bead is defined once, a host's beads use only their
# PREFIX@DEFINITION line and never this machine's, a malformed, repeated or local-URL scotty line is
# skipped, and the machine flag is required once.
# Uses the real tmux-tooltip of this checkout (the installed one when the checkout has none); never reads
# or writes Ari's beads.conf.
# Run: zsh $HOME/.claude/skills/ari-bead-driven-development/tests/bead_link.test.zsh
set -euo pipefail

readonly SCRIPT_DIR="${0:A:h}"
readonly SKILLS_DIR="${HOME}/.claude/skills"
readonly LIB_LOGGING="${SKILLS_DIR}/ari-skill-shellscripts/lib/logging.zsh"
if [[ ! -r "${LIB_LOGGING}" ]]; then
  print -u2 "[ERROR] missing shared logging lib | path='${LIB_LOGGING}'"
  exit 1
fi
source "${LIB_LOGGING}"

readonly BEAD_LINK="${SCRIPT_DIR:h}/bin/bead_link.zsh"
# The skill sits at <checkout>/.config/claude/skills/<name>, beside <checkout>/.config/bin.
readonly CHECKOUT_TOOLTIP="${SCRIPT_DIR:h:h:h:h}/bin/tmux-tooltip"
readonly LOCAL_URL="https://scotty.example.com/p/beads"
readonly HOST_URL="https://scotty.example.org/p/beads"

typeset -i passed=0 failed=0

#######################################
# Record one check: pass when the text holds each literal string, in order.
# Arguments: $1 test name, $2 text, then the strings
#######################################
expect_has() {
  local name="${1}" got="${2}" rest="${2}" want
  shift 2
  for want in "$@"; do
    if [[ "${rest}" != *"${want}"* ]]; then
      failed=$(( failed + 1 ))
      log::err "FAIL | test='${name}' want='${want}' got='${got}'"
      return 0
    fi
    rest="${rest#*"${want}"}"
  done
  passed=$(( passed + 1 ))
  log::info "ok | test='${name}'"
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

#######################################
# Record one check: pass when the exit codes are equal.
# Arguments: $1 test name, $2 wanted code, $3 actual code
#######################################
expect_rc() {
  local name="${1}" want="${2}" got="${3}"
  if [[ "${want}" == "${got}" ]]; then
    passed=$(( passed + 1 ))
    log::info "ok | test='${name}'"
    return 0
  fi
  failed=$(( failed + 1 ))
  log::err "FAIL | test='${name}' want_rc='${want}' got_rc='${got}'"
}

#######################################
# Run bead_link.zsh against a fixture config; stdout to $out, stderr to $err.
# Globals: BEAD_LINK, out, err (written)
# Arguments: $1 config file, then bead_link.zsh's arguments
# Returns: bead_link.zsh's exit code
#######################################
link_with() {
  local config="${1}"
  shift
  local rc=0
  local -a tooltip=()
  [[ -r "${CHECKOUT_TOOLTIP}" ]] && tooltip=("BEAD_LINK_TMUX_TOOLTIP=${CHECKOUT_TOOLTIP}")
  env "${tooltip[@]}" BEAD_LINK_CONFIG="${config}" zsh "${BEAD_LINK}" "$@" > "${work}/out" 2> "${work}/err" || rc=$?
  out="$(< "${work}/out")"
  err="$(< "${work}/err")"
  return "${rc}"
}

main() {
  local work out err rc
  work="$(mktemp -d "${TMPDIR:-/tmp}/bead-link.XXXXXX")"
  trap "rm -rf '${work}'" EXIT

  local good="${work}/good.conf"
  cat > "${good}" <<EOF
status open cyan
scotty beads ${LOCAL_URL}
scotty beads@laptop ${HOST_URL}
EOF

  link_with "${good}" --here --bead beads-o27 --title 'Graph view' --status open
  expect_eq "a local prefix match is defined as its short Scotty page, card flags ignored" \
    "[beads-o27]: ${LOCAL_URL}?bead=beads-o27" "${out}"

  link_with "${good}" --here --bead beads-o27 --bead beads-xy9.2 --bead beads-o27
  expect_eq "one definition per distinct bead, in order, with no title needed" \
    "[beads-o27]: ${LOCAL_URL}?bead=beads-o27"$'\n'"[beads-xy9.2]: ${LOCAL_URL}?bead=beads-xy9.2" "${out}"

  rc=0
  env BEAD_LINK_TMUX_TOOLTIP="${work}/no-tmux-tooltip" BEAD_LINK_CONFIG="${good}" \
    zsh "${BEAD_LINK}" --here --bead beads-o27 > "${work}/out" 2> "${work}/err" || rc=$?
  expect_rc "a Scotty definition needs no tmux-tooltip" 0 "${rc}"

  link_with "${good}" --here --bead other-abc --title 'Graph view: a | b' --status open --priority 2
  expect_has "a prefix with no scotty line is defined as the tmux-only link with its card" "${out}" \
    "[other-abc]: tmux-tooltip://show?title=other-abc&text=Graph%20view%3A%20a%20%7C%20b" \
    "field=status%3Dopen&color=cyan" "field=priority%3DP2" \
    "&copy=other-abc%20%7C%20Graph%20view%3A%20a%20%7C%20b"
  local -a out_lines=("${(@f)out}")
  expect_eq "the tmux-only definition is one line" "1" "${#out_lines}"
  rc=0; [[ "${out}" == *"]("* ]] || rc=1
  expect_rc "the tmux-only definition carries no Markdown link around its URL" 1 "${rc}"

  link_with "${good}" --here --bead other-abc --status review --priority 9 --bead beads-o27 --status review
  expect_has "an unknown status or priority is dropped from the card, never the definition" "${out}" \
    "[other-abc]: tmux-tooltip://show?title=other-abc&copy=other-abc" "[beads-o27]: ${LOCAL_URL}?bead=beads-o27"
  expect_has "the dropped card values warn" "${err}" "field='status' value='review'" "field='priority' value='9'"

  link_with "${good}" --here --bead other-abc
  expect_eq "a tmux-only definition with no title copies the id" \
    "[other-abc]: tmux-tooltip://show?title=other-abc&copy=other-abc" "${out}"

  rc=0
  env BEAD_LINK_TMUX_TOOLTIP="${work}/no-tmux-tooltip" BEAD_LINK_CONFIG="${good}" \
    zsh "${BEAD_LINK}" --here --bead other-abc > "${work}/out" 2> "${work}/err" || rc=$?
  expect_rc "a tmux-only definition without tmux-tooltip is refused" 1 "${rc}"
  expect_eq "a refused call prints no definition" "" "$(< "${work}/out")"
  err="$(< "${work}/err")"
  expect_eq "a missing tmux-tooltip is the only error, never a blamed color" "" "${(M)err:#*a color in the config*}"

  link_with "${good}" --here --card --bead beads-o27 --title 'Graph view' --status open --priority 2
  expect_has "--card builds the card on the short Scotty URL" "${out}" \
    "[beads-o27]: ${LOCAL_URL}?bead=beads-o27&tmux-tooltip=show&title=beads-o27&text=Graph%20view" \
    "field=status%3Dopen&color=cyan" "field=priority%3DP2" "&copy=beads-o27%20%7C%20Graph%20view"
  link_with "${good}" --here --card --bead other-abc --title x
  expect_has "--card with no scotty line is the tmux-only link" "${out}" "[other-abc]: tmux-tooltip://show?title=other-abc&text=x"
  rc=0
  env BEAD_LINK_TMUX_TOOLTIP="${work}/no-tmux-tooltip" BEAD_LINK_CONFIG="${good}" \
    zsh "${BEAD_LINK}" --here --card --bead beads-o27 > "${work}/out" 2> "${work}/err" || rc=$?
  expect_rc "--card needs tmux-tooltip" 1 "${rc}"

  link_with "${good}" --host-definition laptop --bead beads-o27
  expect_eq "a host's bead uses its PREFIX@DEFINITION line" "[beads-o27]: ${HOST_URL}?bead=beads-o27" "${out}"

  link_with "${good}" --host-definition co2 --bead beads-o27
  expect_has "a host with no line is tmux only, never this machine's Scotty" "${out}" "[beads-o27]: tmux-tooltip://show?"

  link_with "${good}" --host-definition local --bead beads-o27
  expect_eq "the local definition links as --here" "[beads-o27]: ${LOCAL_URL}?bead=beads-o27" "${out}"

  rc=0; link_with "${good}" --bead beads-o27 || rc=$?
  expect_rc "no machine flag is refused" 1 "${rc}"
  rc=0; link_with "${good}" --here --host-definition laptop --bead beads-o27 || rc=$?
  expect_rc "two machine flags are refused" 1 "${rc}"
  rc=0; link_with "${good}" --host-definition 'lap top' --bead beads-o27 || rc=$?
  expect_rc "a malformed definition name is refused" 1 "${rc}"
  rc=0; link_with "${good}" --here --bead 'not an id' || rc=$?
  expect_rc "a malformed id is refused" 1 "${rc}"

  local bad="${work}/bad.conf"
  cat > "${bad}" <<EOF
scotty beads http://scotty.example.com/p/beads
scotty other https://scotty.example.com/p/other?x=1
scotty paren https://scotty.example.com/p/(weird)
scotty @laptop ${HOST_URL}
scotty twice https://a.example.com/p/twice
scotty twice https://b.example.com/p/twice
scotty same ${LOCAL_URL}
scotty same@laptop ${LOCAL_URL}
EOF

  link_with "${bad}" --here --bead beads-o27 --title x --bead other-abc --title y --bead paren-abc --title z
  expect_has "http, a query and a ')' are skipped" "${out}" \
    "[beads-o27]: tmux-tooltip://" "[other-abc]: tmux-tooltip://" "[paren-abc]: tmux-tooltip://"
  expect_has "a skipped URL warns with its line" "${err}" "Skipping scotty line" "line_no='1'"
  expect_has "a key with no prefix warns" "${err}" "want PREFIX or PREFIX@DEFINITION" "line_no='4'"

  link_with "${bad}" --here --bead twice-abc --title x
  expect_eq "a repeated key keeps the first line" "[twice-abc]: https://a.example.com/p/twice?bead=twice-abc" "${out}"
  expect_has "a repeated key warns with both lines" "${err}" "repeated scotty line" "line_no='6'" "first_line_no='5'"

  link_with "${bad}" --host-definition laptop --bead same-abc --title x
  expect_has "a host line on this machine's URL is skipped" "${out}" "[same-abc]: tmux-tooltip://"
  expect_has "the skipped host line warns" "${err}" "names this machine's Scotty" "line_no='8'"

  link_with "${work}/missing.conf" --here --bead beads-o27 --title x
  expect_has "no config is tmux only" "${out}" "[beads-o27]: tmux-tooltip://"

  cat <<EOF
passed=${passed}
failed=${failed}
EOF
  (( failed == 0 ))
}

main "$@"
