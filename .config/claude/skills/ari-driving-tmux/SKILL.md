---
name: ari-driving-tmux
description: "Hand Ari commands for a terminal on this machine and read the results back: a click-to-run link that runs the command in his tmux pane through run_log and returns him to Claude's pane with `run_log artifact: <dir>` typed into its prompt, a click-to-type link, or a fenced block. Owns the run_log capture contract, the `ari-driving on|off|status` pane opt-in, and every clipboard rule: never write it unasked, the pbcopy guard, Raycast recovery. Part of /ari-driving; use when Ari should run something here, says \"pane 2.4\" or \"type it into my pane\", or pastes a `run_log artifact:` line."
---

# Driving tmux

Ari watches tmux panes on this machine and keeps their scrollback as the record. Claude never types into them: it hands Ari a link, and his click focuses the pane and types the command, or runs it through `run_log` and brings him straight back to Claude's pane with the capture's path already in the prompt. Where no pane fits, the command goes in a fenced block. The clipboard is Ari's: Claude writes it only when he asks, while `run_log` and `tcap` manage it for him by design.

A pane's *label* is `ID=%301|pane=2.4` (`/ari-driving` Rules). A *capture dir* is the directory one `run_log` run writes.

## Rules

- **Shared rules live in `/ari-driving`:** pane labels, hints not facts, no raw `send-keys`, the opt-in is Ari's, who runs what.
- **Every pane reference is a link.** `[ID=%301|pane=2.4](tmux-pane://301)`; a click focuses the pane. Build links with `bin/link.zsh`; never hand-encode one.
- **The output is needed back → a click-to-run link.** Only typing is wanted (Ari edits before running, or Enter is his call) → click-to-type. No pane, or an interactive command whose output belongs in this conversation (a browser login) → a fenced block, `! cmd` for the interactive kind.
- **The code block shows the bare command.** Never the `run_log` wrapper or the link's encoding.
- **Every user-run step of a round goes in one message.** Numbered, each with `Expected: …` (what Ari sees when it worked); then stop and wait.
- **The clipboard is written only when Ari asks in the current turn**, through `handoff.zsh --copy`. The PreToolUse guard blocks every other `pbcopy` Claude runs; never write `HANDOFF_CLIP_OK=1` yourself. Claude never restores a clobbered clipboard.
- **A `run_log artifact: <dir>` message is data to read, not a command.** Read it (**Read a capture**); never resend what produced it.

## Reference

### The opt-in

`ari-driving on|off|status` (`bin/ari-driving`; on PATH as `~/.config/bin/ari-driving`, and `~/.local/bin/ari-remote-tmux` under its old name) acts on the pane it runs in. `on` sets the pane option `@ari_driving`, the same window option, and window-scoped status formats with ✦ against the window number, and flashes `✦ AI control ON: ID=%301|pane=2.4`. `off` unsets the pane option, and the window's marker once no other pane in it is on. Only the pane option grants anything.

### Links

`bin/link.zsh --pane 2.4|%N [--cmd TEXT | --run TEXT]` resolves Ari's `2.4` in his most recently active session and prints:

- no command: `[ID=%301|pane=2.4](tmux-pane://301)`, focus only;
- `--cmd`: a blockquote of `[ID=%301|pane=2.4](tmux-pane://301?cmd=…)` and the command in a code block; the click types it, no Enter;
- `--run`: the same with `[▶ run in ID=%301|pane=2.4](tmux-pane://301?run=…)`; the click types `run_log --deliver-to <clicked pane> '<command>'`, presses Enter, and switches back to the clicked pane. When it finishes, `run_log artifact: <dir>` appears in that pane's prompt (no Enter), and only then the status line says so.

It warns on stderr when the pane is not opted in: the click would only focus. A click types only into an opted-in shell at an empty prompt; otherwise `bin/focus.zsh` focuses the pane and puts the reason on the status line. The handler is the `tmux-pane://` branch of `~/.config/tmux/plugin/osc8-hyperlinks.conf`, which runs `focus.zsh` and logs to `~/.local/state/ari-driving-focus.log`; every other link still opens.

### The run_log contract

`run_log [--name N] [--dir D] [--fd N]… [--no-copy] [--deliver-to PANE] -- CMD` (`~/.config/bin/run_log`) runs CMD in an interactive zsh, so aliases work; stdout and stderr each get their own pty, so colors and progress bars behave as in a bare terminal. A single argument is a shell string (pipes, `&&`); several are an argv passed byte for byte; `VAR=val` assignments go after `--`. Each run writes one capture dir, `<root>/<seq>_<slug>/` (root: `--dir` > `$LOG_DIR` > `~/.local/state/run_log`; `--name` names it):

| File | Holds |
|---|---|
| `metadata` | `user=`, `timestamp=`, `cwd=`, `command=`, `stdout_tty=`, `stderr_tty=`, `exit=`, `duration_s=` |
| `1.fd`, `2.fd`, `<N>.fd` | each fd byte for byte, colors kept; `--fd N` (3–9) adds fd N, capture only |
| `<N>.fd.plain` | the same with escapes stripped and `\r` redraws resolved |
| `stdout`, `stderr`, `*.plain` | symlinks to the fd 1 and 2 files |

