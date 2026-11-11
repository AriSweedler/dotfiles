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

# prefs_many <profile dir> <file> <entry JSON>...: that profile's prefs file with one extension
# entry per argument, keyed id0, id1, … in order.
prefs_many() {
  local dir="$1" file="$2"; shift 2
  jq -n '{extensions: {settings: ([$ARGS.positional[] | fromjson] | to_entries | map({key: "id\(.key)", value}) | from_entries)}}' \
    --args "$@" > "${CHROME}/${dir}/${file}"
}

reset_prefs
prefs_many Default "Secure Preferences" "{\"path\": \"${FW}/dist-personal\"}" "{\"path\": \"${FW}/dist\"}"
check
assert_eq "dist and dist-personal on in one profile: a manual fail" "fail duplicate_load true" "$(field status) $(field reason) $(field manual)"
assert_contains "duplicate: names the copy to remove" "$(field detail)" "'Work': id0 (${FW}/dist-personal)"
assert_not_contains "duplicate: keeps the dist/ copy" "$(field detail)" "id1"
assert_contains "duplicate: the fix names the copy to keep" "$(field fix)" "keep the one loaded from ${FW}/dist"

reset_prefs
prefs_many Default "Secure Preferences" "{\"path\": \"${FW}/dist-personal\", \"disable_reasons\": [1]}" "{\"path\": \"${FW}/dist\"}"
check
assert_eq "a second copy turned off is no duplicate" "ok built" "$(field status) $(field reason)"

reset_prefs
prefs Default "Secure Preferences" "{\"path\": \"${FW}/dist\"}"
prefs "Profile 1" "Secure Preferences" "{\"path\": \"${FW}/dist\"}"
check
assert_eq "one copy in each of two profiles is no duplicate" "ok built" "$(field status) $(field reason)"

# The framework reached through a link, as ~/.config/chrome-exoskeleton is: Chrome keys the
# link's path and the resolved one as two extensions.
REAL="${FIX}/exo-checkout"
mv "${FW}" "${REAL}" && ln -s "${REAL}" "${FW}"
REAL_P="$(cd "${REAL}" && pwd -P)"
reset_prefs
prefs_many Default "Secure Preferences" "{\"path\": \"${REAL_P}/dist\"}" "{\"path\": \"${FW}/dist\"}"
check
assert_eq "the link's path and the resolved one: a duplicate" "fail duplicate_load" "$(field status) $(field reason)"
assert_contains "resolved duplicate: removes the resolved copy" "$(field detail)" "id0 (${REAL_P}/dist)"
assert_not_contains "resolved duplicate: keeps the link's copy" "$(field detail)" "id1"
rm "${FW}" && mv "${REAL}" "${FW}"

check ARI_DOTFILES_CHROME_DIR="${FIX}/no-chrome"
assert_eq "Chrome never opened: a manual fail" "fail not_loaded true" "$(field status) $(field reason) $(field manual)"
assert_contains "Chrome never opened: says so" "$(field detail)" "no Chrome profile found"

