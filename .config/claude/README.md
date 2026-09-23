# Claude Code hooks: notifications and the headless-Chrome guard

macOS desktop notifications for Claude Code, with one-click jump back to the
exact tmux pane that fired the notification. Also exposes a programmatic
"click simulator" that Raycast / a hotkey can invoke to dismiss the banner
and run the click action without finding it on screen, plus a
"fire simulator" for testing the pipeline without waiting for Claude Code.

## Layout

```
~/.config/claude/                       # CLAUDE_SCRIPT_ROOT
├── bin/                                # orchestration layer (entry points)
│   ├── notification-fire.sh            # fired by Claude Code's Notification hook
│   ├── notification-fire-simulator.sh  # post a notification with a chosen target
│   ├── notification-click-handler.sh   # invoked when the banner is clicked
│   ├── notification-click-simulator.sh # invoke the click action programmatically
│   ├── quickchat.sh                    # random Rocket League quickchat (CLI toy / fallback msg)
│   ├── pretooluse-headless-chrome-guard.sh  # PreToolUse (Bash) hook: refuses headless Chrome.app
│   └── initialize.sh                   # idempotent setup (brew + both settings.json hooks)
├── lib/                                # implementation layer (sourced)
│   ├── notification-lib.sh             # constants, log, helpers
│   └── tmux-pane.sh                    # tmux_target_pane() — current pane
└── skills/                             # shared-tier Claude skills; ~/.claude/skills/<name> symlinks here
    └── <name>/SKILL.md                 # see skills/ari-dotfiles/SKILL.md, Placement rules
```

`bin/` scripts are tiny orchestrators — they derive `CLAUDE_SCRIPT_ROOT` from
`$0`, source `lib/notification-lib.sh`, and call a few high-level functions.
All real work lives in `lib/`. The `*-fire*` and `*-click*` pairs use the
same lib helpers, so a fired notification and a simulated fire post the
exact same banner; a real click and a simulated click run the exact same
handler.

## Information flow

**Fire** (Claude Code → banner on screen). Claude Code emits a Notification
event to the hook configured in `~/.claude/settings.json`. The hook runs
`bin/notification-fire.sh`, which resolves a message body, looks up the
current tmux pane via `tmux_target_pane`, and calls `post_notification`.
That builds a `terminal-notifier` invocation with `-group claude-notification-<target>`
(per-pane group, so notifications from different panes stack instead of
dismissing each other; a second notification from the same pane still
replaces the first) and `-execute` wired to the click handler with the
target baked in. macOS shows the banner.

**Fire simulation** (manual testing).
`bin/notification-fire-simulator.sh '<target>' '<msg>'` calls the same
`post_notification` helper as `notification-fire.sh`, but takes the target
and message as arguments instead of deriving them. Useful for testing the
click + click-simulator pipeline without waiting for Claude Code to emit a
real Notification event.

**Click** (user clicks the banner). `terminal-notifier` runs the
`-execute` command, which is `bin/notification-click-handler.sh '<target>'`.
The handler activates Terminal.app via `osascript` and calls `tmux_jump`,
which is one `tmux select-window … \; select-pane …` invocation that sets
both the active window and active pane in a single round trip. The target
was baked into `-execute` at fire time, so the handler is stateless.

**Click simulation** (Karabiner / Raycast / hotkey).
`bin/notification-click-simulator.sh` queries `terminal-notifier -list ALL`
for the most-recently-delivered `claude-notification-*` group, dismisses
that one specifically, then invokes `bin/notification-click-handler.sh`
with the target parsed from the group ID. Older claude notifications from
other panes stay in the tray and can be caught by subsequent invocations.
The handler is the single source of truth for "what does a click do" —
both real and simulated clicks go through it.

## Logs

