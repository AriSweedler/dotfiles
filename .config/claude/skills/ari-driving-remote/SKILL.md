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
    - **One pane per branch or fork.** `run.zsh` binds a pane to the Claude session that first types into it and refuses every other session with 76; a session that must drive gets a pane of its own (**Create a pane for yourself**). When Ari explicitly makes two sessions share a pane, capture (`--cmd ''`) immediately before every send and read only from your own `TYPED:` echo down.
    - **Every pane mention carries the whole label**, `machine=personal|ID=%6|pane=4.1`, in inline code, never linked, never one part alone.
    - **NEVER start or chain `clear`, `reset` or `tmux clear-history`**; raise `--lines` to see more. `run.zsh` refuses a leading `clear`. Above the pane's tmux `history-limit`, `--lines` returns fewer lines with no marker; a capture whose top lacks the `TYPED:` echo outgrew the pane, so read the host's `/tmp/run_log/<dir>/stdout.plain` in slices (`wc -l`, then `sed -n`) instead of raising `--lines` again.
    - **NEVER `pbcopy` on his machine**; `run.zsh` refuses it in `--cmd`.
    - **Claude never sets the opt-in.** Not `ari-driving on`, `ari-remote-tmux on` or `@ari_driving`: typed, linked, chained, in a pane's startup command, through the Bash tool, or through a fork, subagent or other session. `run.zsh`, `link.zsh` and the click handler refuse any command that spells them; a self-set opt-in is undone with `ari-driving off` there, and Ari is told which pane.
- **`--hosts` first.** The first `run.zsh` call of a conversation, and the first after compaction, MUST be `--hosts`. Never guess a name or a `user@host`; read them from its output.
- **Before every non-empty `--cmd`, the bare command goes in chat, in the same message**, headed by the pane's label from the latest `--list`. `run.zsh` adds the `run_log` wrapper itself and prints `TYPED:` with the exact text it sent. Captures (`--cmd ''`) and `--list` need no block.
- **One `--cmd` per prompt.** Several commands chain with `&&` or `;` inside one `--cmd`; keys sent while a command runs are eaten by it. Directory state persists in the pane, so prefer absolute paths.
- **Exit 124 means still running, not failed**, as after `--no-wait` or a Bash-tool timeout. NEVER resend; the only call on that pane until the prompt returns is a capture, `--cmd ''`.
- **Exit 77, 76 or 75: nothing was typed; exit 1 with no `PANE:` line: nothing was connected.** NEVER work around a refusal: no other `--target` Ari did not name, no `--no-run-log`, no ssh of your own. 77: print the command under its label, Ari runs `ari-driving on` there, resend after he says so. 1: tell Ari what was dropped and why; never resend it.
- **"Turn it on for me" is declined.** The command goes to Ari under the pane's label; the opt-in stays his.
- **Say when you are cut off, then stop.** A required read with no pane to make it in (the only opted-in pane holds un-entered text, or is bound to another session) is reported as exactly that: which pane, what it holds, what is cut off (the beads tracker, a deploy), and that clearing it is a P0 for Ari. Nothing else happens that turn: no other pane, no workaround, no guess at what the read would have said.
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

### The text check

Before connecting, `run.zsh` reads `--cmd` itself and exits 1, with no `PANE:` line, when the text has a newline or control character, starts with `clear`, has `pbcopy` anywhere, or spells the opt-in: `ari-driving on`, `ari-remote-tmux on` or `@ari_driving`, case and quotes ignored, refused whether it sets, reads or quotes it. The rule binds, not the filter; opt-in state is read from `--list`, never from the option itself.

```
[ERROR] Refusing --cmd; nothing typed | reason='spells the opt-in (ari-driving on or @ari_driving); refused whether it sets, reads or quotes it'
```

→ tell Ari what was dropped and why; never resend it.

### The gate

