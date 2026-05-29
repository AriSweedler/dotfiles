# Claude Code notification scripts

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
│   └── initialize.sh                   # idempotent setup (brew + settings.json)
└── lib/                                # implementation layer (sourced)
    ├── notification-lib.sh             # constants, log, helpers
    └── tmux-pane.sh                    # tmux_target_pane() — current pane
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

It is wired into `~/.config/new-machine.sh` (`ensure_claude_notifications`)
so a fresh machine gets it as part of the regular bootstrap. Safe to run by
hand any time:

```sh
~/.config/claude/bin/initialize.sh
```

## Karabiner integration

Hyper+N is bound in `~/.config/karabiner/karabiner.ts/src/claude-notifications.ts`
to invoke the click simulator. The absolute path to the simulator is baked
at build time, since Karabiner's `shell_command` runs in a minimal sh
context where `$HOME` expansion is unreliable. Re-run `npm run build` (or
`~/.config/karabiner/bin/karabiner-recompile`) after editing.

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
