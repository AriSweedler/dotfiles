---
name: ari-driving-remote
description: "Drive a tmux pane on another machine over ssh: type each command into the pane Ari named, wait for his shell prompt, read the pane back. Hosts are remembered as named definitions (user@host, prompt, panes, what Ari said about them). Every send is gated: the pane must be marked `ari-driving on` and idle at his prompt, or nothing is typed. Part of /ari-driving; use when Ari names his laptop, a Pi, a host or a definition, or says to run something over there."
---

# Driving remote

Ari watches one tmux pane per task on another machine and keeps its scrollback as the record. Claude runs nothing on that machine except through that pane: one script resolves the pane Ari named, checks that he marked it and that it is an idle shell at his prompt, types the command, waits for the prompt to return, and prints the pane. It does the two-shell quoting once and remembers every host as a named definition.

A *definition* is a named file; its *host* is a `user@host` (or `local`, below). The *shell prompt* is the idle line the script waits for; a *question* is anything a command asks before that line returns. Pane labels follow `/ari-driving` Rules; a remote label is never linked.

## Rules

- **Shared rules live in `/ari-driving`:** pane labels, hints not facts, no raw `send-keys`, the opt-in is Ari's, who runs what.
- **`--hosts` before anything else.** The first `run.zsh` call of a conversation MUST be `--hosts`. Never guess a name or a `user@host`; read them from its output.
- **Everything goes through `bin/run.zsh`**, one call per command; nothing else runs on the host over ssh, because Ari cannot see it.
- **Pass the address Ari said.** `--target 2.4` resolves to the pane ID in the host's most recently active session; `--session S` when he names another; a `%N` from `--list` also works.
- **The `--cmd` text goes in chat first.** Before each `--cmd` call, a fenced block with exactly the text that will appear on the prompt line, headed by the pane's label. Captures (`--cmd ''`) and `--list` need no block.
- **Exit 77 or 75 is a refusal.** 77: the pane is not marked; Ari runs `ari-driving on` there. 75: it is running something, or text sits on its prompt line. Never retry into it; print the command in chat.
- **One send per command.** Chain with `&&` or `;`: keys sent while a command runs are eaten by it. Directory state persists in the pane, so prefer absolute paths.
- **Exit 124 means still running, not failed**, as after `--no-wait` or a Bash-tool timeout. NEVER resend; the only call on that target until the prompt returns is a capture, `--cmd ''`.
- **Nested ssh is one-shot and `-t`:** `ssh -t user@host "command"`. Never an interactive nested shell: its prompt does not end in the definition's `prompt_end`, so every later wait times out.
- **No `clear`, `reset`, or `tmux clear-history`.** The scrollback is the record; raise `--lines` to see more.
- **`--no-enter` when Ari runs it.** Ari said never press Enter, or the harness denied the command: type it with `--no-enter` and tell him it is on his prompt line; never rephrase a denied command past the classifier. Nothing else goes into that pane until he says he pressed Enter or cleared it. Never `pbcopy` on his machine; clipboard rules are `/ari-driving-tmux`'s.
- **Save what Ari says about a host as he says it.** A username, an address, how it is reached, what it is for, a correction: the next `run.zsh` call MUST be `--describe`, before any `--cmd`. `--describe` REPLACES the text: take the current description from `--hosts`, fold the fact in, write the whole thing back.
- **`--host` only for a name absent from `--hosts`.** On an existing name it is refused unless Ari said the address changed; then `--re-point`.

## Input

