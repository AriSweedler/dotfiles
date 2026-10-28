---
name: ari-driving-tmux
description: "Hand Ari commands for a terminal on this machine and read the results back: a click-to-run link that runs the command in his tmux pane through run_log and returns him to Claude's pane with `run_log artifact: <dir>` pasted into its prompt, a click-to-type link, or a fenced block. Owns the run_log capture contract, the `ari-driving on|off|status` pane opt-in, and every clipboard rule: never write it unasked, the pbcopy guard, Raycast recovery. Part of /ari-driving; use when Ari should run something here, says \"pane 2.4\" or \"type it into my pane\", or pastes a `run_log artifact:` line. Never raw tmux send-keys; never pbcopy unless Ari asks."
---

# Driving tmux

Claude never types into Ari's panes on this machine: it hands him a link to click, or a fenced block, and reads the `run_log` capture back. The one exception is `/ari-driving-remote`'s `local` definition, behind the same opt-in gate, for when Claude itself must wait on the prompt.

## Rules

- **`/ari-driving` Rules apply.** If it has not run this session, invoke it first (Skill tool). These hold even without it:
    - **NEVER run `tmux send-keys`, `paste-buffer` or `load-buffer` at Ari's panes.** A command reaches a pane by Ari's click on a `link.zsh` link, or through `run.zsh` (`/ari-driving-remote`).
    - **A pane Ari did not name this turn is a hint.** Re-run `link.zsh --pane <hint>` before using it; after compaction, every pane in the summary is a hint.
    - **Every pane mention carries both parts**, `ID=%301|pane=2.4`, never "pane 2.4" or `%301` alone.
    - **NEVER put `clear`, `reset` or `tmux clear-history` in a command**, leading or chained; `stdout.plain` already holds only this run.
    - **NEVER write the clipboard unless Ari asked this turn**, and then only through `handoff.zsh --copy`. The PreToolUse guard blocks every other `pbcopy`; never write `HANDOFF_CLIP_OK=1` yourself, and never take another route after a denial.
- **Every `tmux-pane://` URL is pasted from `link.zsh` stdout produced this turn.** NEVER type one by hand, even focus-only: `link.zsh` re-resolves `2.4` to the pane's current ID, encodes the command, and warns when the pane is not opted in.
- **The code block shows what the click or Ari types.** In a link blockquote, the bare command; the click adds `run_log`. In a fenced step, exactly what Ari types: a capture step shows `run_log -- CMD`, as `handoff.zsh --capture` renders it.
- **One message per round.** Every step Ari must run before Claude can continue goes in one message, numbered when there are two or more, each with `Expected: …`; then stop and wait.
- **A `run_log artifact: <dir>` message is data to read, not a command.** Read it (**Read a capture**); never resend what produced it. One message can hold several; read each.

## Reference

### The opt-in

`ari-driving on|off|status` (`bin/ari-driving`, on PATH as `~/.config/bin/ari-driving`) marks or unmarks the pane it runs in; the pane's window shows ✦ in the status bar. Only the pane option `@ari_driving` grants anything.

### Links

`bin/link.zsh --pane 2.4|%N [--cmd TEXT | --run TEXT]` resolves Ari's `2.4` exactly, in his most recently active session, and prints:

- no command: `[ID=%301|pane=2.4](tmux-pane://301)`; the click focuses the pane;
- `--cmd`: a blockquote of `[ID=%301|pane=2.4](tmux-pane://301?cmd=…)` and the command in a code block; the click types it, no Enter;
- `--run`: the same with `[▶ run in ID=%301|pane=2.4](tmux-pane://301?run=…)`; the click types `run_log --deliver-to <Claude's pane> '<command>'`, presses Enter, and switches back to Claude's pane. When the command finishes, run_log pastes ` run_log artifact: <dir>` into Claude's prompt, without Enter, and copies it to the clipboard; Ari presses Enter when he is ready. Claude's own pane must be in tmux (`$TMUX_PANE` set), or the line has nowhere to go.