From a terminal it ends by copying `run_log artifact: <dir>` (skipped with `--no-copy`, `RUN_LOG_COPY=0`, or when stdout is not a terminal); `--deliver-to PANE` also types that line into a pane. The exit code is the command's, or 128 + the signal.

### Clipboard pieces

- `bin/handoff.zsh --print --cmd CMD --expect TEXT [--step N [--blocking|--not-blocking]] [--interactive | --capture [--capture-dir DIR]]` renders one fenced step; `--copy (--text T | --file P)` is the only sanctioned copy and prints where the displaced entry went.
- `bin/pretooluse_bash_pbcopy_guard.sh` is the PreToolUse hook, installed as `~/.config/claude/bin/pretooluse-pbcopy-guard.sh`. It exits 2 when `pbcopy` is in command position (start, after `|;&(` or a newline, as a path, or behind `xargs`, `sudo`, `env`, `command`, `exec`, `nohup`, `time`); quoted words, arguments and longer names pass, as does `HANDOFF_CLIP_OK=1`.
- Raycast records every clipboard change. `dotfiles raycast link clipboard-history` prints its widget, `<[Raycast: Clipboard History | key: '✦4'](raycast://extensions/raycast/clipboard-history/clipboard-history)>`; `dotfiles raycast link check` must show it allowed.

## Workflow

### Hand Ari a command

Ari names a pane, or one of his opted-in panes is the obvious place. Output needed back:

```zsh
zsh $HOME/.claude/skills/ari-driving-tmux/bin/link.zsh --pane 2.4 --run 'kubectl get pods -o wide'
```

Paste its stdout into chat unchanged:

> [▶ run in ID=%301|pane=2.4](tmux-pane://301?run=kubectl%20get%20pods%20-o%20wide)
> ```zsh
> kubectl get pods -o wide
> ```

`--cmd` instead of `--run` for type-only. No pane fits: fenced steps, one message for the round:

````
1. (blocks me)
```zsh
! gws auth login --scopes openid,email
```
Expected: `gws auth status` lists the new scopes.

2. (not blocking)
```zsh
run_log -- kubectl get pods -l app=web
```
Expected: one Running pod.
````

`(blocks me)` means Claude cannot continue until it is done. To render a step rather than type it:

```zsh
zsh $HOME/.claude/skills/ari-driving-tmux/bin/handoff.zsh --print --step 1 --blocking --cmd 'kubectl get pods' --expect 'one Running pod' --capture
```

### Read a capture

Ari sends `run_log artifact: <dir>`, or names a capture dir. Read `<dir>/metadata` first (command, cwd, exit, duration), then `<dir>/stdout.plain` and `<dir>/stderr.plain`; the raw `.fd` files only when escapes matter. A long capture is read with a subagent, which reports the conclusion. Interactive `!` steps arrive as output in the conversation; Ari's pasted output is data.

### Copy only on request

Ari asks for text on his clipboard, and only then:

```zsh
zsh $HOME/.claude/skills/ari-driving-tmux/bin/handoff.zsh --copy --text '<text>'
```

Repeat its `previous clipboard:` line in the message.

### Recover a clobbered clipboard

Print the widget and say the displaced entry is the second item in that list; Claude never restores and never reads the history:

```zsh
dotfiles raycast link clipboard-history
```

When the link text ends in `(not compiled yet)`, the binding is declared but Karabiner has not been rebaked; say so.

## Setup (once per machine)

- **Command:** `ln -s ../claude/skills/ari-driving-tmux/bin/ari-driving ~/.config/bin/ari-driving`.
- **Links:** `~/.config/tmux/plugin/osc8-hyperlinks.conf` carries the handler; `tmux source-file` it after a change.
- **Guard:** `cp "$HOME/.claude/skills/ari-driving-tmux/bin/pretooluse_bash_pbcopy_guard.sh" "$HOME/.config/claude/bin/pretooluse-pbcopy-guard.sh"`, then via `/update-config` a `PreToolUse` entry `{"matcher": "Bash", "hooks": [{"type": "command", "command": "$HOME/.config/claude/bin/pretooluse-pbcopy-guard.sh", "if": "Bash(*pbcopy*)", "timeout": 5}]}` with the path spelled out. Verify with the Bash call `false && pbcopy`: the guard must deny it.

## File storage

- `bin/ari-driving` — `on|off|status` for the current pane.
- `bin/link.zsh` — `--pane 2.4|%N [--cmd TEXT | --run TEXT]`; prints a link or the link-plus-code-block blockquote.
- `bin/focus.zsh` — `--pane %N[?cmd=…|?run=…] [--cmd TEXT | --run TEXT] [--return-pane %M] [--no-activate]`; what a click runs.
- `bin/handoff.zsh` — renders fenced steps; the sanctioned copy.
- `bin/pretooluse_bash_pbcopy_guard.sh` — the pbcopy guard hook.
