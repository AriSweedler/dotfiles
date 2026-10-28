---
name: ari-driving-remote
description: "Drive a tmux pane on another machine over ssh: type each command into the pane Ari named, wait for his shell prompt, read the pane back. Hosts are remembered as named definitions (user@host, prompt, panes, what Ari said about them). Every send is gated: the pane must be marked `ari-driving on` and idle at his prompt, or nothing is typed. Part of /ari-driving; use when Ari names his laptop, a Pi, a host or a definition, or says to run something over there. Never raw tmux send-keys; never pbcopy unless Ari asks."
---

# Driving remote

Claude runs nothing on another machine except by typing into the pane Ari named, through `bin/run.zsh`, which gates the send, waits for his prompt and prints the pane. Hosts are remembered as named definitions.

## Rules

- **`/ari-driving` Rules apply.** If it has not run this session, invoke it first (Skill tool). These hold even without it:
    - **NEVER run `tmux send-keys` yourself, here or as `ssh host tmux …`.** Every keystroke to a host goes through `run.zsh --cmd`; nothing else runs on the host over ssh.
    - **A pane from earlier in the conversation or a compaction summary is a hint.** Re-run `--list` and use it only if it still shows `✦` and a shell.
    - **Every pane mention carries the whole label**, `machine=personal|ID=%6|pane=4.1`, in inline code, never linked, never one part alone.
    - **NEVER start or chain `clear`, `reset` or `tmux clear-history`**; raise `--lines` to see more. `run.zsh` refuses a leading `clear`.
    - **NEVER `pbcopy` on his machine**; `run.zsh` refuses it in `--cmd`.
- **`--hosts` first.** The first `run.zsh` call of a conversation, and the first after compaction, MUST be `--hosts`. Never guess a name or a `user@host`; read them from its output.
- **Before every non-empty `--cmd`, the bare command goes in chat, in the same message**, headed by the pane's label from the latest `--list`. `run.zsh` adds the `run_log` wrapper itself and prints `TYPED:` with the exact text it sent. Captures (`--cmd ''`) and `--list` need no block.
- **One `--cmd` per prompt.** Several commands chain with `&&` or `;` inside one `--cmd`; keys sent while a command runs are eaten by it. Directory state persists in the pane, so prefer absolute paths.
- **Exit 124 means still running, not failed**, as after `--no-wait` or a Bash-tool timeout. NEVER resend; the only call on that pane until the prompt returns is a capture, `--cmd ''`.
- **Exit 77 or 75: nothing was typed. NEVER work around the gate**: no other `--target` Ari did not name, no `--no-run-log`, no ssh of your own. Print the command under its label and say why; send once more only after Ari says the pane is ready.
- **Nested ssh is one-shot and `-t`:** `ssh -t pi@pi.local "cd app && ./install.sh"`. Never an interactive nested shell: every later wait would time out.
- **`--no-enter` when Ari runs it:** he said never press Enter, the harness denied the command, or it mutates and he has not allowed it. Tell him it is on his prompt line; nothing else goes into that pane until he says he pressed Enter or cleared it.
- **Save what Ari says about a host as soon as he says it.** A username, an address, how it is reached, what it is for, a correction: the next `run.zsh` call is `--describe` with the merged text, before any `--cmd`.
- **`--host` only for a name absent from `--hosts`.** On an existing name it is refused unless Ari said the address changed; then `--re-point`.

## Reference

### Host definitions

`~/.local/share/ari-driving-remote/hosts/<name>`, one file per definition, local to this machine and never committed; only `run.zsh` writes them, and moves any left in the old `~/.cache` dir on its next run. The values below are illustrative; real ones come from `--hosts`:

```
host=me@laptop.local
path_prefix=/opt/homebrew/bin
prompt_end=❯
windows=machine=personal|ID=%3|pane=1.1 | machine=personal|ID=%6|pane=4.1
last_seen=2026-10-22T07:55:14Z
description=Personal MacBook, session 0. The only machine with an ssh key on the Pi: reach pi@pi.local from it with a nested ssh -t.
```