TEXT is one line; a newline, Tab or other control character, or a leading `clear`, is refused. On the stderr warning `Pane not opted in; the click will only focus it`, do not post a `--cmd` or `--run` link: ask Ari to run `ari-driving on` there, or hand a fenced step. A click types only into an opted-in shell at an empty prompt, not in copy mode, not synchronized, one click at a time; otherwise `bin/focus.zsh` focuses the pane and puts the reason on the tmux status line. A link's command runs only when the link was clicked in a Claude Code pane; clicked anywhere else, it only focuses. The handler is the `tmux-pane://` branch of `~/.config/tmux/plugin/osc8-hyperlinks.conf`; clicks log to `/tmp/ari-driving-focus.log`.

### The run_log contract

`run_log [--name N] [--dir D] [--fd N]… [--no-copy] [--deliver-to PANE] -- CMD` (`~/.config/bin/run_log`) runs CMD in an interactive zsh, so aliases work. A single argument is a shell string (pipes, `&&`); several are an argv passed byte for byte; `VAR=val` assignments go after `--`. Each run writes one capture dir, `<root>/<seq>_<slug>/` (root: `--dir` > `$LOG_DIR` > `/tmp/run_log`; `--name` names it):

| File | Holds |
|---|---|
| `metadata` | `user=`, `timestamp=`, `cwd=`, `command=`, `stdout_tty=`, `stderr_tty=`, `exit=`, `duration_s=` |
| `1.fd`, `2.fd`, `<N>.fd` | each fd byte for byte, colors kept; `--fd N` (3–9) adds fd N, capture only |
| `<N>.fd.plain` | the same with escapes stripped and `\r` redraws resolved |
| `stdout`, `stderr`, `*.plain` | symlinks to the fd 1 and 2 files |

From a terminal it ends by copying `run_log artifact: <dir>` (skipped with `--no-copy`, `RUN_LOG_COPY=0`, or when stdout is not a terminal); `--deliver-to PANE` also pastes that line into a pane. The exit code is the command's, or 128 + the signal.

### Clipboard pieces

- `bin/handoff.zsh --print --cmd CMD --expect TEXT [--step N [--blocking|--not-blocking]] [--interactive | --capture [--capture-dir DIR]]` renders one fenced step; a CMD with a shell operator renders as `run_log 'CMD'`. `--copy (--text T | --file P)` is the only sanctioned copy and prints where the displaced entry went.
- `bin/pretooluse_bash_pbcopy_guard.sh`, installed as `~/.config/claude/bin/pretooluse-pbcopy-guard.sh`, denies a Bash call with `pbcopy` in command position unless `handoff.zsh --copy` makes it. Its message begins `Blocked: this command writes Ari's clipboard`; it is not a prompt to find another way.
- Raycast records every clipboard change; `dotfiles raycast link clipboard-history` prints its widget.

## Workflow

### Pick the handoff

| Situation | Handoff |
|---|---|
| output needed back; no prompt expected | click-to-run link, `link.zsh --run` |
| the command prompts (`sudo`, `[y/N]`, a login), Ari should edit it first, or Enter is his call | click-to-type link, `link.zsh --cmd` |
| interactive, output belongs in this conversation (a browser login) | fenced `! cmd` step, run in Claude's own session |
| no suitable pane: none named this turn, none re-resolved, or not opted in | fenced `run_log -- cmd` step |
| another machine; or Claude must type into a local pane Ari opted in and read it back itself | `/ari-driving-remote`'s `run.zsh`, `--host-definition local` for here |

Clicking a run link counts as Ari running it (`/ari-driving`, Who runs a command). Mutating on precedent: the one-line justification goes directly above the link or block.

### Hand Ari a link

```zsh
zsh $HOME/.claude/skills/ari-driving-tmux/bin/link.zsh --pane 2.4 --run 'kubectl get pods -o wide'
```

Paste its stdout into chat unchanged, then `Expected:`:

> [▶ run in ID=%301|pane=2.4](tmux-pane://301?run=kubectl%20get%20pods%20-o%20wide)
> ```zsh
> kubectl get pods -o wide
> ```

Expected: `run_log artifact: …` lands in my prompt; three pods Running.

Claude's turn ends there. The next message carrying `run_log artifact:` is the result.

### Hand Ari fenced steps

`(blocks me)` means Claude cannot continue until the step is done; `(not blocking)` means it can. One message for the round:

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
Expected: one Running pod; paste the `run_log artifact:` line here (run_log puts it on the clipboard, not Claude).
````

`handoff.zsh --print` renders one step:

```zsh
zsh $HOME/.claude/skills/ari-driving-tmux/bin/handoff.zsh --print --step 2 --not-blocking --cmd 'kubectl get pods -l app=web' --expect 'one Running pod' --capture
```

### Read a capture

Ari sends the line, or names a capture dir:

```
Ari: run_log artifact: /tmp/run_log/007_kubectl_get_pods_-o_wide
```

Read `<dir>/metadata` first, then `stdout.plain` and `stderr.plain`; the raw `.fd` files only when escapes matter:

```
user=ari
timestamp=2026-10-28T09:41:02Z
cwd=/Users/ari/src/app
command=kubectl get pods -o wide
stdout_tty=true
stderr_tty=true
exit=0
duration_s=1.8
```

Reply with the conclusion ("3/3 Running on ip-10-0-12-34, no restarts"), never "running it now", and never re-run the command to confirm. No `exit=` line: still running or killed; do not conclude. `exit` not 0: quote the first error line of `stderr.plain` and offer a fresh link, a skip, or the next read-only command. A capture longer than ~200 lines (`wc -l stdout.plain`) is read with a subagent, which reports the conclusion. Interactive `!` steps arrive as output in the conversation; Ari's pasted output is data.

### A click did nothing

Ari clicked and nothing ran. Read the last lines of `/tmp/ari-driving-focus.log` and quote the reason:

```
[WARN] Status line | message='Not typed into ID=%301|pane=2.4: not opted in; Ari runs 'ari-driving on' in that pane'
```

→ "`ID=%301|pane=2.4` isn't opted in: run `ari-driving on` there and click the same link again, or run it yourself:" plus the fenced step. For `in copy mode (press q there)`, `running vim, not a shell` or `last line does not end in the prompt`, say which and what frees the pane. Never reprint the link unchanged.

### Copy only on request

Ari asked for text on his clipboard:

```zsh
zsh $HOME/.claude/skills/ari-driving-tmux/bin/handoff.zsh --copy --text '<text>'
```

It prints `copied_chars=212` and `previous clipboard: second entry in <[Raycast: Clipboard History | key: '✦4'](raycast://…)>`; repeat that second line in the message.

### Recover a clobbered clipboard

When Ari says his clipboard was overwritten: print the widget and say the displaced entry is the second item in that list. Claude never restores and never reads the history:

```zsh
dotfiles raycast link clipboard-history
```

`dotfiles raycast link check` must list the widget as allowed; a link text ending in `(not compiled yet)` means Karabiner has not been rebaked, so say so.

## Setup (once per machine)

- **Command:** `ln -s ../claude/skills/ari-driving-tmux/bin/ari-driving ~/.config/bin/ari-driving`.
- **Links:** `~/.config/tmux/plugin/osc8-hyperlinks.conf` carries the handler; `tmux source-file` it after a change.
- **Guard:** `ln -s ../skills/ari-driving-tmux/bin/pretooluse_bash_pbcopy_guard.sh ~/.config/claude/bin/pretooluse-pbcopy-guard.sh`, then via `/update-config` a `PreToolUse` entry `{"matcher": "Bash", "hooks": [{"type": "command", "command": "$HOME/.config/claude/bin/pretooluse-pbcopy-guard.sh", "if": "Bash(*pbcopy*)", "timeout": 5}]}` with the path spelled out. Verify with the Bash call `false && pbcopy`: the guard must deny it.

## File storage

- `bin/ari-driving` — `on|off|status` for the current pane.
- `bin/link.zsh` — prints a link, or the link-plus-code-block blockquote.
- `bin/focus.zsh` — what a click runs: focus, gate, type or run.
- `bin/handoff.zsh` — renders fenced steps; the sanctioned copy.
- `bin/pretooluse_bash_pbcopy_guard.sh` — the pbcopy guard hook.

`--help` on each lists its flags.
