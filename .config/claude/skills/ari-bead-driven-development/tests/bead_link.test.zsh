#!/usr/bin/env zsh
# Proves bead_link.zsh's link choice against fixture configs under mktemp: a local prefix match links
# to its Scotty page, a host's beads use only their PREFIX@DEFINITION line and never this machine's,
# a malformed, repeated or local-URL scotty line is skipped, and the machine flag is required once.
# Uses the real tmux-tooltip; never reads or writes Ari's beads.conf.
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
  BEAD_LINK_CONFIG="${config}" zsh "${BEAD_LINK}" "$@" > "${work}/out" 2> "${work}/err" || rc=$?
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
  expect_has "a local prefix match links to its Scotty page with the card" "${out}" \
    "[beads-o27](${LOCAL_URL}?bead=beads-o27&tmux-tooltip=show&" "color=cyan"

  link_with "${good}" --here --bead other-abc --title x
  expect_has "a prefix with no scotty line links to tmux only" "${out}" "[other-abc](tmux-tooltip://show?"

  link_with "${good}" --host-definition laptop --bead beads-o27 --title x
  expect_has "a host's bead uses its PREFIX@DEFINITION line" "${out}" "[beads-o27](${HOST_URL}?bead=beads-o27&"

  link_with "${good}" --host-definition co2 --bead beads-o27 --title x
  expect_has "a host with no line links to tmux only, never this machine's Scotty" "${out}" "[beads-o27](tmux-tooltip://show?"

  link_with "${good}" --host-definition local --bead beads-o27 --title x
  expect_has "the local definition links as --here" "${out}" "[beads-o27](${LOCAL_URL}?bead=beads-o27&"

  rc=0; link_with "${good}" --bead beads-o27 --title x || rc=$?
  expect_rc "no machine flag is refused" 1 "${rc}"
  rc=0; link_with "${good}" --here --host-definition laptop --bead beads-o27 --title x || rc=$?
  expect_rc "two machine flags are refused" 1 "${rc}"
  rc=0; link_with "${good}" --host-definition 'lap top' --bead beads-o27 --title x || rc=$?
  expect_rc "a malformed definition name is refused" 1 "${rc}"

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
    "[beads-o27](tmux-tooltip://" "[other-abc](tmux-tooltip://" "[paren-abc](tmux-tooltip://"
  expect_has "a skipped URL warns with its line" "${err}" "Skipping scotty line" "line_no='1'"
  expect_has "a key with no prefix warns" "${err}" "want PREFIX or PREFIX@DEFINITION" "line_no='4'"

  link_with "${bad}" --here --bead twice-abc --title x
  expect_has "a repeated key keeps the first line" "${out}" "[twice-abc](https://a.example.com/p/twice?bead=twice-abc&"
  expect_has "a repeated key warns with both lines" "${err}" "repeated scotty line" "line_no='6'" "first_line_no='5'"

  link_with "${bad}" --host-definition laptop --bead same-abc --title x
  expect_has "a host line on this machine's URL is skipped" "${out}" "[same-abc](tmux-tooltip://"
  expect_has "the skipped host line warns" "${err}" "names this machine's Scotty" "line_no='8'"

  link_with "${work}/missing.conf" --here --bead beads-o27 --title x
  expect_has "no config links to tmux only" "${out}" "[beads-o27](tmux-tooltip://"

  cat <<EOF
passed=${passed}
failed=${failed}
EOF
  (( failed == 0 ))
}

main "$@"
