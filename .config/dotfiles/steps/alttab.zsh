# step alttab — the Free-tier AltTab built from source (~/.config/alttab/bin/alttab-free-build).
# The check reads the machine: the app is the patched build (signed with the local certificate),
# the updater is pinned to manual, and the Homebrew cask is gone. The apply runs the build, which
# quits and replaces /Applications/AltTab.app. The local signing certificate is a human step: its
# creation pops a system password dialog, so init never makes it: until it exists, and while full
# Xcode is not selected, a needed build is a manual fail naming `dotfiles alttab install`.
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

# Full Xcode is selected: Command Line Tools alone cannot build a macOS app. One ~15 ms call.
step::alttab::has_xcode() {
  local dev
  dev="$(xcode-select -p 2>/dev/null)" || return 1
  [[ "${dev}" == *.app/Contents/Developer ]]
}

step::alttab::has_cert() { zsh "${ALTTAB_DIR}/bin/alttab-free-cert" --status >/dev/null 2>&1; }

# step::alttab::needs_build <reason> <detail>: the verdict for a machine that needs the build. init
# runs it only when nothing in it needs a human: full Xcode selected and the certificate made.
step::alttab::needs_build() {
  local reason="${1}" detail="${2}"
  if ! step::alttab::has_xcode; then
    verdict fail "${reason}" -m -d "${detail}; building it needs full Xcode, and $(xcode-select -p 2>/dev/null || print -r -- 'no developer directory') is selected" \
      -f "install Xcode from the App Store, then: sudo xcode-select -s /Applications/Xcode.app && sudo xcodebuild -license accept && ${CLI_NAME} alttab install"
  elif ! step::alttab::has_cert; then
    verdict fail "${reason}" -m -d "${detail}; the signing certificate '${ALTTAB_IDENTITY}' is not created yet (one macOS admin password dialog)" \
      -f "${CLI_NAME} alttab install"
  else
    verdict fail "${reason}" -d "${detail}" -f "${CLI_NAME} apply alttab"
  fi
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
    step::alttab::needs_build alttab_missing "AltTab is not installed at ${ALTTAB_APP}"
    return 0
  fi
  if step::alttab::has_cask; then
    step::alttab::needs_build alttab_cask "the official alt-tab Homebrew cask is installed; it starts the Pro trial"
    return 0
  fi
  if ! step::alttab::has_cert; then
    step::alttab::needs_build cert_missing "the local signing certificate '${ALTTAB_IDENTITY}' is not created or trusted"
    return 0
  fi
  local sig
  sig="$(codesign -dvvv "${ALTTAB_APP}" 2>&1 || true)"
  if [[ "${sig}" != *"Authority=${ALTTAB_IDENTITY}"* && "${sig}" != *"Signature=adhoc"* ]]; then
    step::alttab::needs_build not_patched "${ALTTAB_APP} is not the patched build (signed by something other than '${ALTTAB_IDENTITY}')"
    return 0
  fi
  local policy auto
  policy="$(defaults read "${ALTTAB_BUNDLE}" updatePolicy 2>/dev/null || echo unset)"
  auto="$(defaults read "${ALTTAB_BUNDLE}" SUEnableAutomaticChecks 2>/dev/null || echo unset)"
  if [[ "${policy}" != 0 || "${auto}" != 0 ]]; then
    step::alttab::needs_build updater_auto "AltTab's updater is not pinned to manual | updatePolicy='${policy}' SUEnableAutomaticChecks='${auto}'"
    return 0
  fi
  verdict ok in_sync -d "patched AltTab installed; updater manual; no Homebrew cask"
}

apply::alttab() {
  step::alttab::paths
  if ! step::alttab::has_cert; then
    print -u2 "[ERROR] alttab certificate missing; init never makes it | fix='${CLI_NAME} alttab install'"
    return 1
  fi
  run_mut zsh "${ALTTAB_DIR}/bin/alttab-free-build"
}
