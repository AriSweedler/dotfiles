#!/usr/bin/env bash
# The documentation rule for steps (steps::doc_gaps) and the dotfiles_docs step that flags it: a
# step without its line 1, --desc, --apply for an apply, or watches fails the step by hand only,
# naming `dotfiles steps edit` for the first; the registry still loads (a gap is never exit 3),
# and `dotfiles steps` shows the gaps in its docs column. Every step of the checkout under test
# passes.
set -u
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

world_new

# ── the checkout under test: every step documented ──
nm steps
assert_eq "steps: exit 0" 0 "${RC}"
undocumented="$(awk 'NF && $6 != "ok" { print $1 ": " $6 }' <<< "${OUT}")"
assert_eq "every step of this checkout is documented" "" "${undocumented}"
assert_contains "dotfiles_docs is a step" "$(awk '{ print $1 }' <<< "${OUT}")" "dotfiles_docs"
# A watch or a --none on every step: the coverage the pull mapping relies on.
missing=""
for f in "${ORIG_CONFIG_DIR}"/dotfiles/steps/*.zsh; do
  n="$(basename "${f}" .zsh)"
  grep -qE "^step::watches ${n} " "${f}" || missing+=" ${n}"
done
assert_eq "every step file calls step::watches (globs or --none)" "" "${missing}"
nm check --only dotfiles_docs --json
assert_eq "documented: exit 0" 0 "${RC}"
f="$(out_json)"
assert_json "documented: ok" "${f}" '.steps[] | select(.step=="dotfiles_docs") | .status' ok
assert_json "documented: the reason" "${f}" '.steps[] | select(.step=="dotfiles_docs") | .reason' documented

# ── a copy of the program the test may break ──
CODE="${HOME}/.config"
rm -f "${CODE}/dotfiles/lib" "${CODE}/dotfiles/cmd" "${CODE}/dotfiles/steps" "${CODE}/bin/dotfiles"
cp -R "${ORIG_CONFIG_DIR}/dotfiles/lib" "${ORIG_CONFIG_DIR}/dotfiles/cmd" "${ORIG_CONFIG_DIR}/dotfiles/steps" "${CODE}/dotfiles/"
cp "${ORIG_CONFIG_DIR}/bin/dotfiles" "${CODE}/bin/dotfiles"
STEPS="${CODE}/dotfiles/steps"
copy() {  # ARGS: the world's copy of the CLI
  local verb="$1"; shift
  [[ "${verb}" != check ]] || verb=healthcheck
  bump_now_secs 60
  nm_run "${CODE}/bin/dotfiles" "${verb}" "$@"
}
docs_check() { copy check --only dotfiles_docs --json; f="$(out_json)"; }
docs_get() { jq -r ".steps[] | select(.step==\"dotfiles_docs\") | $1" "${f}"; }

# Every gap at once: no line 1, no --desc, an apply without --apply, no watches.
printf 'step::declare zz_bare --group tools\ncheck::zz_bare() { verdict ok fine; }\napply::zz_bare() { run_mut true; }\n' > "${STEPS}/zz_bare.zsh"
docs_check
assert_eq "undocumented: exit 1, not a preflight 3" 1 "${RC}"
assert_eq "undocumented: fail" fail "$(docs_get .status)"
assert_eq "undocumented: the reason" undocumented "$(docs_get .reason)"
assert_eq "undocumented: manual, never applied" true "$(docs_get .manual)"
assert_eq "undocumented: the fix" "dotfiles steps edit zz_bare" "$(docs_get .fix)"
assert_eq "undocumented: what it lacks" \
  "zz_bare: line 1 is not '# step zz_bare — <summary>', no --desc, no --apply \"<what the apply changes>\", no step::watches (globs or --none \"<why it reads no repo file>\")" \
  "$(docs_get .detail)"
copy steps
assert_eq "steps still lists: exit 0" 0 "${RC}"
assert_eq "the docs column names the gaps" "header,--desc,--apply,watches" "$(awk '$1 == "zz_bare" { print $6 }' <<< "${OUT}")"
copy check --only zz_bare --json
assert_eq "the undocumented step itself still runs" ok "$(jq -r '.steps[] | select(.step=="zz_bare") | .status' "$(out_json)")"

# Two undocumented: both named, in run order, the fix for the first.
cat > "${STEPS}/aa_half.zsh" <<'EOF'
# step aa_half — half documented: a check-only step that claims an apply, and an empty --none.
step::declare aa_half --group repo --desc "half documented" --apply "nothing"
step::watches aa_half --none ""
check::aa_half() { verdict ok fine; }
EOF
docs_check
assert_eq "two undocumented: the fix names the first in run order" "dotfiles steps edit aa_half" "$(docs_get .fix)"
assert_contains "two undocumented: the first" "$(docs_get .detail)" \
  "aa_half: --apply but no apply::aa_half, step::watches --none without a reason; zz_bare: "

# Documented: back to ok.
cat > "${STEPS}/zz_bare.zsh" <<'EOF'
# step zz_bare — documented now.
step::declare zz_bare --group tools --desc "fine" --apply "does nothing"
step::watches zz_bare --none "reads nothing"
check::zz_bare() { verdict ok fine; }
apply::zz_bare() { run_mut true; }
EOF
cat > "${STEPS}/aa_half.zsh" <<'EOF'
# step aa_half — documented now.
step::declare aa_half --group repo --desc "fine"
step::watches aa_half '.config/aa/**'
check::aa_half() { verdict ok fine; }
EOF
docs_check
assert_eq "fixed: ok" ok "$(docs_get .status)"

# ── the help rule: every verb's help, and the top-level one ──
assert_contains "documented: counts the helps" "$(docs_get .detail)" " helps"
CMD="${CODE}/dotfiles/cmd"
cat > "${CMD}/zz.zsh" <<'EOS'
# dotfiles/cmd/zz.zsh — a verb the test owns, not declared.
cmd_zz() {
  case "${1:-}" in
    --frob) ;;
  esac
}
EOS
docs_check
assert_eq "a verb not declared: fail" fail "$(docs_get .status)"
assert_eq "a verb not declared: manual" true "$(docs_get .manual)"
assert_eq "a verb not declared: the fix" "dotfiles help --edit zz" "$(docs_get .fix)"
assert_contains "a verb not declared: what it lacks" "$(docs_get .detail)" "dotfiles zz --help: not declared: 'dotfiles help --edit zz' writes the declaration"
# Declared, but still parsing a flag by hand.
cat > "${CMD}/zz.zsh" <<'EOS'
# dotfiles/cmd/zz.zsh — a verb the test owns, declared, parsing by hand.
verb::define zz 'frob the zz'
verb::usage zz 'zz [--frob]'
verb::flag zz '--frob' 'frob it'
verb::edit zz --none 'zz has nothing to edit'
cmd_zz() {
  case "${1:-}" in
    --frob) ;;
  esac
}
EOS
docs_check
assert_eq "a flag parsed by hand: fail" fail "$(docs_get .status)"
assert_contains "a flag parsed by hand: named" "$(docs_get .detail)" "dotfiles zz --help: parses flags outside verb::parse: --frob"
# Declared and parsed by verb::parse; a hand-parsed flag in cmd/VERB/*.zsh counts too.
cat > "${CMD}/zz.zsh" <<'EOS'
# dotfiles/cmd/zz.zsh — a verb the test owns, declared.
verb::define zz 'frob the zz'
verb::usage zz 'zz [--frob]'
verb::flag zz '--frob' 'frob it'
verb::edit zz --none 'zz has nothing to edit'
cmd_zz() { local -A opts; local -a args; verb::parse zz "$@"; }
EOS
mkdir -p "${CMD}/zz"
printf 'zz_sub() {\n  case "${1}" in\n    --sub-flag) ;;\n  esac\n}\n' > "${CMD}/zz/sub.zsh"
docs_check
assert_contains "a flag of cmd/VERB/*.zsh: named" "$(docs_get .detail)" "dotfiles zz --help: parses flags outside verb::parse: --sub-flag"
assert_not_contains "the declared flag is not named" "$(docs_get .detail)" "--frob"
rm -rf "${CMD}/zz"
docs_check
assert_eq "a whole declaration: ok" ok "$(docs_get .status)"
# The top-level help is held to main()'s flags; with a verb's gap too, its fix comes first.
DISPATCH="${CODE}/dotfiles/lib/dispatch.zsh"
cp "${DISPATCH}" "${FIX}/dispatch.orig"
awk '/^help\(\) \{/ { h = 1 } h { gsub(/--timing/, "--timingx") } /^}/ { h = 0 } { print }' "${FIX}/dispatch.orig" > "${DISPATCH}"
awk '{ sub(/\x27frob it\x27/, "\x27\x27") } { print }' "${CMD}/zz.zsh" > "${CMD}/zz.zsh.tmp" && mv "${CMD}/zz.zsh.tmp" "${CMD}/zz.zsh"
docs_check
assert_eq "top-level gap: the fix" "dotfiles help --edit" "$(docs_get .fix)"
assert_contains "top-level gap: named" "$(docs_get .detail)" "dotfiles --help: flags not in it: --timing"
assert_contains "and the verb's gap after it" "$(docs_get .detail)" "; dotfiles zz --help: '--frob' has no description"
cp "${FIX}/dispatch.orig" "${DISPATCH}"
rm -f "${CMD}/zz.zsh"
# Cached while nothing it reads changes; a change to a verb file is seen.
sleep 2
docs_check
assert_eq "fixed again: ok" ok "$(docs_get .status)"
docs_check
assert_contains "unchanged: the verdict is the cached one" "$(docs_get .detail)" "cached: true"
printf 'cmd_zz() { :; }\n' > "${CMD}/zz.zsh"
docs_check
assert_eq "a new verb file after a cached verdict: seen" fail "$(docs_get .status)"
assert_not_contains "a new verb file: not the cached verdict" "$(docs_get .detail)" "cached: true"
rm -f "${CMD}/zz.zsh"

# A registry that does not load is the preflight's (exit 3), not this step's.
printf 'step::declare zz_broken\n' > "${STEPS}/zz_broken.zsh"
copy check --only dotfiles_docs --json
assert_eq "a broken registry: exit 3" 3 "${RC}"

report
