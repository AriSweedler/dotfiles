---
name: ari-tui-dashboard
description: Build or review a terminal dashboard, or any TUI that must run inside tmux. Picks watch, shell ANSI, gum, or a compiled binary; fixes the one-JSON-blob data contract; lists the tmux rules for TERM, color, glyphs, the cell-grid frame, signals and raw mode; gives the detached-tmux test recipe and the display-popup surface. Worked example is `plugged`, a Rust dashboard drawn as bordered panels.
---

# TUI dashboard

Worked example: `~/.config/plugged`, a Rust binary whose bare `plugged` is the live dashboard: bordered panels drawn on a grid of styled cells. Read these before writing a loop:

| file | holds |
|---|---|
| `~/.config/plugged/src/tui/terminal.rs` | `ioctl(TIOCGWINSZ)`, the `write(2)` loop, alternate screen, frame `draw`, `RawMode` as a `Drop` guard, signal pipe |
| `~/.config/plugged/src/tui/dashboard.rs` | option parsing (`--interval`; `--width` and `-` for `tui`), the stdin one-shot `render_once`, `run_dashboard`, the `poll()` loop `run_live` |
| `~/.config/plugged/src/render/frame.rs` | `Cell`/`Row`/`Style`, `build_frame(snapshot, status, columns)`, panels, `draw_link`, `render_ansi`, `render_plain` |
| `~/.config/plugged/src/render/mod.rs` | helpers both views share, `feeding_port` (where the power link starts) among them |
| `~/.config/plugged/src/render/merge.rs` | view-side folding of a USB 3 hub's two halves; the JSON keeps both |
| `~/.config/plugged/src/render/text.rs` | `render_text`, the text view |
| `~/.config/plugged/src/main.rs` | bare, `--json`, `--text`, `tui` dispatch; sorted JSON keys |
| `~/.config/plugged/src/model.rs` | `Snapshot`, `schemaVersion`, optional keys skipped |
| `~/.config/plugged/src/collect/mod.rs` | `collect_snapshot()`, one collector set per platform |
| `~/.config/plugged/bin/plugged` | build when a source is newer than the binary, then `exec`: the working tree, uncommitted edits included |
| `~/.config/plugged/bin/plugged-dev` | `build`, `test`, `check`; their stages are in `/ari-dotfile--submodule-plugged` § Commands |

**Test with `~/.config/plugged/bin/plugged`, never the `plugged` on PATH:** that one is the installed build and lacks uncommitted edits. Changing plugged itself (commits, the flake.lock bump) follows `/ari-dotfile--submodule-plugged`.

## Pick the tool

| need | use | why |
|---|---|---|
| rerun a text command; flicker is fine | `watch -n 2 --color <cmd>` | zero code |
| flicker-free loop, one screen, shell only | `printf` + `tput`, the frame below | any TERM, no deps |
| one-shot styled boxes or tables from a script | `gum style`, `gum table`, `gum join` | good render, no loop |
| collector is already a binary; needs keys, SIGWINCH, guaranteed restore | raw ANSI in the same binary, no framework (`plugged`) | one artifact |
| many screens, scrolling, focus | bubbletea, ratatui, textual | too heavy for one screen |

Pretty needs no framework: `plugged`'s panel borders, battery gauge and power link are cells in `build_frame`, from `tests/snapshots/mac-charging.frame.txt`:

```
╭─ Ports ──────────────────────────────────────────────────────────────────────────╮
│ USB-C 4  ●                         power-in 94 W ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓ │
│ HDMI 3   ○                                                                     ┃ │
├─ Power ────────────────────────────────────────────────────────────────────────╂─┤
│ ██████████████░░░░░░░░░░  57%  charging, 330 min to full                       ┃ │
│ adapter  94 W  ·  20 V × 4.7 A  ·  96W USB-C Power Adapter  ·  on USB-C 4 ◀━━━━┛ │
```

The `╂` is `draw_link` writing over a `─` border cell, which a frame of strings cannot do.

Minimal shell loop, for a collector that prints plain text. `tput cols`/`lines` hit `ioctl` each call, so it follows a resize without a handler; one line short of the screen, because the last newline would scroll it:

```zsh
[[ -t 1 ]] || { my-collector text; exit; }
tput smcup; tput civis
trap 'tput cnorm; tput rmcup' EXIT
trap 'exit' INT TERM HUP
while :; do
  printf '\e[H'
  my-collector text | head -n "$(( $(tput lines) - 1 ))" | cut -c1-"$(tput cols)" | sed $'s/$/\e[K/'
  printf '\e[J'; sleep 2
done
```

## Data contract

| rule | `plugged` |
|---|---|
| One collector call prints one JSON document; sorted keys; `schemaVersion`; optional keys omitted, never null | `plugged --json` (also `json`; through a `serde_json::Value` in `main.rs`, so keys sort), `model.rs` (`skip_serializing_if`), `collect/mod.rs` |
| The renderer reads JSON from stdin, or self-polls by calling the collector in-process | `plugged tui -`, or `plugged tui` with stdin not a TTY, decodes once; otherwise `collect_snapshot()` every `--interval` |
| Text and TUI views take the same model | `render_text` in `render/text.rs` and `build_frame` in `render/frame.rs` both take `&Snapshot` |
| View-only fixes live in the view, not the JSON | `merge_containers` in `render/merge.rs` |
| Build a frame as a grid of styled cells, one cell per column, then emit ANSI | `Row = Vec<Cell>`; an overlay writes cells, so `draw_link` crosses panel borders; `truncate` is `take(columns)` on cells before `render_ansi`, so a cut never lands inside an escape |
| Never write escapes to a pipe | `is_terminal` gates in `dashboard.rs`; off a terminal, the text view, or with `--width N` the frame through `render_plain` |

Modes, from `main.rs` and `run_dashboard`/`run_tui` in `dashboard.rs`. "Not a TTY" is a pipe, a file or `/dev/null`:

| command | stdin | stdout | does |
|---|---|---|---|
| `plugged --json`, `plugged --text` | any | any | print once |
| `plugged [--interval N]` | TTY | TTY | live loop |
| `plugged [--interval N]` | any other pair | | text view once; stdin is never read |
| `plugged tui`, or `plugged tui -` | not a TTY, or `-` | TTY | one colored frame as ordinary lines, not the alternate screen; exit 0 |
| `plugged tui`, or `plugged tui -` | not a TTY, or `-` | not a TTY | text view; with `--width N`, the frame N wide, uncolored |
| `plugged tui` | TTY | TTY | live loop |
| `plugged tui` | TTY | not a TTY | collect once; text view, or with `--width N` the frame uncolored |

`--width` and `-` are `tui`'s only: bare `plugged --width 50` is an unknown command. `plugged tui -` with a TTY stdin waits for a document until Ctrl-D.

Bad JSON on stdin, an empty one included, exits 1 with one stderr line: `plugged tui: stdin is not a plugged JSON document (<serde's error>)`. Bad arguments print `plugged: unknown command '<x>'` or `plugged: bad tui arguments`, then the usage, and exit 2.

## tmux rules

| rule | how |
|---|---|
| Never set or export `TERM` | tmux gives `screen-256color` or `tmux-256color`; `tput colors` says 256; no `terminal-overrides` means no RGB |
| 16 or 256 colors, never RGB | `ESC[3Xm`, or `ESC[38;5;Nm`; never `ESC[38;2;r;g;bm`. `Style::sgr` in `frame.rs` emits only 1, 2, 30-37, joined by `;` |
| Reset per run | `render_ansi` gives each run of one style one SGR and an `ESC[0m`; a truncated line leaves no attribute open |
| Alternate screen and hidden cursor, restored on every exit path | `ESC[?1049h ESC[?25l` on entry; `ESC[0m ESC[?25h ESC[?1049l` on exit (`enter_screen`/`leave_screen`) |
| The frame | `ESC[H`, then every line followed by `ESC[K`, joined by `\r\n`, then `ESC[J`. Never `ESC[2J` per frame |
| Never more lines than rows | `.take(size.rows)` in `run_live`; overflow scrolls the alternate screen and the next `ESC[H` frame drifts |
| Size from `ioctl(TIOCGWINSZ)`, re-read on SIGWINCH | `terminal::size()`; falls back to 80x24 when the ioctl fails or reports 0 |
| Truncate by visible width | `build_frame` clamps its width to 48..96, then cuts each row with `take(columns)`. That counts columns only while every cell is one column wide |
| Single-cell glyphs only | the frame's own glyphs, all of them: ASCII, box drawing, block elements `█` `░`, `●` `○` `◀`, `·` `×`. No VS16 or ZWJ emoji, no keycaps, no CJK. Collected text (a USB product name) can hold a wide character: measure it with wcwidth or replace it; `plugged` does neither, a known gap, not a pattern |
| No mouse reporting | never `ESC[?1000h` and friends; it steals tmux's mouse |
| Handle SIGHUP | tmux sends it when the pane's pty goes away, including a closed popup |

