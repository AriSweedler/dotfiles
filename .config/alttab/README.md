# AltTab, Free tier, built from source

The official AltTab (`brew install --cask alt-tab`) starts a 14-day Pro trial on first launch,
with no way to opt out, then shows upgrade prompts on days 1, 4, 12, 15, 21 and 35. On day 15
any Pro setting you picked silently reverts. This folder builds AltTab from its GPL-3.0 source
with a small patch that makes it the permanent Free tier from the first launch: no trial, no
prompts, Pro features locked. Nothing is unlocked.

## Files

| File | Purpose |
|---|---|
| `bin/alttab-free-build` | Clones upstream, applies the patch, builds, installs, fixes permissions. On `PATH` via `~/.config/bin`. |
| `free.patch` | The source change. Its header lists exactly what it alters. Targets upstream tag `v11.6.1`. |
| `README.md` | This file. |
| `AGENTS.md` | Instructions for an LLM agent doing this on a new machine with you. |

## Before you run it

- macOS 12 or newer.
- Full Xcode from the App Store. Command Line Tools alone cannot build a macOS app.
  First time only, run both and enter your password:

  ```sh
  sudo xcode-select -s /Applications/Xcode.app
  sudo xcodebuild -license accept
  ```

- If the Homebrew AltTab is installed, the script uninstalls it so `brew upgrade` can never swap
  the Pro build back in. Your AltTab settings are kept.

## Run it

```sh
alttab-free-build
```

It takes a minute or two, most of it compiling. The script:

1. Clones `lwouis/alt-tab-macos` into `~/.cache/alttab-free/src` (or reuses it) at tag `v11.6.1`.
2. Applies `free.patch`.
3. Writes `config/local.xcconfig`: ad-hoc signature, macOS 12 deployment target, upstream
   deprecation warnings not treated as errors.
4. Builds the Release scheme and verifies the signature and bundle id.
5. Quits AltTab, removes the Homebrew cask, replaces `/Applications/AltTab.app`, and deletes the
   build-folder copy so Spotlight sees one AltTab.
6. Sets the in-app updater to manual. The official update feed would reinstall Pro.
7. Resets the Accessibility and Screen Recording records if the app's code requirement changed.
8. Opens the app.

It prints `key=value` lines at the end. `permissions_reset=true` means step 9 below is needed.

## What you do by hand

macOS will not let a script grant permissions. When AltTab opens its permissions window:

1. System Settings > Privacy & Security > **Accessibility**: turn AltTab on. If it is not listed,
   click **+** and pick `/Applications/AltTab.app`.
2. **Screen Recording**: turn AltTab on, then choose **Quit & Reopen** when macOS asks.
   You can skip this one with the checkbox in AltTab's window. You lose live thumbnails.
3. Never accept an in-app update. **Check for updates…** in the menu offers the official Pro build.

That is all. Re-running the script later is safe: an identical build is not reinstalled and your
permissions stay put.

## Why permissions need redoing after a rebuild

macOS stores each grant together with the app's code requirement. An ad-hoc signature's
requirement is the binary's hash, so every rebuild, even in a different folder, is a new app to macOS. Toggling the old row
in System Settings does nothing, and AltTab re-asks for Screen Recording every 5 seconds until a
valid grant exists. The script clears the stale rows so a fresh grant sticks.

To grant once and keep it across rebuilds, create the local certificate the upstream repo
provides (one admin password prompt to trust it), then build with it:

```sh
cd ~/.cache/alttab-free/src && scripts/codesign/setup_local.sh
alttab-free-build --identity "Local Self-Signed"
```

## Updating to a newer AltTab

```sh
alttab-free-build --ref v11.7.0
```

If the patch no longer applies, the script stops and says so. Regenerate it: check out the new
tag in the clone, make the changes the header of `free.patch` describes, then
`git diff > ~/.config/alttab/free.patch` and paste the header back on top. Do not widen the patch
to unlock Pro features.

## If something is off

| Symptom | Cause | Fix |
|---|---|---|
| Screen Recording prompt keeps popping up | Permission rows keyed to the previous binary | Quit AltTab, run `tccutil reset ScreenCapture com.lwouis.alt-tab-macos` and `tccutil reset Accessibility com.lwouis.alt-tab-macos`, reopen, grant again |
| System Settings shows AltTab on, but it still asks | Same stale rows | Same fix, or remove the row with **−** and add the app again |
| Two AltTabs in Spotlight | Build-folder copy left behind | `rm -rf ~/.cache/alttab-free/src/DerivedData/Build/Products/Release/AltTab.app` |
| Build fails | See `~/.cache/alttab-free/src/DerivedData/alttab-free-build.log` | Deployment-target and deprecation errors mean `config/local.xcconfig` was not written |
| Switcher size or style changed on its own | Auto size, App Icons and Titles styles are Pro | Expected. Pick a Free value in Settings |

Check what is installed:

```sh
codesign -dvvv /Applications/AltTab.app 2>&1 | grep -E 'CDHash|Signature'
```

`Signature=adhoc` is this build. A `TeamIdentifier=QXD7GW8FHY` line means the official build is back.

## Free vs Pro, so you know what to expect

Free: Thumbnails style, Shortcut 1, fixed switcher sizes, all filters, window previews, gestures,
per-app exceptions, switching across Spaces.

Pro, shown with a badge and locked: App Icons and Titles styles, Search, Auto size, Shortcuts 2 to 9.
