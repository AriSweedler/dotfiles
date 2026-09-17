# Agent brief: install the Free-tier AltTab on this machine

You are helping a person get a working, permanent Free-tier AltTab on a Mac, using the files in
this directory. Read `README.md` first; it explains why this exists and what a human must do by
hand. This file tells you how to run the process with them.

## Definition of done

All of these are true, and you have verified each with a command, not an assumption:

1. `/Applications/AltTab.app` is the patched build: `codesign -dvvv /Applications/AltTab.app 2>&1`
   shows `Signature=adhoc` (or the `--identity` certificate) and a `CDHash` equal to the `cdhash=`
   line the script printed.
2. AltTab is running from `/Applications`: `ps -o comm= -p "$(pgrep -x AltTab)"`.
3. Spotlight knows exactly one AltTab: `mdfind "kMDItemCFBundleIdentifier == 'com.lwouis.alt-tab-macos'"`.
4. The Homebrew cask is gone: `brew list --cask alt-tab` fails (skip if Homebrew is absent).
5. The updater is manual: `defaults read com.lwouis.alt-tab-macos updatePolicy` prints `0`.
6. Accessibility and Screen Recording are granted to this binary. Verify with the TCC database if
   the terminal has Full Disk Access (see Verification), otherwise by the person confirming the
   switcher opens with thumbnails and no permission prompt appears.

## Ground rules

- The patch keeps Pro features locked. Do not edit it, or anything else, to unlock them.
- Never install AltTab through Homebrew here. The script removes the cask on purpose.
- Permissions cannot be granted from a shell. `tccutil` only resets. The person clicks in
  System Settings; you tell them exactly where and verify afterwards.
- Anything needing `sudo` or a password prompt is theirs to run. In Claude Code, ask them to type
  `! <command>` so the output lands in the session.
- One human step at a time. Say what they will see, what to click, and what to reply. Wait for
  the reply, then verify with a command before the next step.
- Do not commit or push dotfiles changes unless asked.
- Before running the script for real, show the person the `--dry-run` plan and get a yes. It
  quits their window switcher, removes the brew cask, replaces the app, and resets permissions.

## Procedure

### 0. Preflight

Run these and report what you find:

```sh
xcodebuild -version                     # full Xcode required; "xcode-select: error" or CLT-only = not ready
git --version
ls -d /Applications/AltTab.app 2>/dev/null && codesign -dvvv /Applications/AltTab.app 2>&1 | grep -E 'Signature|TeamIdentifier|CDHash'
brew list --cask alt-tab 2>/dev/null && echo "brew cask present"
pgrep -x AltTab && echo running
alttab-free-build --help
```

- `TeamIdentifier=QXD7GW8FHY` means the official build is installed. Expected; the script replaces it.
- If Xcode is missing: ask them to install Xcode from the App Store, then run
  `! sudo xcode-select -s /Applications/Xcode.app` and `! sudo xcodebuild -license accept`.
  Re-run `xcodebuild -version` before continuing.
- If `alttab-free-build` is not on `PATH`, run it as `~/.config/alttab/bin/alttab-free-build`.

### 1. Plan

```sh
alttab-free-build --dry-run
```

Summarize the plan in three lines and ask for a go-ahead.

### 2. Build and install

```sh
alttab-free-build
```

Expect a minute or two of silence during compilation. Parse the trailing `key=value` lines:
`installed`, `permissions_reset`, `cdhash`, `version`, `commit`. If it exits non-zero, go to the
failure playbook; the build log is `~/.cache/alttab-free/src/DerivedData/alttab-free-build.log`.

### 3. Permissions, only if `permissions_reset=true`

AltTab is now open and showing its permissions window. Guide one grant at a time:

1. "Open System Settings > Privacy & Security > Accessibility. Turn on AltTab. If it is not in
   the list, click + and choose /Applications/AltTab.app. Tell me when it is on."
   Verify: AltTab's permissions window drops the Accessibility item, or the TCC check below.
