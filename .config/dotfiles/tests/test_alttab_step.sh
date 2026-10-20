#!/usr/bin/env bash
# The alttab step: a needed build is something init runs only when no human is needed. Without
# full Xcode or the signing certificate it is a manual fail naming the fix; with both, init's.
# The probes (Xcode, certificate, cask, codesign, defaults) are stubbed; nothing touches the Mac.
set -u
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

world_new
mkdir -p "${HOME}/.config/alttab/bin" "${FIX}/apps/AltTab.app" "${FIX}/apps/Xcode.app" "${FIX}/no-apps"

# check [VAR=value…]: check::alttab with stubbed probes; XCODE (selected), LICENSE, FIRST_LAUNCH,
# CERT, CASK, SIGNED, MANUAL_UPDATES are 1 or 0 (default: the converged Mac, CASK=0), and the Xcode
# app is ARI_DOTFILES_XCODE_APP (in the world's apps folder). VERDICT is its JSON line.
check() {
  hermetic_env
  RC=0
  env -i "${HERMETIC_ENV[@]}" ALTTAB_APP="${FIX}/apps/AltTab.app" ARI_DOTFILES_XCODE_APP="${FIX}/apps/Xcode.app" XCODE=1 LICENSE=1 FIRST_LAUNCH=1 CERT=1 CASK=0 SIGNED=1 MANUAL_UPDATES=1 "$@" \
    "${FIX}/tools/zsh" -c '
      for f in "$1"/lib/*.zsh(N); do source "${f}"; done
      source "$1/steps/alttab.zsh"
      STEP=alttab
      xcode-select() { (( XCODE )) && print -r -- "${ARI_DOTFILES_XCODE_APP}/Contents/Developer" || print -r -- /Library/Developer/CommandLineTools; }
      xcodebuild() { case "$*" in "-license check") (( LICENSE )) ;; -checkFirstLaunchStatus) (( FIRST_LAUNCH )) ;; *) return 99 ;; esac; }
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

check ALTTAB_APP="${FIX}/apps/Nope.app" ARI_DOTFILES_XCODE_APP="${FIX}/no-apps/Xcode.app" CERT=0
assert_eq "missing, no Xcode app: a manual fail" "fail alttab_missing true false" \
  "$(field status) $(field reason) $(field manual) $(field actionable)"
assert_contains "missing, no Xcode app: the fix is the App Store, then install" "$(field fix)" "install Xcode (open 'macappstores://apps.apple.com/app/id497799835', or: mas install 497799835), then dotfiles alttab install"

for state in "XCODE=0:is selected" "LICENSE=0:the Xcode license is not accepted" "FIRST_LAUNCH=0:Xcode's first-launch packages are not installed"; do
  check ALTTAB_APP="${FIX}/apps/Nope.app" "${state%%:*}"
  assert_eq "missing, ${state%%:*}: manual, alttab install does it" "fail alttab_missing true dotfiles alttab install" \
    "$(field status) $(field reason) $(field manual) $(field fix)"
  assert_contains "missing, ${state%%:*}: the detail says which" "$(field detail)" "${state#*:}"
done

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

# ── alttab install gets Xcode ready: each missing piece one sudo command, named, then re-probed ──
# State lives in files: selected, license, first_launch exist once done. The sudo stub logs the
# command and does it, unless STICKY (the fix does not take) or SUDO_FAILS.
STATE="${FIX}/xcode-state"
ready() {
  hermetic_env
  RC=0
  env -i "${HERMETIC_ENV[@]}" ARI_DOTFILES_XCODE_APP="${FIX}/apps/Xcode.app" STATE="${STATE}" STICKY=0 SUDO_FAILS=0 "$@" \
    "${FIX}/tools/zsh" -c '
      for f in "$1"/lib/*.zsh(N); do source "${f}"; done
      source "$1/steps/alttab.zsh"; source "$1/cmd/alttab.zsh"
      xcode-select() { [[ -e "${STATE}/selected" ]] && print -r -- "${ARI_DOTFILES_XCODE_APP}/Contents/Developer" || print -r -- /Library/Developer/CommandLineTools; }
      xcodebuild() { case "$*" in "-license check") [[ -e "${STATE}/license" ]] ;; -checkFirstLaunchStatus) [[ -e "${STATE}/first_launch" ]] ;; *) return 99 ;; esac; }
      sudo() {
        print -r -- "sudo $*" >> "${STATE}/sudo.log"
        (( SUDO_FAILS )) && return 1
        (( STICKY )) && return 0
        case "$*" in
          "xcode-select -s "*) : > "${STATE}/selected" ;;
          "xcodebuild -license accept") : > "${STATE}/license" ;;
          "xcodebuild -runFirstLaunch") : > "${STATE}/first_launch" ;;
        esac
      }
      alttab::ready_xcode' _ "${ORIG_CONFIG_DIR}/dotfiles" > "${FIX}/out" 2> "${FIX}/err" || RC=$?
  OUT="$(cat "${FIX}/out")" ERR="$(cat "${FIX}/err")"
  SUDO="$(cat "${STATE}/sudo.log" 2>/dev/null)"
}
fresh() { rm -rf "${STATE}"; mkdir -p "${STATE}"; for f in "$@"; do : > "${STATE}/${f}"; done; }

fresh
ready
assert_eq "nothing done: exit 0" 0 "${RC}"
assert_eq "nothing done: select, license, first launch, in order" \
  "sudo xcode-select -s ${FIX}/apps/Xcode.app"$'\n'"sudo xcodebuild -license accept"$'\n'"sudo xcodebuild -runFirstLaunch" "${SUDO}"
assert_contains "each command is named before it runs" "${OUT}" "  sudo xcodebuild -runFirstLaunch"

fresh selected license
ready
assert_eq "an updated Xcode: only the first launch" "sudo xcodebuild -runFirstLaunch" "${SUDO}"
assert_contains "it says why" "${OUT}" "Installing Xcode's first-launch packages"

fresh selected license first_launch
ready
assert_eq "ready: exit 0" 0 "${RC}"
assert_eq "ready: no sudo" "" "${SUDO}"

fresh selected license
ready STICKY=1
assert_eq "a fix that does not take: exit 1" 1 "${RC}"
assert_contains "a fix that does not take: says so" "${ERR}" "Xcode is still not ready after the fix | state='first_launch'"
assert_eq "a fix that does not take: tried once" "sudo xcodebuild -runFirstLaunch" "${SUDO}"

fresh selected
ready SUDO_FAILS=1
assert_eq "a failed sudo: exit 1" 1 "${RC}"
assert_contains "a failed sudo: names the command" "${ERR}" "Xcode setup command failed | cmd='sudo xcodebuild -license accept'"

fresh
ready ARI_DOTFILES_DRY_RUN=1
assert_eq "dry run: exit 0" 0 "${RC}"
assert_eq "dry run: no sudo" "" "${SUDO}"
assert_contains "dry run: the plan" "${OUT}" "sudo xcodebuild -runFirstLaunch   (if needed)"

fresh
ready ARI_DOTFILES_XCODE_APP="${FIX}/no-apps/Xcode.app"
assert_eq "no Xcode app: exit 1" 1 "${RC}"
assert_contains "no Xcode app: the App Store" "${ERR}" "macappstores://apps.apple.com/app/id497799835"
assert_eq "no Xcode app: no sudo" "" "${SUDO}"

report
