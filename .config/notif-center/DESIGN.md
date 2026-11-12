# notif-center — read and click macOS notifications

A small CLI that lists the notifications currently in the macOS tray and clicks
one — triggering its native action (open the Slack message, the Calendar event,
the Claude session) and dismissing it. It backs two keybindings:

- **Hyper+C** → jump to the newest Slack notification.
- **Hyper+N** → jump to the newest Claude Code notification.

## What we wanted

One keystroke that takes you straight to whatever just pinged you, from any app,
without hunting through the tray with the mouse. And a plain CLI underneath, so
the behavior is scriptable and debuggable outside of Karabiner.

## How it works

macOS gives no public API for notifications, so the tool leans on two facts:

1. **Clicking** a live notification — firing its real action — is only possible
   through the Accessibility (AX) API, by driving the `NotificationCenter`
   process and pressing the notification element.
2. The AX tree shows a notification's **text** but not **which app posted it**.
   The only source of app identity is the Notification Center database.

So the two halves play to their strengths: reads come from the database (fast,
and it knows the posting app), clicks go through AX. `--app slack` bridges them —
the database picks the newest notification from that app, AX clicks it.

```
notif-center list  [--app PAT] [--match PAT] [--all] [--output json|human]
notif-center click [N] [--app PAT] [--match PAT]
notif-center os
```

The database is never modified — reads run against a throwaway copy.

## Permissions

- **Reading** the notification database needs **Full Disk Access**.
- **Clicking** through AX needs **Accessibility**.

Run from a terminal, both usually come for free. Under Karabiner the keybindings
run as `karabiner_console_user_server`, which must be granted both itself — see
`set-fda-perms` and the `notif-click-slack` handler, which surface a missing
grant instead of failing silently.

## Running fast

Every AX read is a round-trip into NotificationCenter, so the cost of a click is
how many reads it makes and what each one pays:

- **List from the database, not AX.** A database read is ~0.1s regardless of how
  many notifications are present; the equivalent AX walk is multiple seconds.
- **Skip the list on the hot path.** "Click the newest" needs no enumeration —
  it presses the top notification directly. Only filtered clicks (`--app` /
  `--match`) pay to read text.
- **Read AX natively.** `notif-ax` (`ax/notif-ax.swift`, built into the package's
  `libexec/`) calls the Accessibility API directly. `osascript` pays ~56ms to
  start and then routes every read through System Events.

## Engines

Two engines run the same layout and return the same result line (`ok`,
`notfound:<n>`, `notfound`, `fail: <why>`):

- **notif-ax**, native, used whenever it is installed and trusted.
- **AppleScript** templates in `bin/notif-center`, rendered from the layout. They
  run when `notif-ax` is absent (the clone's copy) or lacks the Accessibility grant
  (`fail: accessibility not trusted`, logged as a warning). `notif-center os` names
  the engine in use.

`notif-ax LAYOUT press N --dry-run` reads everything and presses nothing.

Measured on macOS 26.6.2, one banner on screen, a dry-run "press
the newest", 15 runs:

| Engine | Median | Best |
|---|---|---|
| osascript (System Events) | 332 ms | 320 ms |
| notif-ax in Swift | 48 ms | 43 ms |
| notif-ax in Rust (raw FFI, no crates) | 51 ms | 47 ms |

Swift and Rust are both ~10ms of process start plus a ~20ms first IPC into
NotificationCenter; the rest is a handful of sub-millisecond reads. Swift ships:
it is a little faster, its binary is a fifth of the size, and the package already
builds Swift. A whole `notif-center click` costs ~107ms with `notif-ax` and
~430ms with osascript.

## OS support

macOS only. The AX tree and the database schema are private and change between
releases. Each verified macOS has a layout file, `macos/<productVersion>.layout`
beside this document. The clicks use the running macOS's own file, else the
newest one older than it. `notif-center os` names the file in use.

A layout is three data lines (`#` starts a comment):

```
alert AXNotificationCenterAlert
stack AXNotificationCenterAlertStack
container AXWindow AXGroup AXGroup AXScrollArea AXGroup?
```

| Key | Holds |
|---|---|
| `alert` | the subrole of one notification |
| `stack` | the subrole of a collapsed group of notifications |
| `container` | the path from the app to the element whose children are the alerts and stacks. The first step is `AXWindow`; each later step is the first child with that role (`AXGroup:2` for the second). A step ending in `?` is taken only when the element so far does not already start with an alert or stack. |

A miss on a macOS without its own file says so in its banner. The banner's click
copies the path of `/tmp/notif-center/miss.md` and opens it: the result, how to
tell a stale layout from a real miss, the steps below, and the AX tree after the
miss. A miss with the macOS's own layout gets a plain banner. To add a file:

1. Read the tree with a banner on screen: `notif-center tree`.
2. Copy the closest file to `macos/<sw_vers -productVersion>.layout` in the clone and
   edit `container` until
   `NOTIF_CENTER_LAYOUT_DIR=~/dotfiles/.config/notif-center/macos notif-center click`
   presses a test banner.
3. Commit it. The store copy that Hyper+N runs gets it at the next `dotfiles switch`.

The database reader is not per-version. If `list` comes back wrong after an update,
re-verify the `DECODE` block in the script.