# assist <answer> <poll the load lands on, 0: never> [env..]: runs assist::chrome_exoskeleton with
# ui::confirm answering <answer>, and `open` and `osascript` logged to ${FIX}/open.log instead of
# run; osascript prints T_TAB_URL (default chrome://extensions/) and exits T_OSA_RC. The probe runs
# in a command substitution, so the poll count lives in ${FIX}/polls; on poll <n> the extension's
# entry lands in Default's Secure Preferences, as Chrome would write it after Load unpacked.
assist() {
  local answer="$1" load_after="$2"; shift 2
  hermetic_env
  RC=0
  : > "${FIX}/open.log"
  print 0 > "${FIX}/polls"
  env -i "${HERMETIC_ENV[@]}" ARI_DOTFILES_CHROME_DIR="${CHROME}" ARI_DOTFILES_UI=plain AWAIT_BELL=0 \
    T_FIX="${FIX}" T_ANSWER="${answer}" T_LOAD_AFTER="${load_after}" T_TAB_URL=chrome://extensions/ T_OSA_RC=0 \
    T_ENTRY="{\"extensions\": {\"settings\": {\"abcdefghijklmnopabcdefghijklmnop\": {\"path\": \"${FW}/dist\"}}}}" "$@" \
    "${FIX}/tools/zsh" -c '
      for f in "$1"/lib/*.zsh(N); do source "${f}"; done
      source "$1/steps/chrome_exoskeleton.zsh"
      open() { print -r -- "$*" >> "${T_FIX}/open.log"; }
      osascript() {
        print -r -- "osascript $* $(cat)" >> "${T_FIX}/open.log"
        (( T_OSA_RC == 0 )) || { print -ru2 -- "execution error: Not authorized to send Apple events to Google Chrome. (-1743)"; return "${T_OSA_RC}"; }
        print -r -- "${T_TAB_URL}"
      }
      ui::confirm() { print -ru2 -- "ASKED: $1"; [[ "${T_ANSWER}" == y ]]; }
      functions -c step::chrome_exoskeleton::is_loaded real_is_loaded
      step::chrome_exoskeleton::is_loaded() {
        local -i n=$(( $(<"${T_FIX}/polls") + 1 ))
        print -r -- "${n}" > "${T_FIX}/polls"
        if (( T_LOAD_AFTER > 0 && n >= T_LOAD_AFTER )); then
          print -r -- "${T_ENTRY}" > "${ARI_DOTFILES_CHROME_DIR}/Default/Secure Preferences"
        fi
        real_is_loaded "$@"
      }
      assist::chrome_exoskeleton' _ "${ORIG_CONFIG_DIR}/dotfiles" > "${FIX}/out" 2> "${FIX}/err" || RC=$?
}

reset_prefs
assist n 0
assert_eq "assist, N: returns 1 so the fail stands" 1 "${RC}"
assert_contains "assist, N: asks to load it" "$(cat "${FIX}/err")" "ASKED: Load the Chrome Exoskeleton into Chrome now?"
assert_eq "assist, N: opens nothing" "" "$(cat "${FIX}/open.log")"

reset_prefs
assist y 2
assert_eq "assist, y and the load lands: returns 0 for a re-check" 0 "${RC}"
assert_contains "assist, y: reveals dist in Finder" "$(cat "${FIX}/open.log")" "-R ${FW}/dist"
assert_contains "assist, y: opens the extensions page through Chrome's script dictionary" "$(cat "${FIX}/open.log")" "osascript - chrome://extensions"
assert_contains "assist, y: the script makes a tab" "$(cat "${FIX}/open.log")" "make new tab"
assert_not_contains "assist, y: never hands open a chrome:// URL" "$(cat "${FIX}/open.log")" "-a Google Chrome"
assert_contains "assist, y: logs the tab it opened" "$(cat "${FIX}/err")" "opened the extensions page"
assert_contains "assist, y: says what to click" "$(cat "${FIX}/err")" "Load unpacked"
assert_contains "assist, y: says how to stop waiting" "$(cat "${FIX}/err")" "Ctrl-C to stop"

reset_prefs
assist y 0 ARI_DOTFILES_ASSIST_WAIT_SECS=1
assert_eq "assist, y but no load before the deadline: returns 1" 1 "${RC}"
assert_contains "assist, timed out: says it stopped waiting" "$(cat "${FIX}/err")" "stopped waiting"

reset_prefs
prefs Default "Secure Preferences" "{\"path\": \"${FW}/dist\", \"disable_reasons\": [1]}"
assist y 0 ARI_DOTFILES_ASSIST_WAIT_SECS=1
assert_contains "assist, turned off: asks to turn it on" "$(cat "${FIX}/err")" "ASKED: Turn the Chrome Exoskeleton on in Chrome now?"
assert_not_contains "assist, turned off: no Finder window" "$(cat "${FIX}/open.log")" "-R "
reset_prefs

assist y 2 T_TAB_URL=about:blank
assert_eq "assist, the tab lands elsewhere: still waits, and the load returns 0" 0 "${RC}"
assert_contains "assist, the tab lands elsewhere: says to type the address" "$(cat "${FIX}/err")" "tab_url='about:blank' fix='type chrome://extensions into Chrome'"
reset_prefs

assist y 2 T_OSA_RC=1
assert_eq "assist, Chrome refuses the script: still waits, and the load returns 0" 0 "${RC}"
assert_contains "assist, Chrome refuses the script: names the Automation permission" "$(cat "${FIX}/err")" "Privacy & Security › Automation"
assert_contains "assist, Chrome refuses the script: quotes the error" "$(cat "${FIX}/err")" "(-1743)"
reset_prefs

rm -f "${FW}/dist/manifest.json"
check
assert_eq "not built comes first, and init builds it" "fail not_built false" "$(field status) $(field reason) $(field manual)"

report
