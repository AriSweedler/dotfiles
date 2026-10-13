# step alttab — the Free-tier AltTab built from source (~/.config/alttab/bin/alttab-free-build).
# The check reads the machine: the app is the patched build (signed with the local certificate),
# the updater is pinned to manual, and the Homebrew cask is gone. The apply runs the build, which
# quits and replaces /Applications/AltTab.app. The local signing certificate is a human step: its
# creation pops a system password dialog, so the apply refuses to run until it exists.
step::declare alttab --group tools --desc "AltTab, the Free-tier build from source: patched app installed, updater manual, no Homebrew cask (~/.config/alttab)"
step::watches alttab '.config/alttab/**'

step::alttab::paths() {
  ALTTAB_DIR="${HOME}/.config/alttab"
  ALTTAB_APP="${ALTTAB_APP:-/Applications/AltTab.app}"
  ALTTAB_BUNDLE="com.lwouis.alt-tab-macos"
  ALTTAB_IDENTITY="AltTab Free Local"
}

# `brew list --cask alt-tab` succeeds, read from the Caskroom: a cask is installed when its
# .metadata holds an installed caskfile. A brew with no Caskroom beside it (a wrapper, a test
# shim) is asked instead.
step::alttab::has_cask() {
  command -v brew >/dev/null 2>&1 || return 1
  local REPLY
  if cache::brew_prefix; then
    local -a caskfiles=("${REPLY}/Caskroom/alt-tab/.metadata/"*/*/Casks/alt-tab.(rb|json)(N))
    (( ${#caskfiles} ))
    return
  fi
  brew list --cask alt-tab >/dev/null 2>&1
}

check::alttab() {
  step::alttab::paths
  if [[ "${OSTYPE}" != darwin* ]]; then
    verdict skip not_macos -d "AltTab is macOS only"
    return 0
  fi
  if [[ ! -d "${ALTTAB_DIR}" ]]; then
    verdict skip no_alttab_dir -d "${ALTTAB_DIR} is not present on this machine"
    return 0
  fi
  if [[ ! -d "${ALTTAB_APP}" ]]; then
    verdict fail alttab_missing -d "AltTab is not installed at ${ALTTAB_APP}" -f "${CLI_NAME} apply alttab"
    return 0
  fi
  if step::alttab::has_cask; then
    verdict fail alttab_cask -d "the official alt-tab Homebrew cask is installed; it starts the Pro trial" -f "${CLI_NAME} apply alttab"
    return 0
  fi
  if ! zsh "${ALTTAB_DIR}/bin/alttab-free-cert" --status >/dev/null 2>&1; then
    verdict fail cert_missing -d "the local signing certificate '${ALTTAB_IDENTITY}' is not created or trusted" -f "run by hand, after reading the dialog warning: ! zsh ${ALTTAB_DIR}/bin/alttab-free-cert"
    return 0
  fi
  local sig
  sig="$(codesign -dvvv "${ALTTAB_APP}" 2>&1 || true)"
  if [[ "${sig}" != *"Authority=${ALTTAB_IDENTITY}"* && "${sig}" != *"Signature=adhoc"* ]]; then
    verdict fail not_patched -d "${ALTTAB_APP} is not the patched build (signed by something other than '${ALTTAB_IDENTITY}')" -f "${CLI_NAME} apply alttab"
    return 0
  fi
  local policy auto
  policy="$(defaults read "${ALTTAB_BUNDLE}" updatePolicy 2>/dev/null || echo unset)"
  auto="$(defaults read "${ALTTAB_BUNDLE}" SUEnableAutomaticChecks 2>/dev/null || echo unset)"
  if [[ "${policy}" != 0 || "${auto}" != 0 ]]; then
    verdict fail updater_auto -d "AltTab's updater is not pinned to manual | updatePolicy='${policy}' SUEnableAutomaticChecks='${auto}'" -f "${CLI_NAME} apply alttab"
    return 0
  fi
  verdict ok in_sync -d "patched AltTab installed; updater manual; no Homebrew cask"
}

apply::alttab() {
  step::alttab::paths
  if ! zsh "${ALTTAB_DIR}/bin/alttab-free-cert" --status >/dev/null 2>&1; then
    print -u2 "[ERROR] alttab certificate missing; create it by hand first | cmd='zsh ${ALTTAB_DIR}/bin/alttab-free-cert'"
    return 1
  fi
  run_mut zsh "${ALTTAB_DIR}/bin/alttab-free-build"
}
