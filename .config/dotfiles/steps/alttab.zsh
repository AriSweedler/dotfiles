# step alttab — the Free-tier AltTab built from source (~/.config/alttab/bin/alttab-free-build).
# The check reads the machine: the app is the patched build (signed with the local certificate),
# the updater is pinned to manual, and the Homebrew cask is gone. The apply runs the build, which
# quits and replaces /Applications/AltTab.app. The local signing certificate is a human step: its
# creation pops a system password dialog, so init never makes it: until it exists, and while full
# Xcode is not selected, a needed build is a manual fail naming `dotfiles alttab install`.
# free.patch documents itself: its header's "What it changes" list names every file it touches,
# or the step fails by hand, naming `dotfiles alttab edit --header`.
step::declare alttab --group tools --desc "AltTab, the Free-tier build from source: patched app installed, updater manual, no Homebrew cask; free.patch's header names every file it changes (~/.config/alttab)"
step::watches alttab '.config/alttab/**'

step::alttab::paths() {
  ALTTAB_DIR="${HOME}/.config/alttab"
  ALTTAB_PATCH="${ALTTAB_DIR}/free.patch"
  ALTTAB_SRC="${XDG_CACHE_HOME:-${HOME}/.cache}/alttab-free/src"   # alttab-free-build's clone
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

# step::alttab::xcode_state: REPLY is what stands between this Mac and an AltTab build, the first
# of: none (no Xcode app at ARI_DOTFILES_XCODE_APP; Command Line Tools alone cannot build a macOS
# app), not_selected (xcode-select points elsewhere), license (not accepted), first_launch (its
# first-launch packages, which a new or updated Xcode may need to build, are not installed); else
# ok. The xcode step reports the first three on every run; this asks only when a build is needed
# (about 0.3 s). XCODE_APP is the app's path.
step::alttab::xcode_state() {
  typeset -g XCODE_APP="${ARI_DOTFILES_XCODE_APP}"
  REPLY=none
  [[ -d "${XCODE_APP}" ]] || return 0
  REPLY=not_selected
  [[ "$(xcode-select -p 2>/dev/null)" == "${XCODE_APP}/Contents/Developer" ]] || return 0
  REPLY=license
  xcodebuild -license check >/dev/null 2>&1 || return 0
  REPLY=first_launch
  xcodebuild -checkFirstLaunchStatus >/dev/null 2>&1 || return 0
  REPLY=ok
}

# step::alttab::undocumented <patch>: reply is each file the patch touches, as its basename
# without .swift, that is not the first word of a line in the header's "What it changes" list
# (the lines after that heading, up to a blank line or the first diff). Reads the file only.
step::alttab::undocumented() {
  local patch="${1}" line name
  local -i in_list=0 items=0
  local -A named=()
  local -a touched=() words
  typeset -gUa reply=()
  [[ -r "${patch}" ]] || return 0
  for line in "${(@f)$(<"${patch}")}"; do
    if [[ "${line}" == 'diff --git '* ]]; then
      in_list=0
      name="${${line##* b/}:t}"
      touched+=("${name%.swift}")
      continue
    fi
    if [[ "${line}" == 'What it changes'* ]]; then in_list=1; continue; fi
    (( in_list )) || continue
    words=(${=line})
    if (( ${#words} == 0 )); then (( items )) && in_list=0; continue; fi
    named[${words[1]}]=1
    (( ++items ))
  done
  for name in "${touched[@]}"; do
    (( ${+named[${name}]} )) || reply+=("${name}")
  done
}

step::alttab::has_cert() { zsh "${ALTTAB_DIR}/bin/alttab-free-cert" --status >/dev/null 2>&1; }

# step::alttab::needs_build <reason> <detail>: the verdict for a machine that needs the build. init
# runs it only when nothing in it needs a human: Xcode ready and the certificate made. Anything
# else is a manual fail; `dotfiles alttab install` does all of it but fetching Xcode itself.
step::alttab::needs_build() {
  local reason="${1}" detail="${2}" REPLY
  step::alttab::xcode_state
  case "${REPLY}" in
    none)
      verdict fail "${reason}" -m -d "${detail}; building it needs the Xcode app, not only Command Line Tools, and none is at ${XCODE_APP}" \
        -f "install Xcode (open 'macappstores://apps.apple.com/app/id497799835', or: mas install 497799835), then ${CLI_NAME} alttab install" ;;
    not_selected)
      verdict fail "${reason}" -m -d "${detail}; ${XCODE_APP} is installed but $(xcode-select -p 2>/dev/null || print -r -- 'nothing') is selected" -f "${CLI_NAME} alttab install" ;;
    license)
      verdict fail "${reason}" -m -d "${detail}; the Xcode license is not accepted" -f "${CLI_NAME} alttab install" ;;
    first_launch)
      verdict fail "${reason}" -m -d "${detail}; Xcode's first-launch packages are not installed" -f "${CLI_NAME} alttab install" ;;
    *)
      if ! step::alttab::has_cert; then
        verdict fail "${reason}" -m -d "${detail}; the signing certificate '${ALTTAB_IDENTITY}' is not created yet (one macOS admin password dialog)" \
          -f "${CLI_NAME} alttab install"
      else
        verdict fail "${reason}" -d "${detail}" -f "${CLI_NAME} apply alttab"
      fi ;;
  esac
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
  local -a reply
  step::alttab::undocumented "${ALTTAB_PATCH}"
  if (( ${#reply} )); then
    verdict fail patch_undocumented -m \
      -d "free.patch changes ${(j:, :)reply}, which its header's 'What it changes' list does not name (each file's name without .swift, first on its line)" \
      -f "${CLI_NAME} alttab edit --header"
    return 0
  fi
  verdict ok in_sync -d "patched AltTab installed; updater manual; no Homebrew cask; free.patch documented"
}

apply::alttab() {
  step::alttab::paths
  if ! step::alttab::has_cert; then
    print -u2 "[ERROR] alttab certificate missing; init never makes it | fix='${CLI_NAME} alttab install'"
    return 1
  fi
  run_mut zsh "${ALTTAB_DIR}/bin/alttab-free-build"
}
