# AltTab, Free tier, built from source

The official AltTab (`brew install --cask alt-tab`) starts a 14-day Pro trial on first launch,
with no way to opt out, then shows upgrade prompts on days 1, 4, 12, 15, 21 and 35. On day 15
any Pro setting you picked silently reverts. This folder builds AltTab from its GPL-3.0 source
with a small patch that makes it the permanent Free tier from the first launch: no trial, no
prompts, Pro features locked, with one deliberate exception. The second shortcut slot, AltTab's
own default of ⌥` for switching between the active app's windows, works. Slots 3 to 9, Search,
and the Pro appearance options stay locked.

## Files

| File | Purpose |
|---|---|
| `bin/alttab-free-build` | Clones upstream, applies the patch, builds, installs, fixes permissions. On `PATH` via `~/.config/bin`. Also moves the patch to a new upstream tag (`--rebase-patch`). |
| `bin/alttab-free-cert` | Creates and trusts the local code-signing certificate the build is signed with, once per machine. Called by the build script; safe to run by hand. |
| `free.patch` | The source change. Its header lists exactly what it alters and the upstream tag it targets (`Base:` line). |
| `free.patch.ref` | That tag on its own, one line; the script's default `--ref`. `--rebase-patch` rewrites both files together. |
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
- The first run creates a local code-signing certificate, and macOS asks for an administrator
  password once to trust it for code signing. See "Why permissions survive rebuilds" below.

## Run it

```sh
alttab-free-build
```

It takes a minute or two, most of it xcodebuild. The script:

1. Makes sure the local code-signing certificate `AltTab Free Local` exists and is trusted
   (`bin/alttab-free-cert`). First time only: it is generated into your login keychain and macOS
   asks for an administrator password to trust it. Every later run finds it and moves on.
2. Clones `lwouis/alt-tab-macos` into `~/.cache/alttab-free/src` (or reuses it) at the tag in
   `free.patch.ref`.
3. Applies `free.patch`.
4. Writes `config/local.xcconfig`: sign with that certificate, macOS 12 deployment target,
   upstream deprecation warnings not treated as errors.
5. Builds the Release scheme into `~/.cache/swift/derived/alttab-free` (kept between runs) and
   verifies the signature and bundle id.
6. Quits AltTab, removes the Homebrew cask, replaces `/Applications/AltTab.app`, and deletes the
   build-folder copy so Spotlight sees one AltTab.
7. Sets the in-app updater to manual, both AltTab's `updatePolicy` and Sparkle's
   `SUEnableAutomaticChecks` and `SUAutomaticallyUpdate`; AltTab copies the first from the second
   on launch, so one alone does not hold. The official update feed would reinstall Pro.
8. Resets the Accessibility and Screen Recording records if the app's code requirement changed.
   With the certificate it does not change between rebuilds, so this happens on the first
   install and then only if you switch signing identity.
9. Opens the app.

It prints `key=value` lines at the end. `permissions_reset=true` means the steps below are needed.

## What you do by hand

macOS will not let a script grant permissions. When AltTab opens its permissions window:

1. System Settings > Privacy & Security > **Accessibility**: turn AltTab on. If it is not listed,
   click **+** and pick `/Applications/AltTab.app`.
2. **Screen Recording**: turn AltTab on, then choose **Quit & Reopen** when macOS asks.
   You can skip this one with the checkbox in AltTab's window. You lose live thumbnails.
3. Never accept an in-app update. **Check for updates…** in the menu offers the official Pro build.

That is all, once per machine. Re-running the script later, including for a newer AltTab
version, keeps the grants: the certificate makes every rebuild the same app to macOS.

If Keychain asks whether `codesign` may use the "AltTab Free Local" key during the first build,
choose **Always Allow**.

## Why permissions survive rebuilds

macOS stores each grant together with the app's designated code requirement and checks the
running binary against it. Signed with the local certificate, AltTab's requirement is

```
identifier "com.lwouis.alt-tab-macos" and certificate leaf = H"<sha1 of the certificate>"
```

Every rebuild signed with the same certificate satisfies it, so the grants stay valid. The
certificate lives in your login keychain, is trusted for code signing only, and is valid for ten
years. `zsh ~/.config/alttab/bin/alttab-free-cert --status` prints its SHA-1, keychain, validity
dates, trust state, the requirement above, and whether the installed app is signed by it.

An ad-hoc build (`alttab-free-build --identity -`) has the requirement `cdhash H"<hash of the
binary>"` instead, so every rebuild is a new app to macOS: toggling the old row in System
Settings does nothing and AltTab re-asks for Screen Recording every 5 seconds until a valid grant
exists. The script clears the stale rows whenever the requirement changes so a fresh grant sticks.

