# step xcode — full Xcode, which the alttab step builds with: AltTab is an Xcode project (no
# Package.swift), and Command Line Tools' xcodebuild cannot build an app bundle. Installed from
# the App Store, selected with xcode-select, license accepted. All three are hand steps (an Apple
# account, then sudo), so the verdicts name the commands and init applies nothing.
step::declare xcode --group tools --desc "full Xcode installed, selected with xcode-select and its license accepted (alttab builds with it)"
step::watches xcode '.config/alttab/**'

check::xcode() {
  if [[ "${OSTYPE}" != darwin* ]]; then
    verdict skip not_macos -d "Xcode is macOS only"
    return 0
  fi
  if [[ ! -d "${HOME}/.config/alttab" ]]; then
    verdict skip not_needed -d "nothing on this machine builds with Xcode (no ~/.config/alttab)"
    return 0
  fi
  local app="${ARI_DOTFILES_XCODE_APP}"
  if [[ ! -d "${app}" ]]; then
    verdict fail xcode_missing -m -d "Xcode is not installed at ${app}; alttab builds with it" \
      -f "open 'macappstores://apps.apple.com/app/id497799835' (or: mas install 497799835)"
    return 0
  fi
  local dev
  dev="$(xcode-select -p 2>/dev/null || true)"
  if [[ "${dev}" != "${app}/Contents/Developer" ]]; then
    verdict fail not_selected -m -d "xcode-select points at ${dev:-nothing}, not ${app}" -f "sudo xcode-select -s ${app}"
    return 0
  fi
  # `xcodebuild -license check` is ~0.4 s: reused while Xcode, its license record and the selection hold.
  cache::check step::xcode::license "${app}/Contents/version.plist" /Library/Preferences/com.apple.dt.Xcode.plist /var/db/xcode_select_link
}

# Xcode's short version from its version.plist, read without a fork; empty when unreadable.
step::xcode::version() {
  local plist="${ARI_DOTFILES_XCODE_APP}/Contents/version.plist" text
  [[ -r "${plist}" ]] || return 0
  text="$(<"${plist}")"
  [[ "${text}" =~ '<key>CFBundleShortVersionString</key>[[:space:]]*<string>([^<]+)</string>' ]] && print -r -- "${match[1]}"
  return 0
}

step::xcode::license() {
  local version; version="$(step::xcode::version)"
  if ! xcodebuild -license check >/dev/null 2>&1; then
    verdict fail license_unaccepted -m -d "Xcode ${version:-?} is selected but its license is not accepted" -f "sudo xcodebuild -license accept"
    return 0
  fi
  verdict ok ready -d "Xcode ${version:-?} selected; license accepted"
}