A definition name (from `--hosts`), the pane as Ari said it (`2.4`), and the command as Ari would type it. For a host never driven before: `--host-definition NAME --host user@host`, plus `--path-prefix ''` on Linux (the default is Homebrew's `/opt/homebrew/bin`) and `--prompt-end` when the prompt does not end in `❯`. The first `--describe`, `--list` or `--cmd` writes the definition. `BatchMode` ssh cannot accept a host key or a password: Ari runs `ssh user@host` once in a pane first.

## Reference

### Host definitions

`${XDG_CACHE_HOME:-~/.cache}/ari-driving-remote/hosts/<name>`, one file per definition:

```
host=ari@laptop.local
path_prefix=/opt/homebrew/bin
prompt_end=❯
windows=ID=%3|pane=1.1 | ID=%4|pane=2.1 | ID=%6|pane=4.1
last_seen=2026-10-22T07:55:14Z
description=Personal MacBook, session 0. The only machine with an ssh key on the Pi: reach pi@pi.local by nesting ssh -t inside its pi window.
```

`windows` holds each pane's label from the last `--list`; `last_seen` the last run that answered. `--hosts` prints each file after a `name=<name>` line. Only the script writes these files. Two seeds: `laptop`, written when no definition exists, and `local` (`host=local`: tmux runs here, no ssh), written whenever it is missing; for a pane on this machine, prefer `/ari-driving-tmux`'s links and use `local` only when Claude itself must wait on the prompt and capture. A definition whose description says it has no tmux (the Pi) is a record, not a target: run through the host it says it is reached from. Local to the machine, not versioned.

### The gate

Every non-empty `--cmd`, before any key is sent: the pane option `@ari_driving` is `on`; the foreground command is a shell (zsh, bash, sh, fish); the last non-blank line ends in `prompt_end`. A failure prints `REFUSED: <label> <why>` and the pane tail, types nothing, and exits 77 or 75.

### Exit codes

0 the shell prompt returned. 124 the command is still running; the pane is printed. 77 the pane is not opted in. 75 the pane is busy or has text on its prompt line. 70 no pane matches the target, or no attached client to resolve `2.4` against (`--session`). 127 tmux not found on the host: `--path-prefix`. 255 ssh could not connect: asleep, wrong address, or Ari must accept the key.

## Workflow

### Read the known hosts

```zsh
zsh $HOME/.claude/skills/ari-driving-remote/bin/run.zsh --hosts
```

Then the live panes of the chosen definition. Each line is `ID=%301|pane=2.4 ✦ zsh session: window_name -- title`; ✦ marks a pane Ari opted in, `-` one he did not; then its foreground command. A pane showing `ssh`, `vim`, `less` or any non-shell command is not at a shell prompt:

```zsh
zsh $HOME/.claude/skills/ari-driving-remote/bin/run.zsh --host-definition laptop --list
```

### Run a command

```zsh
zsh $HOME/.claude/skills/ari-driving-remote/bin/run.zsh --host-definition laptop --target 4.1 --cmd 'ssh -t pi@pi.local "cd app && sudo ./install.sh"'
```

The output starts `PANE: ID=%6|pane=4.1`, then the last 60 lines of the pane once the prompt is back. Read from the line that echoes the command down to the final prompt; lines above it are history. Default `--timeout` is 90 s; raising it means also raising the Bash tool's timeout above it. `--dry-run` prints the host script, for checking the quoting of a tricky command.

Here the pane ends in `[sudo] password for pi:` with exit 124. Chat: "Type the Pi's sudo password in `ID=%6|pane=4.1`." Then capture until the last line is the laptop prompt again:

```zsh
zsh $HOME/.claude/skills/ari-driving-remote/bin/run.zsh --host-definition laptop --target %6 --cmd ''
```

### Type a command for Ari to run

```zsh
zsh $HOME/.claude/skills/ari-driving-remote/bin/run.zsh --host-definition laptop --target 4.1 --no-enter --cmd 'brew upgrade'
```

Chat: "Typed into `ID=%6|pane=4.1` on laptop; press Enter when ready." After he says he did, capture; never resend. The same shape hands a harness-denied command to Ari.

### Poll a long run

`--no-wait` returns right after typing. Then the capture above, once per turn, telling Ari the last line each time, until the prompt shows.

### Add or describe a host

```zsh
zsh $HOME/.claude/skills/ari-driving-remote/bin/run.zsh --host-definition pi --host pi@pi.local --describe 'Pi 4 B at 192.168.1.94, no tmux; reached by ssh -t from the laptop pi window'
```

`--describe` does not connect. Ari later says "the Pi is on .102 now": same turn, the merged text, not the new fact alone:

```zsh
zsh $HOME/.claude/skills/ari-driving-remote/bin/run.zsh --host-definition pi --describe 'Pi 4 B at 192.168.1.102 (static lease), no tmux; reached by ssh -t from the laptop pi window'
```

A host Ari says is gone: `--host-definition NAME --forget` prints the definition and deletes it.

## File storage

- `bin/run.zsh` — `--hosts`; `--host-definition NAME` with one of `--list`, `--cmd TEXT`, `--describe TEXT`, `--forget`; `--host USER@HOST|local`, `--re-point`, `--target W.P|%N|S:W[.P]`, `--session S`, `--no-enter`, `--no-wait`, `--lines N`, `--timeout S`, `--path-prefix DIR`, `--prompt-end STR`, `--dry-run`. `--help` has the defaults. Logging comes from `/ari-skill-shellscripts`; it refuses to start without it.
