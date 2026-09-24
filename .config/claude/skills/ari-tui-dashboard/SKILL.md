---
name: ari-tui-dashboard
description: Build or review a terminal dashboard, or any TUI that must run inside tmux. Picks watch, shell ANSI, gum, or a compiled binary; fixes the one-JSON-blob data contract; lists the tmux rules for TERM, color, glyphs, the frame, signals and raw mode; gives the detached-tmux test recipe and the display-popup surface. Worked example is `plugged tui`.
---

# TUI dashboard

Worked example: `~/.config/plugged`, subcommand `plugged tui`. Read these before writing a loop:

| file | holds |
|---|---|
| `~/.config/plugged/Sources/plugged/TUI/Terminal.swift` | `ioctl(TIOCGWINSZ)`, `write(2)` loop, alternate screen, frame draw, `RawMode`, signal pipe |
| `~/.config/plugged/Sources/plugged/TUI/Dashboard.swift` | option parsing, the stdin one-shot, the `poll()` loop |
| `~/.config/plugged/Sources/plugged/Render/Frame.swift` | `Span`/`Style`/`Line`, `buildFrame`, `truncate`, `renderANSI` |
| `~/.config/plugged/Sources/plugged/Render/Merge.swift` | view-side folding of a USB 3 hub's two halves; the JSON keeps both |
| `~/.config/plugged/Sources/plugged/main.swift` | `json`, `text`, `tui` dispatch |
| `~/.config/plugged/bin/plugged` | build when a source is newer than the binary, then `exec` |
| `~/.config/plugged/bin/plugged-dev` | `check`: jq-validate the JSON, round-trip it through `tui -`, render text |

## Pick the tool

| need | use | why |
|---|---|---|
| rerun a text command; flicker is fine | `watch -n 2 --color <cmd>` | zero code |
| flicker-free loop, one screen, shell only | `printf` + `tput`, the frame below | any TERM, no deps |
| one-shot styled boxes or tables from a script | `gum style`, `gum table`, `gum join` | good render, no loop |
| collector is already a binary; needs keys, SIGWINCH, guaranteed restore | raw ANSI in the same binary, no framework (`plugged`) | one artifact |
| many screens, scrolling, focus | bubbletea, ratatui, textual | too heavy for one screen |

Minimal shell loop. `tput cols`/`lines` hit `ioctl` each call, so it follows a resize without a handler:

```zsh
tput smcup; tput civis
trap 'tput cnorm; tput rmcup; exit' INT TERM HUP
while :; do
  printf '\e[H'
  my-collector text | head -n "$(tput lines)" | cut -c1-"$(tput cols)" | sed $'s/$/\e[K/'
  printf '\e[J'; sleep 2
done
```

## Data contract

| rule | `plugged` |
|---|---|
| One collector call prints one JSON document; sorted keys; `schemaVersion`; optional keys omitted, never null | `plugged json`, `Model.swift`, `Collect/Snapshot.swift` |
| The renderer reads JSON from stdin, or self-polls by calling the collector in-process | `-` or a piped stdin decodes once; otherwise `collectSnapshot()` every `--interval` |
| Text and TUI views take the same model | `renderText(_:)` in `Render/Text.swift` and `buildFrame(_:status:)` in `Render/Frame.swift` both take `Snapshot` |
| View-only fixes live in the view, not the JSON | `mergeContainers` in `Render/Merge.swift` |
| Build a frame as spans, truncate spans by width, then emit ANSI | `Line = [Span]`; `truncate(_:to:)` before `renderANSI(_:)`, so a cut never lands inside an escape |
| Never write escapes to a pipe | `isatty(STDOUT_FILENO)` gate in `Dashboard.swift` |

Mode table, from `runTUI` in `Dashboard.swift`:

