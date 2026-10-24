#!/usr/bin/env bash
# The xcode step: full Xcode installed, selected and licensed, each missing piece a manual fail
# with its command. xcode-select and xcodebuild are stubbed; nothing touches the Mac.
set -u
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

world_new
mkdir -p "${HOME}/.config/alttab" "${FIX}/Xcode.app/Contents"
cat > "${FIX}/Xcode.app/Contents/version.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0">
<dict>
	<key>CFBundleShortVersionString</key>
	<string>27.1</string>
</dict>
</plist>
PLIST

# check [VAR=value…]: check::xcode with SELECTED (the xcode-select path) and LICENSED (1|0).
check() {
  hermetic_env
  RC=0
  env -i "${HERMETIC_ENV[@]}" ARI_DOTFILES_NO_CACHE=1 ARI_DOTFILES_XCODE_APP="${FIX}/Xcode.app" \
    SELECTED="${FIX}/Xcode.app/Contents/Developer" LICENSED=1 "$@" \
    "${FIX}/tools/zsh" -c '
      for f in "$1"/lib/*.zsh(N); do source "${f}"; done
      source "$1/steps/xcode.zsh"
      STEP=xcode
      xcode-select() { [[ -n "${SELECTED}" ]] && print -r -- "${SELECTED}"; }
      xcodebuild() { [[ "$*" == "-license check" ]] && (( LICENSED )); }
      check::xcode' _ "${ORIG_CONFIG_DIR}/dotfiles" > "${FIX}/out" 2> "${FIX}/err" || RC=$?
  VERDICT="$(cat "${FIX}/out")"
}
field() { printf '%s' "${VERDICT}" | jq -r ".$1"; }

check
assert_eq "ready: ok, with the version" "ok ready Xcode 27.1 selected; license accepted" "$(field status) $(field reason) $(field detail)"

check ARI_DOTFILES_XCODE_APP="${FIX}/Nope.app"
assert_eq "not installed: a manual fail" "fail xcode_missing true false" "$(field status) $(field reason) $(field manual) $(field actionable)"
assert_contains "not installed: the App Store, or mas" "$(field fix)" "macappstores://apps.apple.com/app/id497799835"
assert_contains "not installed: mas named" "$(field fix)" "mas install 497799835"

check SELECTED=/Library/Developer/CommandLineTools
assert_eq "Command Line Tools selected: a manual fail" "fail not_selected true" "$(field status) $(field reason) $(field manual)"
assert_eq "Command Line Tools selected: the fix selects Xcode" "sudo xcode-select -s ${FIX}/Xcode.app" "$(field fix)"
assert_contains "Command Line Tools selected: names what is selected" "$(field detail)" "points at /Library/Developer/CommandLineTools"

check SELECTED=
assert_contains "nothing selected: says so" "$(field detail)" "points at nothing"

check LICENSED=0
assert_eq "license not accepted: a manual fail" "fail license_unaccepted true sudo xcodebuild -license accept" \
  "$(field status) $(field reason) $(field manual) $(field fix)"

rm -rf "${HOME}/.config/alttab"
check ARI_DOTFILES_XCODE_APP="${FIX}/Nope.app"
assert_eq "nothing builds with it: skip, even without Xcode" "skip not_needed" "$(field status) $(field reason)"

report
