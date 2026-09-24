# Agent brief: install the Free-tier AltTab on this machine

You are helping a person get a working, permanent Free-tier AltTab on a Mac, using the files in
this directory. Read `README.md` first; it explains why this exists and what a human must do by
hand. This file tells you how to run the process with them.

## Definition of done

All of these are true, and you have verified each with a command, not an assumption:

1. `/Applications/AltTab.app` is the patched build: `codesign -dvvv /Applications/AltTab.app 2>&1`
   shows `Authority=AltTab Free Local` (or `Signature=adhoc` if `--identity -` was used) and a
   `CDHash` equal to the `cdhash=` line the script printed.
2. AltTab is running from `/Applications`: `ps -o comm= -p "$(pgrep -x AltTab)"`.
3. Spotlight knows exactly one AltTab: `mdfind "kMDItemCFBundleIdentifier == 'com.lwouis.alt-tab-macos'"`.
4. The Homebrew cask is gone: `brew list --cask alt-tab` fails (skip if Homebrew is absent).
5. The updater is manual: `defaults read com.lwouis.alt-tab-macos updatePolicy` prints `0` AND
   `defaults read com.lwouis.alt-tab-macos SUEnableAutomaticChecks` prints `0`. AltTab copies
   `updatePolicy` from Sparkle's `SUEnableAutomaticChecks` on launch, so the first alone drifts
   back to auto-check and the update window returns.
6. Accessibility and Screen Recording are granted to this binary. Verify with the TCC database if
   the terminal has Full Disk Access (see Verification), otherwise by the person confirming the
   switcher opens with thumbnails and no permission prompt appears.
7. The local signing certificate exists and is trusted:
   `zsh ~/.config/alttab/bin/alttab-free-cert --status` exits 0 and prints its `sha1=`.

## Ground rules