Every non-empty `--cmd`, before any key and under a per-pane lock: the pane is opted in (its option `@ari_driving` is on, set by Ari's `ari-driving on` there); it is not in copy mode or synchronized; the foreground command is a shell; the last non-blank line ends in `prompt_end`. A failure prints `REFUSED: <label> <why>` and the pane tail, types nothing, and exits 77 or 75:

```
PANE: machine=personal|ID=%6|pane=4.1
REFUSED: machine=personal|ID=%6|pane=4.1 not opted in; Ari runs 'ari-driving on' in that pane
```

→ "`machine=personal|ID=%6|pane=4.1` isn't marked. Run `ari-driving on` there and say so, or run this yourself:" plus the fenced command.

```
REFUSED: machine=personal|ID=%6|pane=4.1 running vim, not a shell
```

→ "`machine=personal|ID=%6|pane=4.1` is in vim. The command, for when it is free:" plus the fenced command. No retry.

After the gate, the binding: the pane belongs to the Claude session (`$CLAUDE_CODE_SESSION_ID`) that first typed into it, recorded under `~/.local/state/ari-driving-remote/bindings/<definition>/<pane>`. A `/branch` or a fork is a new session, so it is refused with exit 76:

```
REFUSED: machine=personal|ID=%18|pane=3.1 bound to another Claude session ad00f077; get a pane of your own
```

→ do not type there; ask Ari for a pane (**Create a pane for yourself**), or report the cut-off. No flag unbinds. Ari rebinds by running `ari-driving on` in the pane again (it stamps `@ari_driving_since`; a stamp newer than the binding's voids it), after which the next session to type owns it.

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
| 77 | pane not opted in; nothing typed | print the command under its label; Ari runs `ari-driving on` there; resend after he says so |
| 76 | pane bound to another Claude session; nothing typed | ask Ari for a pane of your own (**Create a pane for yourself**); only his `ari-driving on` there rebinds it |
| 1 | the text refused before connecting, no `PANE:` line: a control character, a leading `clear`, `pbcopy`, or it spells the opt-in | tell Ari what was dropped and why; never resend it |
| 75 | pane busy: copy mode, synchronized, not a shell, text on the line, or another caller typing; nothing typed | print the command under its label; never retry on your own |
| 70 | no pane matches, no attached client to resolve `2.4` against, or no tmux server | read the `PANES:` lines under the refusal (every pane on the host, live), pick the one Ari means or ask him; `--list` only for the ✦ marks; or `--session S` |
| 127 | tmux not on the host's PATH | `--path-prefix ''` (Linux) or its dir; then `--describe` the fix |
| 255 | ssh could not connect before anything was typed | Ari runs `ssh user@host` once in a pane (key, sleep); retry only after he says done |
| any other code, 141 among them | `run.zsh` died locally; when `TYPED:`/`SENT` printed, or nothing printed after a `--cmd`, the pane may have run the command | `--cmd ''` to capture; never resend |

### Pitfalls

| What happens | What to do |
|---|---|
| a `--cmd` with a newline is typed as several commands; the gate refuses or the shell breaks | ship multi-line text as a file: `printf %s '<base64>' \| base64 -d > /tmp/x` with `--no-run-log`, then run the short command |
| `run_log` names its capture dir after the command's first words; a very long first word fails with "File name too long" before running | keep the first words short (`cd ~/x && …`), or `--no-run-log` |
| in the pane's zsh, `. .env` looks the bare name up on `PATH` and loads nothing | `. ./.env`, or the full path |
| a local loop calling `run.zsh` runs only its first iteration: ssh eats the loop's stdin | `</dev/null` on every call inside a loop |
| the permission classifier tends to refuse a typed `docker run`; `docker exec` and `curl` pass | probe through a published loopback port or `docker exec`; hand a `docker run` to Ari |
| a refusal prints before `SENT`, so a filter that keys on the command text sees nothing | filter output on `^SENT`; an empty filtered result means capture (`--cmd ''`) before any retry |

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
machine=personal|ID=%6|pane=4.1 ✦ bound=this zsh 0: pi -- laptop
machine=personal|ID=%7|pane=4.2 - bound=none vim 0: pi -- notes.md
```

✦ means Ari opted the pane in, `-` that he did not; `bound=` says which Claude session owns it (`this`, `other`, `none`); the next field is its foreground command. Only a pane with ✦ and `bound=this` or `bound=none` is yours to type into. A pane running anything but a shell (`ssh`, `vim`, `less`) refuses with 75. The `local` definition's lines carry no `machine=` prefix.

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

### Create a pane for yourself

Only on Ari's words this turn ("make yourself a pane"). Another session driving the only pane is a reason to ask him for one, not to create one. `--list` first, so a pane he already made is reused, not doubled. Never with the opt-in inside: `tmux new-window … "zsh -ic 'ari-driving on; …'"`, `tmux set-option -p … @ari_driving on` and every other spelling are refused, because the opt-in is Ari's. The plain window, in the background so his view stays put:

`machine=personal|ID=%18|pane=3.1`
```zsh
tmux new-window -d -n claude-homelab -c ~/homelab
```

`--list` again for the new pane's label. Chat: "Created window `claude-homelab` in the background: `machine=personal|ID=%35|pane=5.1`. Run `ari-driving on` there and say so." Nothing is typed there until `--list` shows ✦ and `bound=none` or `bound=this` on it. A fork sent to drive is told which pane it owns, and the parent stops driving that pane while the fork lives.

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
- `tests/run-large-capture.test.zsh` — run after any edit to `run.zsh` that touches how host output is read or printed (`run_command`, `execute_script`, the BIND scan): `zsh $HOME/.claude/skills/ari-driving-remote/tests/run-large-capture.test.zsh`. Self-contained: it puts its own fake `ssh` on PATH that answers a `--cmd` run with a capture larger than a pipe buffer; no tmux, no network. Passes when the last line is `N passed, 0 failed` and it exits 0; a failure is the SIGPIPE regression (exit 141, nothing printed) or a sibling of it.
