#!/usr/bin/env bash
# The chrome_exoskeleton step: once dist/ is built, Chrome must load it unpacked and enabled in at
# least one profile, read from a fake Chrome user data dir; anything less is a manual fail. Node,
# the submodule identity and its hooksPath are stubbed; nothing touches the real Chrome.
set -u
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

world_new
FW="${HOME}/.config/chrome-exoskeleton"
CHROME="${FIX}/chrome"
mkdir -p "${FW}/bin" "${FW}/node_modules" "${FW}/dist" "${CHROME}/Default" "${CHROME}/Profile 1"
printf '#!/bin/zsh\n' > "${FW}/bin/exo" && chmod +x "${FW}/bin/exo"
printf '{"version":"9.9.9"}\n' > "${FW}/dist/manifest.json"
jq -n '{profile: {info_cache: {"Default": {name: "Work"}, "Profile 1": {name: "Home"}}}}' > "${CHROME}/Local State"

# prefs <profile dir> <file> <entry JSON or empty>: that profile's prefs file with one extension
# entry (or none).
prefs() {
  local entry="${3:-}"
  if [[ -z "${entry}" ]]; then printf '{}\n' > "${CHROME}/$1/$2"; return; fi
  jq -n --argjson e "${entry}" '{extensions: {settings: {abcdefghijklmnopabcdefghijklmnop: $e}}}' > "${CHROME}/$1/$2"
}
reset_prefs() { rm -f "${CHROME}"/*/Preferences "${CHROME}"/*/"Secure Preferences"; }

check() {
  hermetic_env
  RC=0
  env -i "${HERMETIC_ENV[@]}" ARI_DOTFILES_CHROME_DIR="${CHROME}" "$@" \
    "${FIX}/tools/zsh" -c '
      for f in "$1"/lib/*.zsh(N); do source "${f}"; done
      source "$1/steps/chrome_exoskeleton.zsh"
      STEP=chrome_exoskeleton
      step::chrome_exoskeleton::is_node_present() { return 0; }
      tier::is_submodule_identity_ok() { return 0; }
      git() { [[ "$*" == *"config core.hooksPath"* ]] && print -r -- .githooks; }
      check::chrome_exoskeleton' _ "${ORIG_CONFIG_DIR}/dotfiles" > "${FIX}/out" 2> "${FIX}/err" || RC=$?
  VERDICT="$(cat "${FIX}/out")"
}
field() { printf '%s' "${VERDICT}" | jq -r ".$1"; }

check
assert_eq "no profile loads it: a manual fail" "fail not_loaded true false" "$(field status) $(field reason) $(field manual) $(field actionable)"
assert_contains "no profile loads it: names the profiles" "$(field detail)" "Work, Home"
assert_contains "no profile loads it: the fix is Load unpacked" "$(field fix)" "Load unpacked: ${FW}/dist"

prefs Default "Secure Preferences" "{\"path\": \"${FW}/dist\", \"location\": 4}"
check
assert_eq "loaded in one profile: ok" "ok built" "$(field status) $(field reason)"
assert_contains "loaded in one profile: names it and the one without" "$(field detail)" "loaded in 'Work' (not in 'Home')"

prefs "Profile 1" "Secure Preferences" "{\"path\": \"${FW}/dist-personal\", \"location\": 4}"
check
assert_eq "dist-personal counts too" "ok built" "$(field status) $(field reason)"
assert_contains "loaded in both: no 'not in'" "$(field detail)" "loaded in 'Work, Home'"
assert_not_contains "loaded in both: no 'not in'" "$(field detail)" "not in"

reset_prefs
prefs Default Preferences "{\"path\": \"${FW}/dist\", \"location\": 4}"
check
assert_eq "an older Chrome's Preferences counts" "ok built" "$(field status) $(field reason)"

reset_prefs
prefs Default "Secure Preferences" "{\"path\": \"/elsewhere/dist\", \"location\": 4}"
check
assert_eq "another unpacked extension does not count" "fail not_loaded" "$(field status) $(field reason)"

for off in '"disable_reasons": [1]' '"disable_reasons": 1' '"state": 0'; do
  reset_prefs
  prefs Default "Secure Preferences" "{\"path\": \"${FW}/dist\", ${off}}"
  check
  assert_eq "turned off (${off}): a manual fail" "fail disabled true" "$(field status) $(field reason) $(field manual)"
  assert_contains "turned off (${off}): names the profile" "$(field detail)" "profiles='Work'"
done

reset_prefs
prefs Default "Secure Preferences" "{\"path\": \"${FW}/dist\", \"disable_reasons\": []}"
check
assert_eq "an empty disable_reasons list is enabled" "ok built" "$(field status) $(field reason)"

check ARI_DOTFILES_CHROME_DIR="${FIX}/no-chrome"
assert_eq "Chrome never opened: a manual fail" "fail not_loaded true" "$(field status) $(field reason) $(field manual)"
assert_contains "Chrome never opened: says so" "$(field detail)" "no Chrome profile found"

rm -f "${FW}/dist/manifest.json"
check
assert_eq "not built comes first, and init builds it" "fail not_built false" "$(field status) $(field reason) $(field manual)"

report