- The patch keeps Pro features locked, with one deliberate exception: shortcut slot 2 (⌥`,
  windows of the active app), which is AltTab's own default. Do not edit it, or anything else,
  to unlock more.
- Never install AltTab through Homebrew here. The script removes the cask on purpose.
- Permissions cannot be granted from a shell. `tccutil` only resets. The person clicks in
  System Settings; you tell them exactly where and verify afterwards.
- Anything needing `sudo` or a password prompt is theirs to run. In Claude Code, ask them to type
  `! <command>` so the output lands in the session.
- The certificate step pops a system password dialog. Do not trigger it from your shell: the
  person runs `! zsh ~/.config/alttab/bin/alttab-free-cert` themselves, after you have told them
  what the dialog will say. A dialog that appears with no warning gets cancelled.
- One human step at a time. Say what they will see, what to click, and what to reply. Wait for
  the reply, then verify with a command before the next step.
- Do not commit or push dotfiles changes unless asked.
- Before running the script for real, show the person the `--dry-run` plan and get a yes. It
  quits their window switcher, removes the brew cask, replaces the app, and resets permissions.
- `--build-only` is safe to run yourself: nothing installed, nothing quit. It leaves a second
  `AltTab.app` in DerivedData that Spotlight lists until it is installed or deleted; delete it
  when you are done testing (path in the Failure playbook).

## Procedure

### 0. Preflight

Run these and report what you find:

```sh
xcodebuild -version                     # full Xcode required; "xcode-select: error" or CLT-only = not ready
git --version
ls -d /Applications/AltTab.app 2>/dev/null && codesign -dvvv /Applications/AltTab.app 2>&1 | grep -E 'Signature|TeamIdentifier|CDHash'
brew list --cask alt-tab 2>/dev/null && echo "brew cask present"
pgrep -x AltTab && echo running
zsh ~/.config/alttab/bin/alttab-free-cert --status   # exit 0 = certificate present and trusted
alttab-free-build --help
cat ~/.config/alttab/free.patch.ref     # the upstream tag the patch targets; the script's default --ref
```

- `TeamIdentifier=QXD7GW8FHY` means the official build is installed. Expected; the script replaces it.
- If Xcode is missing: ask them to install Xcode from the App Store, then run
  `! sudo xcode-select -s /Applications/Xcode.app` and `! sudo xcodebuild -license accept`.
  Re-run `xcodebuild -version` before continuing.
- If `alttab-free-build` is not on `PATH`, run it as `~/.config/alttab/bin/alttab-free-build`.

### 1. Certificate, only if `--status` exited 1

Explain first, then have them run it:

> The build is signed with a local certificate so macOS remembers the permissions across
> rebuilds. Creating it needs your Mac password once. Run
> `! zsh ~/.config/alttab/bin/alttab-free-cert`. A dialog will say that "security" wants to
> change your Certificate Trust Settings. Enter your password and confirm. Reply "done".

Verify: `zsh ~/.config/alttab/bin/alttab-free-cert --status` exits 0. If their output ends in
`The authorization was canceled by the user`, the certificate is imported but untrusted; the
same command re-applies trust only. Skip the certificate with `--identity -` only if they prefer
re-granting permissions after every rebuild.

### 2. Plan

```sh
alttab-free-build --dry-run
```

Summarize the plan in three lines and ask for a go-ahead.

### 3. Build and install

```sh
alttab-free-build
```

Expect a minute or two of silence during compilation (about 70 s on an M4 Max; the DerivedData
under `~/.cache/swift/derived/alttab-free` is kept between runs, but xcodebuild's fixed work
dominates, so a rebuild is not much faster than the first build). During the first build Keychain
may ask whether `codesign` may use the "AltTab Free Local" key; they choose Always Allow. Parse the
trailing `key=value` lines: `installed`, `permissions_reset`, `identity`, `cdhash`, `version`,
`commit`. If it exits non-zero, go to the failure playbook; the build log is
`~/.cache/swift/derived/alttab-free/alttab-free-build.log`.

### 4. Permissions, only if `permissions_reset=true`

This happens once per machine; later rebuilds keep the grants. AltTab is now open and showing
its permissions window. Guide one grant at a time:

1. "Open System Settings > Privacy & Security > Accessibility. Turn on AltTab. If it is not in
   the list, click + and choose /Applications/AltTab.app. Tell me when it is on."
   Verify: AltTab's permissions window drops the Accessibility item, or the TCC check below.
2. "Now Screen Recording, same place. Turn on AltTab. macOS will offer Quit & Reopen; choose it.
   Tell me when AltTab is back."
   If they prefer no thumbnails, the checkbox in AltTab's window skips this step.
3. Verify (below). If the Screen Recording prompt keeps reappearing, see the playbook.

### 5. Verification

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
csreq -r /tmp/req.bin -t        # want: identifier "com.lwouis.alt-tab-macos" and certificate leaf = H"<sha1 from --status, lowercase>"
                                # cdhash H"..." = an ad-hoc build's row; a Team ID = the official build's stale row
```

Without Full Disk Access, ask: "Press your AltTab shortcut. Do window thumbnails appear, with no
permission prompt?" A yes closes the loop.

### 6. Report

Tell the person: the version and CDHash installed, what they granted, that the updater is manual
and why they must decline in-app updates, and that re-running the script is safe and keeps the
permissions because the certificate does not change. If you fell back to the human check for
permissions, say so.

## Upstream released a new version

The signal is usually AltTab's own update window ("11.7.1 is available"). The person declines
it: accepting would replace the patched build with the stock one. The rebuild is theirs to
finish; the patch move is yours.

1. Confirm the release and the current base:
   `gh api repos/lwouis/alt-tab-macos/releases/latest --jq .tag_name` and
   `cat ~/.config/alttab/free.patch.ref`.
2. Move the patch. This works in a throwaway worktree beside the clone, never in `/Applications`:
   ```sh
   alttab-free-build --rebase-patch vX.Y.Z
   ```
   It commits `free.patch` on top of its current base tag, runs `git rebase` onto the new tag (a
   three-way merge, which follows moved context that a plain `git apply` rejects), and on success
   rewrites `free.patch` (header `Base:` line included) and `free.patch.ref`, then removes the
   worktree.
3. If it stops on conflicts, it names the files and leaves the worktree at
   `~/.cache/alttab-free/rebase`. Resolve each conflict yourself, keeping the patch's intent:
   Pro stays locked apart from shortcut slot 2. The usual shape is upstream adding lines at the
   top of a function the patch gutted (a `#if DEBUG` mock hook, a new guard): keep upstream's new
   lines and the patch's replacement body, with an explicit `return` where the patch relied on a
   single-expression body. Then run the three commands the script printed (`git add`, the
   `rebase --continue` with `GIT_EDITOR=true`, `alttab-free-build --finish-patch`).
4. Prove it builds without installing: `alttab-free-build --build-only --identity -` (about 70 s).
   Read `free.patch`'s header and the hunk list (`grep -E '^\+\+\+|^@@' free.patch`) and check the
   "What it changes" list still matches what the hunks do.
5. The person installs: `alttab-free-build` (Procedure steps 2 to 6; permissions survive because
   the certificate is unchanged). Delete the build-only bundle first if it is still there.
6. Commit `free.patch`, `free.patch.ref` and anything else that changed on the shared tier
   (`git df add …; git df commit`), only when asked; the push is the person's.

If the rebase applies cleanly but the build then fails, the conflict was semantic. Read the
`error:` lines in the build log and fix the files in the clone at `~/.cache/alttab-free/src`,
which the build left at the new tag with the patch applied. Then regenerate the patch from the
clone, keeping the prose header: `{ sed -n '1,/^diff --git/p' free.patch | sed '$d';
git -C ~/.cache/alttab-free/src diff; } > free.patch.new && mv free.patch.new free.patch`.
`free.patch.ref` already names the new tag.

## Failure playbook

| Symptom | Cause | What to do |
|---|---|---|
| `Patch does not apply` | `--ref` is not the tag in `free.patch.ref` | Build the default ref, or move the patch first: **Upstream released a new version**. |
| `Rebase stopped on conflicts` | upstream changed a patched function | Resolve in `~/.cache/alttab-free/rebase` per **Upstream released a new version** step 3, then `--finish-patch`. |
| `No patch rebase in progress` from `--finish-patch` | the worktree is gone or `--rebase-patch` never ran | Run `--rebase-patch vX.Y.Z` again. |
| Build error about `MACOSX_DEPLOYMENT_TARGET` or deprecations reported as errors | `config/local.xcconfig` missing or overridden | Confirm the file exists in the clone with `MACOSX_DEPLOYMENT_TARGET = 12.0` and `SWIFT_TREAT_WARNINGS_AS_ERRORS = NO`; re-run. |
| `xcodebuild` license or `xcode-select` errors | Xcode not set up | Person runs the two `sudo` commands from Preflight. |
| `No signing certificate "AltTab Free Local" found` or `ambiguous` during the build | Certificate missing, untrusted, or duplicated | `zsh ~/.config/alttab/bin/alttab-free-cert --status`. Missing or untrusted: step 1. Duplicated: the person deletes the extras in Keychain Access. |
| `The authorization was canceled by the user` | Trust dialog dismissed | Explain the dialog; the person re-runs `! zsh ~/.config/alttab/bin/alttab-free-cert`. It only re-applies trust. |
| `errSecInternalComponent` during the build, or a Keychain dialog about `codesign` | Keychain blocks codesign's use of the key | The person chooses Always Allow. Without a dialog: Keychain Access > login > Keys > AltTab Free Local > Access Control > allow all applications; rebuild. |
| Screen Recording prompt repeats every few seconds | Permission rows keyed to a previous signature (ad-hoc or Homebrew build); AltTab re-checks on a timer | Quit AltTab. Run `tccutil reset ScreenCapture com.lwouis.alt-tab-macos` and `tccutil reset Accessibility com.lwouis.alt-tab-macos`. Reopen. Redo step 4. |
| System Settings shows AltTab on, yet it still asks | Same stale rows | Same fix, or have them remove the row with − and add the app again. |
| Two AltTab entries in Spotlight or in System Settings' app list | A `--build-only` bundle still present | `rm -rf ~/.cache/swift/derived/alttab-free/Build/Products/Release/AltTab.app`. |
| A Keychain password prompt at launch | Should not happen; the patch skips the Keychain | Have them click Deny or Cancel, note it, and report it. Do not enter a password. |
| Switcher size or style changed on its own | Pro values downgrade to Free on lock | Expected. They pick a Free value in Settings. |
| AltTab offers an update | Upstream released; or the pin drifted (a build before 2026-09-24 pinned only `updatePolicy`, which AltTab resets from Sparkle's `SUEnableAutomaticChecks` on launch); or they clicked Check for updates | Decline. Move the patch (**Upstream released a new version**). Re-pin with the app quit: `defaults write com.lwouis.alt-tab-macos updatePolicy -string 0; defaults write com.lwouis.alt-tab-macos SUEnableAutomaticChecks -bool false; defaults write com.lwouis.alt-tab-macos SUAutomaticallyUpdate -bool false` (the install step does this). |

## Phrasing the human steps

Short, one action, concrete: where to click, what they will see, what to say back. Example:

> Open System Settings, then Privacy & Security, then Accessibility. Find AltTab in the list and
> switch it on. If it is missing, click the plus button and choose AltTab from Applications.
> Reply "on" when done.

Then verify with a command before moving on.