2. "Now Screen Recording, same place. Turn on AltTab. macOS will offer Quit & Reopen; choose it.
   Tell me when AltTab is back."
   If they prefer no thumbnails, the checkbox in AltTab's window skips this step.
3. Verify (below). If the Screen Recording prompt keeps reappearing, see the playbook.

### 4. Verification

Run every check in Definition of done. For the permission rows, test for Full Disk Access first:

```sh
DB="/Library/Application Support/com.apple.TCC/TCC.db"
sqlite3 "$DB" "select count(*) from access;" 2>&1         # a number = readable; an error = no FDA, use the human check instead
sqlite3 "$DB" "select service, auth_value from access where client='com.lwouis.alt-tab-macos';"
```

Both `kTCCServiceAccessibility` and `kTCCServiceScreenCapture` should show `auth_value` `2`. To
confirm they are bound to this binary, decode a row's requirement and look for the new CDHash:

```sh
sqlite3 "$DB" "select hex(csreq) from access where client='com.lwouis.alt-tab-macos' limit 1;" | xxd -r -p > /tmp/req.bin
csreq -r /tmp/req.bin -t        # want: cdhash H"<CDHash from step 2>" ...; a Team ID means stale rows
```

Without Full Disk Access, ask: "Press your AltTab shortcut. Do window thumbnails appear, with no
permission prompt?" A yes closes the loop.

### 5. Report

Tell the person: the version and CDHash installed, what they granted, that the updater is manual
and why they must decline in-app updates, and that re-running the script is safe. If you fell back
to the human check for permissions, say so.

## Failure playbook

| Symptom | Cause | What to do |
|---|---|---|
| `Patch does not apply` | `--ref` newer than `v11.6.1` | Prefer `--ref v11.6.1`. If they want the newer version: check out the tag in the clone, port the six changes listed in `free.patch`'s header by hand, `git diff > free.patch` keeping the header, re-run with `--patch`. Keep Pro locked. |
| Build error about `MACOSX_DEPLOYMENT_TARGET` or deprecations reported as errors | `config/local.xcconfig` missing or overridden | Confirm the file exists in the clone with `MACOSX_DEPLOYMENT_TARGET = 12.0` and `SWIFT_TREAT_WARNINGS_AS_ERRORS = NO`; re-run. |
| `xcodebuild` license or `xcode-select` errors | Xcode not set up | Person runs the two `sudo` commands from Preflight. |
| Screen Recording prompt repeats every few seconds | Permission rows keyed to the previous binary; AltTab re-checks on a timer | Quit AltTab. Run `tccutil reset ScreenCapture com.lwouis.alt-tab-macos` and `tccutil reset Accessibility com.lwouis.alt-tab-macos`. Reopen. Redo step 3. |
| System Settings shows AltTab on, yet it still asks | Same stale rows | Same fix, or have them remove the row with − and add the app again. |
| Two AltTab entries in Spotlight or in System Settings' app list | Build-folder copy still present | `rm -rf ~/.cache/alttab-free/src/DerivedData/Build/Products/Release/AltTab.app`. |
| A Keychain password prompt at launch | Should not happen; the patch skips the Keychain | Have them click Deny or Cancel, note it, and report it. Do not enter a password. |
| Switcher size or style changed on its own | Pro values downgrade to Free on lock | Expected. They pick a Free value in Settings. |
| AltTab offers an update | Updater not pinned, or they clicked Check for updates | Decline. `defaults write com.lwouis.alt-tab-macos updatePolicy -string 0`. |

## Phrasing the human steps

Short, one action, concrete: where to click, what they will see, what to say back. Example:

> Open System Settings, then Privacy & Security, then Accessibility. Find AltTab in the list and
> switch it on. If it is missing, click the plus button and choose AltTab from Applications.
> Reply "on" when done.

Then verify with a command before moving on.