Certificates are per machine. On a new Mac the first run creates one there, and you grant once
there. To start over on this machine:

```sh
security find-certificate -c "AltTab Free Local" -p > /tmp/c.pem && sudo security remove-trusted-cert -d /tmp/c.pem
security delete-identity -c "AltTab Free Local"
```

The next `alttab-free-build` creates a new certificate, and you grant once more.

## Updating to a newer AltTab

When AltTab's own update window appears, decline it, then move the patch to the new tag:

```sh
alttab-free-build --rebase-patch v11.7.1     # commits free.patch on its base tag, git-rebases it onto v11.7.1
alttab-free-build --build-only               # prove it builds; installs nothing
alttab-free-build                            # install; permissions survive (same certificate)
```

The rebase is a three-way merge, so it follows code that merely moved. When upstream changed a
line the patch also changes, it stops, names the files, and leaves a worktree at
`~/.cache/alttab-free/rebase`. Resolve the conflicts there (keep Pro locked; only shortcut slot 2
is allowed), run the `git add` and `git rebase --continue` it printed, then
`alttab-free-build --finish-patch` rewrites `free.patch` and `free.patch.ref` and removes the
worktree. `AGENTS.md` has the step-by-step for an agent.

## If something is off

| Symptom | Cause | Fix |
|---|---|---|
| Screen Recording prompt keeps popping up | Permission rows keyed to a previous signature (an ad-hoc or Homebrew build) | Quit AltTab, run `tccutil reset ScreenCapture com.lwouis.alt-tab-macos` and `tccutil reset Accessibility com.lwouis.alt-tab-macos`, reopen, grant again |
| Build fails: `No signing certificate "AltTab Free Local" found`, or `ambiguous` | Certificate missing, untrusted, or duplicated | `zsh ~/.config/alttab/bin/alttab-free-cert --status`. Missing or untrusted: run it without `--status` and approve the password dialog. Duplicated: delete the extras in Keychain Access |
| `The authorization was canceled by the user` | The trust dialog was dismissed | Run `zsh ~/.config/alttab/bin/alttab-free-cert` again; it only re-applies trust |
| Build fails with `errSecInternalComponent`, or a Keychain dialog asks about `codesign` | Keychain will not let codesign use the key silently | Choose **Always Allow** in the dialog. Without a dialog: Keychain Access > login > Keys > "AltTab Free Local" > Access Control > allow all applications, then rebuild |
| System Settings shows AltTab on, but it still asks | Same stale rows | Same fix, or remove the row with **−** and add the app again |
| Two AltTabs in Spotlight | A `--build-only` copy left behind | `rm -rf ~/.cache/swift/derived/alttab-free/Build/Products/Release/AltTab.app` |
| Build fails | See `~/.cache/swift/derived/alttab-free/alttab-free-build.log` | Deployment-target and deprecation errors mean `config/local.xcconfig` was not written |
| `Patch does not apply` | `--ref` is not the tag in `free.patch.ref` | Move the patch first: "Updating to a newer AltTab" |
| Switcher size or style changed on its own | Auto size, App Icons and Titles styles are Pro | Expected. Pick a Free value in Settings |
| ⌥` does nothing | A build from before slot 2 was allowed, or slot 2 was removed in Settings | Rebuild with `alttab-free-build`. In Settings > Controls, the **+** button re-adds slot 2; set it to hold ⌥, press `, "Active app" |

Check what is installed:

```sh
codesign -dvvv /Applications/AltTab.app 2>&1 | grep -E 'CDHash|Signature|Authority|TeamIdentifier'
```

`Authority=AltTab Free Local` is this build. `Signature=adhoc` is an ad-hoc build (`--identity -`),
which loses its permissions on every rebuild. `TeamIdentifier=QXD7GW8FHY` means the official build
is back.

## Free vs Pro, so you know what to expect

Free: Thumbnails style, Shortcut 1 (⌥⇥, all apps), fixed switcher sizes, all filters, window
previews, gestures, per-app exceptions, switching across Spaces.

Unlocked by this patch on purpose: Shortcut 2 (⌥`, windows of the active app). It is what AltTab
configures by default; the official Free tier blocks it at the key press.

Pro, shown with a badge and locked: App Icons and Titles styles, Search, Auto size, Shortcuts 3 to 9.