From `draw` in `terminal.rs`:

```rust
let body: Vec<String> = lines.iter().map(|line| format!("{line}\x1b[K")).collect();
write(&format!("\x1b[H{}\x1b[J", body.join("\r\n")));
```

## Input loop

Raw mode only for the live loop that reads keys; the one-shot and piped paths never touch termios.
Hold it for the loop's lifetime, not per read: a key that lands while the terminal is cooked echoes onto the frame.

| step | `RawMode` in `terminal.rs` |
|---|---|
| save | `RawMode::enter()`: `tcgetattr` into `original`; `None` when stdin is not a tty |
| set | clear `ICANON` and `ECHO`; `VMIN=1`, `VTIME=0`; keep `ISIG` so Ctrl-C is still SIGINT; keep `OPOST` so `\n` still works |
| restore | `Drop`: `tcsetattr(TCSANOW, original)` |

Signals go through a self-pipe (`install_signal_pipe` in `terminal.rs`): `pipe()`, one `signal()` handler for SIGINT, SIGTERM, SIGHUP, SIGWINCH. **The handler only writes the signal number to the pipe as one byte; it never draws, restores or exits.** `signal()` also overrides an inherited `SIG_IGN`, which the Ctrl-C test in **Test recipe** relies on.

`run_live` in `dashboard.rs` holds two `Drop` guards: `_raw` (`RawMode`) and `_screen` (`Screen`, whose drop calls `leave_screen`). They drop in reverse, so every return leaves the screen, then restores the modes. **NEVER call `process::exit` inside the loop: it skips `Drop`. Return a code; `main` exits after `run_live` returns.** A panic unwinds through the same guards (Cargo's default `panic = "unwind"`; never set `abort`), and its message is erased with the alternate screen.

```
poll([stdin, pipe], timeout = ms until next_tick)
ready < 0 and EINTR      -> continue; other errors -> return 1
timeout, or now >= tick  -> collect, draw, next_tick = now + interval
stdin readable           -> read <= 64 bytes; q, Q or 0x03 -> return 0
pipe readable            -> per byte: SIGWINCH -> size = terminal::size(), draw last snapshot
                                       else    -> return 0
```

Exit code 0 for `q`, Ctrl-C, SIGTERM, SIGHUP.

## Test recipe

Without tmux, from `~/.config/plugged`:

- `bin/plugged-dev check` builds, runs `plugged json | plugged tui - >/dev/null`, and runs the tests, among other stages (`/ari-dotfile--submodule-plugged` § Commands).
- The frame: `bin/plugged tui - --width 84 < tests/snapshots/mac-charging.json | diff - tests/snapshots/mac-charging.frame.txt` prints nothing when it matches; `bin/plugged-dev test` does this for every fixture and snapshot.
- `bin/plugged-dev test --update` rewrites the expected files from the current build, a regression included: run it only after reading the failing diff, and show `git diff tests/` before any commit.

Then tmux, on a private server (`-L`): it is not Ari's, so `send-keys` into it is not the raw send-keys `/ari-driving` forbids, and `kill-server` kills only it. **Run `~/.config/plugged/bin/plugged-dev build` first**: a stale binary makes `bin/plugged` build inside the pane, and the captures show cargo. **Run each block below as one Bash call:** `L` and `t` do not survive between calls. The pane command ends in `sleep 60` so the pane outlives the app; without it, `q` closes the session and every later `t` fails.

```zsh
L="tui-test-$$"; t() { tmux -L "$L" -f /dev/null "$@"; }
t new-session -d -x 100 -y 30 '~/.config/plugged/bin/plugged; echo exit=$?; sleep 60'
for i in {1..50}; do t capture-pane -p | grep -q 'q quits' && break; sleep 0.2; done
t capture-pane -p                                              # the frame
t capture-pane -p -J | awk '{ print length }' | sort -n | tail -1   # <= 100; -J joins wrapped rows, so a wrap reads longer
t capture-pane -p | head -1 | grep -q plugged && echo header-ok      # a drifted frame loses its header first
t capture-pane -p -e | grep -o $'\e\[[0-9;]*m' | sort -u      # only 0, 1, 2, 3x and combinations like 0;1; 39 is tmux's own
h1="$(t capture-pane -p | head -1)"; sleep 2.5
[[ "$(t capture-pane -p | head -1)" != "$h1" ]] && echo tick-ok     # the header clock moved
t resize-window -x 80; sleep 1
t capture-pane -p -J | awk '{ print length }' | sort -n | tail -1   # <= 80, no garbage
t send-keys q; sleep 0.5; t capture-pane -p | grep 'exit='    # exit=0, dashboard gone
t kill-server
```

Ctrl-C: `new-session -d '<cmd>'` runs under a non-interactive `zsh -c` with no job control, so the tty's SIGINT reaches that shell too and the whole pane dies. Ignore it in the pane shell; the app re-installs its own handler:

```zsh
L="tui-test-$$"; t() { tmux -L "$L" -f /dev/null "$@"; }
t new-session -d -x 100 -y 30 \
  'trap "" INT; ~/.config/plugged/bin/plugged; echo exit=$?; stty -a | tr " ;" "\n\n" | grep -xE -- "-?(icanon|echo)"; sleep 60'
for i in {1..50}; do t capture-pane -p | grep -q 'q quits' && break; sleep 0.2; done
t send-keys C-c; sleep 0.5
t capture-pane -p | grep -v '^$' | tail -3   # expect exit=0, then icanon and echo, neither with a leading "-"
t kill-server
```

SIGTERM and SIGHUP: the Ctrl-C block with `t send-keys C-c` replaced by `kill -TERM "$(pgrep -P "$(t display -p '#{pane_pid}')")"` (or `-HUP`, the stand-in for closing a popup), same expected output.

Not covered by this recipe: a dragged terminal window (only `resize-window` delivers SIGWINCH here), the popup itself (it needs an attached client), and scrolling when the frame is taller than the pane (`plugged` cuts at the bottom with no indicator).

## Popup surface

`tmux display-popup -E -w 90% -h 80% ~/.config/plugged/bin/plugged`. `-E` closes the popup when the command exits, so `q` closes it. A popup has no copy mode: nothing to select or scroll. Closing the popup sends SIGHUP, so the guards in `run_live` restore the terminal. **NEVER run `display-popup` yourself: it opens on Ari's screen.** Hand it to Ari as an interactive run link per `/ari-driving-tmux`.

## Failures

| symptom | cause | fix |
|---|---|---|
| wrapped lines, frame drifts down | a glyph wider than one cell, or more lines than rows | single-cell glyphs; truncate by cells; `.take(rows)` |
| stuck terminal after exit: no echo, cursor gone, still on the alternate screen | an exit path that skips `Drop`: `process::exit` inside the loop, or `panic = "abort"` | a `Drop` guard (shell: an EXIT trap) per mode, held for the loop; return from it, and signals exit through the same path. Ari runs `reset` to recover |
| the dashboard flashes and exits 101 with no message | a panic after `enter_screen`; `leave_screen` erased its message | validate every argument before `enter_screen`; rerun with `2>err.log` to read it |
| escapes in a log file | rendered ANSI to a non-TTY stdout | `is_terminal` gate, text view or `render_plain` |
| Ctrl-C kills the test pane, not the app | `zsh -c` shares the foreground process group | `trap "" INT` in the pane shell |
| a key echoes onto the frame | raw mode toggled per read | hold raw mode for the loop |
| tmux mouse stops working | mouse reporting enabled | never enable it |