| stdin | stdout | does |
|---|---|---|
| `-` or pipe | TTY | one colored frame as ordinary lines, not the alternate screen; exit 0 |
| `-` or pipe | pipe | text view |
| TTY | TTY | live loop |
| TTY | pipe | collect once, text view |

Bad JSON on stdin: one line on stderr, exit 1. Bad arguments: usage, exit 2.

## tmux rules

| rule | how |
|---|---|
| Honor `$TERM` | tmux gives `screen-256color` or `tmux-256color`; `tput colors` says 256; no `terminal-overrides` means no RGB |
| 16 or 256 colors, never RGB | `ESC[3Xm`, or `ESC[38;5;Nm`; never `ESC[38;2;r;g;bm`. `Style.sgr` in `Frame.swift` emits only 1, 2, 30-37 |
| Reset per span | `renderANSI` wraps each styled span in its SGR and `ESC[0m`; a truncated line leaves no attribute open |
| Alternate screen, restored on every exit path | `ESC[?1049h` on entry; `ESC[0m ESC[?25h ESC[?1049l` on exit (`Screen.enter`/`leave`) |
| Cursor hidden and restored | `ESC[?25l` with entry, `ESC[?25h` with exit |
| The frame | `ESC[H`, then every line followed by `ESC[K`, joined by `\r\n`, then `ESC[J`. Never `ESC[2J` per frame |
| Never more lines than rows | `prefix(rows)`; overflow scrolls the alternate screen and the next `ESC[H` frame drifts |
| Size from `ioctl(TIOCGWINSZ)`, re-read on SIGWINCH | `Terminal.size()`; falls back to 80x24 when the ioctl fails |
| Truncate by visible width | `truncate(_:to:)` counts characters because every glyph is one cell; otherwise count cells (wcwidth) |
| Single-cell glyphs only | ASCII, box drawing, `●` U+25CF, `○` U+25CB. No VS16 or ZWJ emoji, no keycaps, no CJK |
| No mouse reporting | never `ESC[?1000h` and friends; it steals tmux's mouse |
| Handle SIGHUP | tmux sends it when the pane's pty goes away, including a closed popup |

From `Screen.draw` in `Terminal.swift`:

```swift
Terminal.write("\u{1B}[H" + lines.map { $0 + "\u{1B}[K" }.joined(separator: "\r\n") + "\u{1B}[J")
```

## Input loop

Raw mode only for the live loop that reads keys; the one-shot and piped paths never touch termios.
Hold it for the loop's lifetime, not per read: a key that lands while the terminal is cooked echoes onto the frame.

| step | `RawMode` in `Terminal.swift` |
|---|---|
| save | `tcgetattr` into `original`; return nil when stdin is not a tty |
| set | clear `ICANON` and `ECHO`; `VMIN=1`, `VTIME=0`; keep `ISIG` so Ctrl-C is still SIGINT; keep `OPOST` so `\n` still works |
| restore | `tcsetattr(TCSANOW, original)` |

Signals go through a self-pipe (`installSignalPipe` in `Terminal.swift`): `pipe()`, one `signal()` handler for SIGINT, SIGTERM, SIGHUP, SIGWINCH that writes the signal number as one byte. The handler does nothing else. `signal()` also overrides an inherited `SIG_IGN`, which the Ctrl-C test below relies on.

The loop (`runLive` in `Dashboard.swift`), one `defer { Screen.leave(); raw?.restore() }` covering every return:

```
poll([stdin, pipe], timeout = ms until nextTick)
ready < 0 and EINTR      -> continue
timeout, or now >= tick  -> collect, draw, nextTick = now + interval
stdin readable           -> read <= 64 bytes; q, Q or 0x03 -> return 0
pipe readable            -> per byte: SIGWINCH -> size = Terminal.size(), draw last snapshot
                                       else    -> return 0
```

Exit code 0 for `q`, Ctrl-C, SIGTERM, SIGHUP. Ticks re-collect; SIGWINCH only redraws.

## Test recipe

