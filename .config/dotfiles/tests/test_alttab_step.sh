#!/usr/bin/env bash
# The alttab step: a needed build is something init runs only when no human is needed. Without
# full Xcode or the signing certificate it is a manual fail naming the fix; with both, init's.
# The probes (Xcode, certificate, cask, codesign, defaults) are stubbed; nothing touches the Mac.
set -u
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

world_new
mkdir -p "${HOME}/.config/alttab/bin" "${FIX}/apps/AltTab.app"

# check [VAR=value…]: check::alttab with stubbed probes; XCODE, CERT, CASK, SIGNED, MANUAL_UPDATES
# are 1 or 0 (default 1, the converged Mac). VERDICT is its JSON line.
check() {
  hermetic_env
  RC=0
  env -i "${HERMETIC_ENV[@]}" ALTTAB_APP="${FIX}/apps/AltTab.app" XCODE=1 CERT=1 CASK=0 SIGNED=1 MANUAL_UPDATES=1 "$@" \
    "${FIX}/tools/zsh" -c '
      for f in "$1"/lib/*.zsh(N); do source "${f}"; done
      source "$1/steps/alttab.zsh"
      STEP=alttab
      xcode-select() { (( XCODE )) && print -r -- /Applications/Xcode.app/Contents/Developer || print -r -- /Library/Developer/CommandLineTools; }
      step::alttab::has_cert() { (( CERT )); }
      step::alttab::has_cask() { (( CASK )); }
      codesign() { (( SIGNED )) && print -r -- "Authority=AltTab Free Local" || print -r -- "Authority=Developer ID Application: Someone"; }
      defaults() { (( MANUAL_UPDATES )) && print -r -- 0 || print -r -- 1; }
      check::alttab' _ "${ORIG_CONFIG_DIR}/dotfiles" > "${FIX}/out" 2> "${FIX}/err" || RC=$?
  VERDICT="$(cat "${FIX}/out")"
}
field() { printf '%s' "${VERDICT}" | jq -r ".$1"; }

check
assert_eq "converged: ok" "ok in_sync" "$(field status) $(field reason)"

check ALTTAB_APP="${FIX}/apps/Nope.app"
assert_eq "missing, Xcode and certificate in place: init builds it" "fail alttab_missing false true" \
  "$(field status) $(field reason) $(field manual) $(field actionable)"
assert_eq "missing, Xcode and certificate in place: the fix is apply" "dotfiles apply alttab" "$(field fix)"

check ALTTAB_APP="${FIX}/apps/Nope.app" CERT=0
assert_eq "missing, no certificate: a manual fail init leaves alone" "fail alttab_missing true false" \
  "$(field status) $(field reason) $(field manual) $(field actionable)"
assert_eq "missing, no certificate: the fix is alttab install" "dotfiles alttab install" "$(field fix)"
assert_contains "missing, no certificate: the detail says why" "$(field detail)" "the signing certificate 'AltTab Free Local' is not created yet"

check ALTTAB_APP="${FIX}/apps/Nope.app" XCODE=0 CERT=0
assert_eq "missing, no Xcode: a manual fail" "fail alttab_missing true false" \
  "$(field status) $(field reason) $(field manual) $(field actionable)"
assert_contains "missing, no Xcode: the fix selects Xcode, then installs" "$(field fix)" "sudo xcode-select -s /Applications/Xcode.app && sudo xcodebuild -license accept && dotfiles alttab install"
assert_contains "missing, no Xcode: the detail names what is selected" "$(field detail)" "/Library/Developer/CommandLineTools is selected"

check CASK=1 CERT=0
assert_eq "the cask, no certificate: manual, alttab install" "fail alttab_cask true dotfiles alttab install" \
  "$(field status) $(field reason) $(field manual) $(field fix)"

check CERT=0
assert_eq "installed but no certificate: manual, alttab install" "fail cert_missing true dotfiles alttab install" \
  "$(field status) $(field reason) $(field manual) $(field fix)"

check SIGNED=0
assert_eq "not the patched build: init rebuilds it" "fail not_patched false dotfiles apply alttab" \
  "$(field status) $(field reason) $(field manual) $(field fix)"

check MANUAL_UPDATES=0 XCODE=0
assert_eq "updater on, no Xcode: manual" "fail updater_auto true" "$(field status) $(field reason) $(field manual)"

rm -rf "${HOME}/.config/alttab"
check
assert_eq "no sources: skip" "skip no_alttab_dir" "$(field status) $(field reason)"

report