`windows` holds each pane's label from the last `--list`; `last_seen` the last run that answered. `description` describes the machine: what it is, how it is reached, what only it can do. It never names a window or a pane; those change daily, and `run.zsh` checks the live panes on every run anyway. Two seeds: `laptop`, written when no definition exists, and `local` (`host=local`: tmux here, no ssh). A definition whose description says it has no tmux (the Pi) is a record, not a target: run through the host it says it is reached from.

### The gate

Every non-empty `--cmd`, before any key and under a per-pane lock: the pane option `@ari_driving` is `on`; the pane is not in copy mode or synchronized; the foreground command is a shell; the last non-blank line ends in `prompt_end`. A failure prints `REFUSED: <label> <why>` and the pane tail, types nothing, and exits 77 or 75:

```
PANE: machine=personal|ID=%6|pane=4.1
REFUSED: machine=personal|ID=%6|pane=4.1 not opted in; Ari runs 'ari-driving on' in that pane
```

→ "`machine=personal|ID=%6|pane=4.1` isn't marked. Run `ari-driving on` there and say so, or run this yourself:" plus the fenced command.

```
REFUSED: machine=personal|ID=%6|pane=4.1 running vim, not a shell
```

→ "`machine=personal|ID=%6|pane=4.1` is in vim. The command, for when it is free:" plus the fenced command. No retry.

A pane that closed since it was last seen fails the same exact check on the next run, with exit 70 and the host's live panes under the refusal:

```
REFUSED: no pane matches %6
PANES: every pane on the host, label command session: window -- title
machine=personal|ID=%3|pane=1.1 zsh 0: caf -- laptop
machine=personal|ID=%18|pane=3.1 zsh 0: homelab -- laptop
```

→ name the candidate under its full label and ask Ari which pane he means; `--list` adds the ✦ marks when that matters.

### Exit codes

| Code | Meaning | Claude's next action |
|---|---|---|
| 0 | the shell prompt returned | read the pane from the `TYPED:` echo down |
| 124 | still running: timeout, `--no-wait`, or ssh dropped after `SENT` | `--cmd ''` to capture; never resend |
| 77 | pane not opted in; nothing typed | Ari runs `ari-driving on` there; print the command |
| 75 | pane busy: copy mode, synchronized, not a shell, text on the line, or another caller typing; nothing typed | print the command under its label; never retry on your own |
| 70 | no pane matches, no attached client to resolve `2.4` against, or no tmux server | read the `PANES:` lines under the refusal (every pane on the host, live), pick the one Ari means or ask him; `--list` only for the ✦ marks; or `--session S` |
| 127 | tmux not on the host's PATH | `--path-prefix ''` (Linux) or its dir; then `--describe` the fix |
| 255 | ssh could not connect before anything was typed | Ari runs `ssh user@host` once in a pane (key, sleep); retry only after he says done |

## Workflow

### Read the known hosts

```zsh
zsh $HOME/.claude/skills/ari-driving-remote/bin/run.zsh --hosts
```

Then the live panes of the chosen definition:

```zsh
zsh $HOME/.claude/skills/ari-driving-remote/bin/run.zsh --host-definition laptop --list
```

```
machine=personal|ID=%6|pane=4.1 ✦ zsh 0: pi -- laptop
machine=personal|ID=%7|pane=4.2 - vim 0: pi -- notes.md
```

✦ means Ari opted the pane in, `-` that he did not; the next field is its foreground command. A pane running anything but a shell (`ssh`, `vim`, `less`) refuses with 75. The `local` definition's lines carry no `machine=` prefix.

### Run a command

The label and the bare command first:

`machine=personal|ID=%6|pane=4.1`
```zsh
diskutil list external physical
```

```zsh
zsh $HOME/.claude/skills/ari-driving-remote/bin/run.zsh --host-definition laptop --target 4.1 --cmd 'diskutil list external physical'
```