Pre-check without tmux: `bin/plugged-dev check` builds, validates the JSON with `jq -e`, and runs `plugged json | plugged tui - >/dev/null`.

Then a detached session of your own. Unique name, `-t "$S"` on every command, `kill-session` only for that name, never `kill-server`, never a bare `send-keys`. The pane command ends in `sleep 60` so the pane outlives the app; a bare `'plugged tui'` closes the session on `q` and every later `-t "$S"` fails.

```zsh
S="tui-test-$$"
tmux new-session -d -s "$S" -x 100 -y 30 '~/.config/plugged/bin/plugged tui; echo exit=$?; sleep 60'
sleep 1.5
tmux capture-pane -p -t "$S"                                  # the frame
tmux capture-pane -p -t "$S" | awk '{ print length }' | sort -n | tail -1   # <= 100, so nothing wrapped
tmux capture-pane -p -e -t "$S" | grep -o $'\e\[[0-9;]*m' | sort -u        # only 0, 1, 2, 3x; 39 is tmux's own
sleep 2.5; tmux capture-pane -p -t "$S" | head -1            # header clock moved, so the tick collects
tmux resize-window -t "$S" -x 80; sleep 1
tmux capture-pane -p -t "$S" | awk '{ print length }' | sort -n | tail -1   # <= 80, no garbage
tmux send-keys -t "$S" q; sleep 0.5; tmux capture-pane -p -t "$S"          # dashboard gone, exit=0
tmux kill-session -t "$S"
```

Ctrl-C needs one trick. `new-session -d '<cmd>'` runs under a non-interactive `zsh -c` with no job control, so the tty's SIGINT reaches that shell too and the whole pane dies. Ignore it in the pane shell; the app re-installs its own handler:

```zsh
tmux new-session -d -s "$S" -x 100 -y 30 \
  'trap "" INT; ~/.config/plugged/bin/plugged tui; echo exit=$?; stty -a | tr ";" "\n" | grep -E "icanon| echo"; sleep 60'
sleep 1.5; tmux send-keys -t "$S" C-c; sleep 0.5
tmux capture-pane -p -t "$S"      # expect exit=0, and icanon / echo without a leading "-"
tmux kill-session -t "$S"
```

SIGTERM: `kill -TERM "$(pgrep -P "$(tmux display -p -t "$S" '#{pane_pid}')")"`, same checks. Afterwards `tmux ls` shows only the sessions that were there before.

Not covered by this recipe: a dragged terminal window (only `resize-window` delivers SIGWINCH here), and scrolling when the frame is taller than the pane (`plugged` cuts at the bottom with no indicator).

## Popup surface

`tmux display-popup -E -w 90% -h 80% 'plugged tui'`. `-E` closes the popup when the command exits, so `q` closes it. A popup has no copy mode: nothing to select or scroll. Closing the popup hangs up the pty, so the SIGHUP path above is what restores the terminal.

## Failures

| symptom | cause | fix |
|---|---|---|
| memory garbage on first paint | `write(fd, &bytes[offset], n)`: Swift makes a one-byte temporary for the subscript and `write` reads past it | `withUnsafeBytes { base + offset }`, as in `Terminal.write` |
| wrapped lines, frame drifts down | a glyph wider than one cell, or more lines than rows | single-cell glyphs; truncate by cells; `prefix(rows)` |
| stuck terminal after exit: no echo, cursor gone, still on the alternate screen | one exit path skipped leave and restore | one `defer` or trap for every return; signals exit through the same path. `reset` recovers by hand |
| escapes in a log file | rendered ANSI to a non-TTY stdout | `isatty` gate, text view |
| Ctrl-C kills the test pane, not the app | `zsh -c` shares the foreground process group | `trap "" INT` in the pane shell |
| a key echoes onto the frame | raw mode toggled per read | hold raw mode for the loop |
| tmux mouse stops working | mouse reporting enabled | never enable it |
