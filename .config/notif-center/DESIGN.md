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

AX is the slow part: every read is an Apple-events round-trip (~20ms), so pulling
text for a trayful of notifications through AX takes seconds. Two choices keep it
snappy:

- **List from the database, not AX.** A database read is ~0.1s regardless of how
  many notifications are present; the equivalent AX walk is multiple seconds.
- **Skip the list on the hot path.** "Click the newest" needs no enumeration —
  it presses the top notification directly, so the common keybinding press is
  sub-second. Only filtered clicks (`--app` / `--match`) pay to read text.

## OS support

macOS only. The notification database schema and the AX element names are private
and change between macOS releases, so this tool is pinned to the version it was
built and verified against:

- **macOS 26.5 (build 25F71)**, Darwin 25.5.0.

The script holds this as `EXPECTED_MACOS_VERSION` / `EXPECTED_MACOS_BUILD`.
`notif-center os` reports the running version against the pin, and any
database-reading path warns on drift. After a macOS update that changes the
version, expect that warning; if reads start coming back wrong, the database
decoder and/or the AX logic likely need re-verifying against the new release.