The output starts `PANE: machine=personal|ID=%6|pane=4.1` (the host's `dotfiles machine-name`, else the definition name), then the last 60 lines of the pane once the prompt is back. Between them, `TYPED:` shows the exact text sent and `SENT` that it reached the pane. Read from the line that echoes the command down to the final prompt; lines above it are history:

```
PANE: machine=personal|ID=%6|pane=4.1
TYPED: run_log 'diskutil list external physical'
SENT
~ ❯ ls                                   ← history
Desktop  Downloads
~ ❯ run_log 'diskutil list external physical'
/dev/disk4 (external, physical):
   #:  TYPE NAME   SIZE   IDENTIFIER
   0:  FDisk_partition_scheme *64.0 GB disk4
~ ❯
```

`run.zsh` wraps the command in `run_log` when the host has `~/.config/bin/run_log` (else `NOTE: no … on the host; typed the command bare`), so the capture lands in the host's `/tmp/run_log`. Read results from the pane; a remote capture dir is read with `--cmd 'cat <dir>/stdout.plain'`, never with Read. `--no-run-log` types the command bare. When you raise `--timeout` (default 90 s), set the Bash tool's timeout higher. Check a tricky command's quoting with `--dry-run`.

A command that asks something: the pane ends in `[sudo] password for pi:` with exit 124. Chat: "Type the Pi's sudo password in `machine=personal|ID=%6|pane=4.1`." After he says done, capture until the last line is the laptop prompt again:

```zsh
zsh $HOME/.claude/skills/ari-driving-remote/bin/run.zsh --host-definition laptop --target %6 --cmd ''
```

### Type a command for Ari to run

```zsh
zsh $HOME/.claude/skills/ari-driving-remote/bin/run.zsh --host-definition laptop --target 4.1 --no-enter --cmd 'brew upgrade'
```

Chat: "Typed into `machine=personal|ID=%6|pane=4.1`; press Enter when ready." After he says he did, capture; never resend.

### Poll a long run

`--no-wait` returns right after typing. Then one capture per response, telling Ari the last line each time it changes, until the prompt shows; Ctrl-C is his.

### Add or describe a host

A host never driven before: `--host-definition NAME --host user@host`, plus `--path-prefix ''` on Linux (the default is Homebrew's `/opt/homebrew/bin`) and `--prompt-end` when the prompt does not end in `❯`. `BatchMode` ssh cannot accept a host key or a password, so Ari first runs `ssh user@host` once in a pane. The first `--describe`, `--list` or `--cmd` writes the definition:

```zsh
zsh $HOME/.claude/skills/ari-driving-remote/bin/run.zsh --host-definition pi --host pi@pi.local --describe 'Pi 4 B at 192.0.2.94, no tmux; reached from the laptop with a nested ssh -t'
```

`--describe` does not connect, and it replaces the text. It describes the machine, never a window or pane (see Host definitions). Ari later says "the Pi is on .102 now"; write back the merged text, then say `was: … → now: …`:

```zsh
zsh $HOME/.claude/skills/ari-driving-remote/bin/run.zsh --host-definition pi --describe 'Pi 4 B at 192.0.2.102 (static lease), no tmux; reached from the laptop with a nested ssh -t'
```

A host Ari says is gone: `--host-definition NAME --forget --dry-run` shows what goes, then `--forget` deletes it.

## Setup (once per host)

The host needs tmux, `~/.config/bin/ari-driving` (`/ari-driving-tmux` Setup) and, for captures, `~/.config/bin/run_log` from the dotfiles; a Mac also needs `/opt/homebrew/bin` on the pane's PATH, or `--path-prefix`. Ari accepts the host key once with `ssh user@host`.

## File storage

- `bin/run.zsh` — every host action; `--help` lists the flags and defaults. It needs the logging library from `/ari-skill-shellscripts` and exits without it.
