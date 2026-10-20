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

# A registry that does not load is the preflight's (exit 3), not this step's.
printf 'step::declare zz_broken\n' > "${STEPS}/zz_broken.zsh"
copy check --only dotfiles_docs --json
assert_eq "a broken registry: exit 3" 3 "${RC}"

report