Each script writes a log on every run to its own directory,
`/tmp/claude-notification/<script-basename>/log.txt` (e.g.
`notification-fire/log.txt`, `notification-click-handler/log.txt`). `log_init`
(from `~/.config/zsh/plugins/log_rotate.zsh`) rotates the previous run aside
to `log.txt.bak.1` … `.bak.4` at the start of each run, so the current log plus
4 backups (5 runs) are preserved for comparison instead of truncated. Grouping
each script's runs in their own directory keeps them easy to correlate.

## Setup

`initialize.sh` is idempotent:

1. Installs `terminal-notifier` via Homebrew if missing.
2. Updates `~/.claude/settings.json` so the `Notification` hook points at
   `bin/notification-fire.sh`.
3. Adds a `PreToolUse` hook (matcher `Bash`) running
   `bin/pretooluse-headless-chrome-guard.sh`, gated with
   `"if": "Bash(*--headless*)"`; other `PreToolUse` entries are kept.

It is wired into `new-machine setup` (the `claude_notifications` step)
so a fresh machine gets it as part of the regular bootstrap. Safe to run by
hand any time:

```sh
~/.config/claude/bin/initialize.sh
```

The `claude_notifications` step also runs in the Monday `new-machine verify`
launchd job, so hook drift surfaces in the background. From a shell,
`claude::hook::check` runs that one step read-only and `claude::hook::register`
applies it (both in `~/.config/zsh/plugins/claude.zsh`).

## Headless Chrome guard

`bin/pretooluse-headless-chrome-guard.sh` is a Claude Code `PreToolUse` hook on
the Bash tool. It exits 2, which blocks the call and feeds its stderr back to
Claude, when a command launches the installed Chrome.app headless: the bare
`/Applications/Google Chrome*.app/Contents/MacOS/…` binary (Chrome, Canary,
Beta, Dev) or `open -a "Google Chrome" … --args --headless`. Every such launch
steals focus twice while Chrome is the running browser: opening a page
activates the running Chrome, and about 6 s in the instance asks
LaunchServices to set the https handler, which CoreServicesUIAgent answers by
ordering its windows front (measured 2026-09-23 with an `lsappinfo front`
tracer and the unified log). Playwright's browsers are separate bundles and
are not affected, so the message points at `~/.config/bin/chrome-headless`,
which runs chrome-headless-shell (default) or Google Chrome for Testing
(`--full`) with the same Chromium flags.

`settings.json` gates the hook with `"if": "Bash(*--headless*)"`, so Claude
Code only spawns it for commands that mention `--headless`; the script matches
the hook's JSON as raw text and spawns nothing itself. Pipe-test it by hand:

```sh
jq -nc '{tool_name:"Bash",tool_input:{command:"open -a \"Google Chrome\" --args --headless"}}' \
  | ~/.config/claude/bin/pretooluse-headless-chrome-guard.sh; echo $?   # 2, message on stderr
```

`new-machine check --only claude_notifications` reports the guard missing from
`settings.json` as `guard_mismatch`; `initialize.sh` (or
`new-machine apply claude_notifications`) wires it.

## Karabiner integration

Hyper+N is bound in `~/.config/karabiner/karabiner.ts/src/shortcuts.ts` to
`karabiner.ts/src/scripts/bin/notif-click`, which tries the click simulator
first and falls back to `notif-center` for on-screen and faded banners from
other apps.

`karabiner_script` (in `src/utils/macros.ts`) wraps it so it runs with a
usable PATH under launchd and logs every press to
`/tmp/karabiner.notif-click/log.txt` with an `elapsed_ms` line. After editing,
rebake with `~/.config/karabiner/bin/bake` (or the Hyper-bound
`karabiner-recompile`).

## Raycast integration

Create a Raycast Script Command that invokes the simulator:

```bash
#!/bin/bash
# @raycast.schemaVersion 1
# @raycast.title Jump to waiting Claude
# @raycast.mode silent
# @raycast.packageName Claude

exec "$HOME/.config/claude/bin/notification-click-simulator.sh"
```

Bind a hotkey to it in Raycast.
