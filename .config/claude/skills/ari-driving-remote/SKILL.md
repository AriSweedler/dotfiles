---
name: ari-driving-remote
description: "Drive a tmux pane on another machine over ssh: type each command into the pane Ari named, wait for his shell prompt, read the pane back. Hosts are remembered as named definitions (user@host, prompt, panes, what Ari said about them). Every send is gated: the pane must be marked `ari-driving on` and idle at his prompt, or nothing is typed. Content (a bead body, a script, anything multi-line or over 200 bytes) goes over as a file with `--put FILE --project DIR`, never as keystrokes. Part of /ari-driving; use when Ari names his laptop, a Pi, a host or a definition, or says to run something over there. Never raw tmux send-keys; never pbcopy unless Ari asks."
---

# Driving remote

Claude runs nothing on another machine except by typing into the pane Ari named, through `bin/run.zsh`, which gates the send, waits for his prompt and prints the pane; content goes over as a file, `run.zsh --put FILE --project DIR`, never as keystrokes. Hosts are remembered as named definitions.

## Rules

- **`/ari-driving` Rules apply.** If its text is not in your context now (a new conversation, or a compaction summary standing where it was), invoke it first (Skill tool); a summary saying it ran does not count. These hold even without it:
    - **NEVER run `tmux send-keys` yourself, here or as `ssh host tmux …`.** A host gets exactly two things from Claude: a command, typed by `run.zsh --cmd`, and content, copied by `run.zsh --put FILE --project DIR` (**Put a file on the host**). Nothing else runs on the host over ssh.
    - **Content goes by `--put`, never by `--cmd`, whatever carries the send.** Content is more than one line, over 200 bytes, or the value of a body, description or message flag (a bead body, a script, a config, a commit message); the trigger is the text's size and shape, not the transport: that `run.zsh` pastes a long command as a heredoc (**The typed text**) changes nothing here. NEVER encode, chunk, heredoc or `printf > FILE` it through `--cmd`: tmux dropped bytes from long sends (a 3,000-byte base64 chunk lost 8 on 2026-10-30), a pasted body still lands in shell history, the capture and `run_log`'s dir name, and `run.zsh` refuses a `base64 -d` and a newline.
    - **Every `--put` names `--project`, and the name is the thing, not the container.** The project's first segment is the repo or system the file belongs to (the checkout the follow-up `--cmd` runs in, `homelab`; else the definition name); one optional second segment names the subsystem when the host has a dir or tool for it (`homelab/beads`, `homelab/torrent`); never a third, never a date, a session id, `tmp`, `scratch` or `claude`; the same work keeps the same project for the whole conversation. `--name` defaults to the file's basename without its last extension (`swap.py` → `swap`, `queue.tar.gz` → `queue.tar`, `.env` → `.env`); keep it when it says what the file is, and pass a lowercase hyphenated name over `body`, `script`, `out`, `tmp` or `file`.
    - **A pane from earlier in the conversation or a compaction summary is a hint.** Re-run `--list` and use it only if it still shows `✦`, a shell, and `bound=this` or `bound=none`.
    - **One pane per branch or fork.** `run.zsh` binds a pane to the Claude session that first types into it and refuses every other session with 76; a session that must drive gets a pane of its own (**Create a pane for yourself**). When Ari makes two sessions share a pane, he runs `ari-driving on` there before each hand-off (that rebinds it); capture (`--cmd ''`) immediately before every send and read only from the pane's last copy of your `TYPED:` text down (its first line, compared to your `TYPED:` block's; an earlier look-alike block is the other session's). A fork sent to drive is told which pane it owns, and the parent stops driving that pane while the fork lives.
    - **Every pane mention carries the whole label**, `machine=personal|ID=%6|pane=4.1`, in inline code, never linked, never one part alone.
    - **NEVER start or chain `clear`, `reset` or `tmux clear-history`**; raise `--lines` once; a top still lacking the pane's copy of the typed text (**The typed text**) outgrew the pane (**Pitfalls**). `run.zsh` refuses a leading `clear`.
    - **NEVER `pbcopy` on his machine**; `run.zsh` refuses it in `--cmd`.
    - **Claude never sets the opt-in.** Not `ari-driving on`, `ari-remote-tmux on`, `@ari_driving` or `ari-driving release`: typed, linked, chained, in a pane's startup command, through the Bash tool, or through a fork, subagent or other session. `run.zsh`, `link.zsh` and the click handler refuse any command that spells the first three; a self-set opt-in is undone with `ari-driving off` there, and Ari is told which pane. Decline "turn it on for me": the command goes to Ari under the pane's label.
- **Every call that acts carries `--execute`; without it the call is a dry run and nothing happens.** `--dry-run` is that default said aloud and wins over `--execute`; NEVER pass it yourself.
    - `--cmd TEXT`: a dry run resolves the pane, runs the gate and the binding check, prints under `WOULD TYPE:` the exact text the host would paste, then the pane tail, then `DRY RUN: nothing was typed`, and types nothing. Add `--execute` after the announcement; no further yes, Ari's `ari-driving on` is the grant.
    - `--put` of a file Claude wrote this session: `--execute` on the first call. A dry run checks the local file, project and name only; the host's refusals show with `--execute`.
    - `--put` of a file Ari named: the dry run first, then `--execute` only on his yes in a later turn.
    - `--describe`: `--execute` on the first call when Ari stated the fact; quote `was: … → now: …` with it. `--forget`: the dry run, then `--execute` on his yes in a later turn.
    - `--hosts`, `--cmd ''` and `--list` read and take neither flag; `--list` also saves the panes and a new definition (the skill's own state).
    - A dry run is never the announcement: the `--execute` call is announced directly above it, even right after a dry run of the same text.
- **`--hosts` first; `--list` before the first `--cmd`.** The first `run.zsh` call of a conversation, and the first after a compaction summary, MUST be `--hosts`; `--describe` follows it when Ari said something about a host; `--list` of the named definition comes before the first `--cmd` into a pane. `--put`, `--describe` and `--forget` need only `--hosts`. Never guess a definition name or a `user@host`; read them from `--hosts`.
- **MUST announce every `--cmd` that types: in the same message, directly above its Bash call, the pane's label from the latest `--list` in inline code, then the text inside `--cmd '…'` in a fenced `zsh` block, one line, character for character** (**Run a command** shows the shape). The label line also names what differs from a plain send: `--no-enter`, `--no-run-log`, a raised `--timeout`. No exception: the one most often dropped is the first `--cmd` after compaction, when the command comes straight from the summary, so `--list` prints a `NEXT:` reminder for it. A call that types nothing needs none: `--cmd ''` (or only whitespace), a dry run (no `--execute`), `--list`, `--put`. After a refusal (77, 76, 75, 70) the next chat line says nothing was typed; the announced block stands as the command Ari runs, never reprinted in that message; a later resend is announced again.
  - **The announced block is the one line you pass `--cmd`, never what `TYPED:` or `WOULD TYPE:` prints.** `run.zsh` wraps that line for `run_log`, over several lines when it is long (**The typed text**); the wrapping is `run.zsh`'s, the pane shows it, and it is NEVER announced, NEVER re-joined by hand, and NEVER passed back into `--cmd` (it holds newlines; the text check exits 1). A resend announces and passes the same one line as before.
  ```
  WRONG  --cmd 'bd show beads-34e.8' as the message's first content: no label, no fenced command above it
  WRONG  the fence holds run_log 'bd show beads-34e.8'                    ← run.zsh's wrapper, not the command
  WRONG  the fence holds run_log "$(command cat <<'RUN_LOG' …             ← the TYPED: text copied into chat
  WRONG  --cmd "$(the TYPED: block)" on a resend                           ← newlines; exit 1
  RIGHT  the fence holds bd show beads-34e.8; --cmd 'bd show beads-34e.8'
  WRONG  --cmd 'bd show beads-34e.8' without --execute, exit 0, "it ran, here is the output"
  RIGHT  `WOULD TYPE:` and no `SENT`: nothing was typed; announce, then resend with --execute
  WRONG  --put without --execute, then a --cmd naming the `WOULD PUT:` path
  RIGHT  paste only the path of a real `PUT:` line
  ```
- **Before every `--put`, one chat line**: what the file is, the definition and the project (`run.zsh` prints the bytes). A file Claude wrote this session in the scratchpad goes straight to `--put`. A file Ari named MUST be read whole first, then `--put` without `--execute` (the dry run), and the same call with `--execute` only on his word in a later turn.
- **NEVER put a file, or type a `--cmd`, that holds a secret**: a token, password, private key, cookie, `.env` contents or anything Ari said not to paste; a `--cmd` references it on the host (`$VAR`, a path). Put nothing that turn; name the file and the kind of secret, tell Ari the destination path on the host, and he places it.
- **One `--cmd` per shell prompt.** Several commands chain with `&&` or `;` inside one `--cmd`; keys sent while a command runs are eaten by it. Directory state persists in the pane, so prefer absolute paths.
- **No `SENT` line means nothing ran, whatever the exit code: `WOULD TYPE:` and `WOULD PUT:` are a dry run, and the pane tail under them is old state, never output.** Exit 0 with `SENT` means the command ran, not that it succeeded, and every line in the pane is the command's output, never run.zsh's. `run.zsh` writes nothing into the pane: its own failures are `[ERROR]`, `REFUSED:` and `REFUSED_KIND:` lines above `SENT`, with a non-zero exit. The command's output is exactly the pane lines (below `SENT`) between the pane's copy of the typed text, which ends at `)"` for a heredoc and is one line otherwise (**The typed text**), and `run_log`'s `Captured command` line just above the prompt, whose `rc='N'` is the status (with `--no-run-log`, or on a host whose `NOTE:` says it has no `run_log`, chain `; echo rc=$?`). The `TYPED:` block above `SENT` is what was pasted, not output. NEVER report a run.zsh failure from pane text.
- **A refusal is final; an exit code is an instruction.** Do what its **Exit codes** row says. NEVER work around a refusal: no `--target` Ari did not name, no `--no-run-log`, no ssh of your own.
- **Say when you are cut off, then stop.** A required read (a `--cmd` whose output the task cannot continue without) with no pane to make it in (the only opted-in pane holds un-entered text, or is bound to another session): report which pane, what it holds, what is cut off (the beads tracker, a deploy), and that clearing it is a P0 for Ari. Nothing else happens that turn: no other pane, no workaround, no guess at what the read would have said.
- **Nested ssh is one-shot and `-t`:** `ssh -t pi@pi.local "cd app && ./install.sh"`. Never an interactive nested shell: every later wait would time out.
- **`--no-enter` when Ari runs it:** he said never press Enter, the harness denied the command, or it mutates and he has not allowed it. Tell him it is on his prompt line; nothing else goes into that pane until he says he pressed Enter or cleared it.
- **Save what Ari says about a host before the next `--cmd`.** A username, an address, how it is reached, what it is for, a correction: the next `run.zsh` call after `--hosts` MUST be `--describe`. It REPLACES the whole description, so the text is the one `--hosts` printed with his words folded in, never his words alone; then quote `was: … → now: …` in chat.
- **`--host` only for a name absent from `--hosts`.** `run.zsh` refuses it on an existing name unless Ari said the address changed; then `--re-point`.

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

`windows` holds each pane's label from the last `--list`; `last_seen` the last run that answered. `description` describes the machine: what it is, how it is reached, what only it can do. It never names a window or a pane; those change daily. Two seeds: `laptop`, written when no definition exists, and `local` (`host=local`: tmux here, no ssh; a `--put` runs the same host script here). A definition whose description says it has no tmux (the Pi) is a record, not a target: run through the host it says it is reached from, and forward files from there (**Put a file on the host**, the last paragraph).

### The text check

Before connecting, `run.zsh` reads `--cmd` itself and exits 1, with no `PANE:` line, when the text has a newline or control character, starts with `clear`, has `pbcopy` anywhere, decodes content (`base64 -d`, `--decode` or `-D`), or spells the opt-in (`ari-driving on`, `ari-remote-tmux on` or `@ari_driving`, case and quotes ignored, refused whether it sets, reads or quotes it); and when `CLAUDE_CODE_SESSION_ID` is unset (not a Claude session: report it as cut off, never set it). The rule binds, not the filter; opt-in state is read from `--list`, never from the option itself.

```
[ERROR] Refusing --cmd | reason='contains a newline or control character; chain with && or ; on one line'
```

→ two commands: chain them on one line. Content: **Put a file on the host**; never flatten or encode it.

```
[ERROR] Refusing --cmd; nothing typed | reason='spells the opt-in (ari-driving on or @ari_driving); refused whether it sets, reads or quotes it'
```

→ tell Ari what was dropped and why; never resend it.

### The typed text

`run.zsh` hands the one line to `run_log` when the host has `~/.config/bin/run_log` (else `NOTE: no … on the host; typed the command bare` and the bare line; `--no-run-log` types it bare), in the form a `/ari-driving-tmux` run link types, from that skill's `lib/wrap.zsh` (`wrap_run_log_text`; its **Command layout** owns the rule): `run_log 'cmd'` when the command has no single quote; `run_log "cmd"` when it has single quotes and none of `"` `$` `` ` `` `\` `!`; otherwise, and whenever it is laid out (over 100 characters, or a quoted argument over 40), the quoted heredoc below. `run.zsh` never escapes a single quote as `'\''`; pass the command as Ari would type it, quotes included. The text goes in as one bracketed paste, so `TYPED:` spans its lines, up to `SENT`, and the pane shows the same lines; a text over several lines goes into a zsh pane only (**The gate**, `not_zsh`).

| `--cmd` | typed |
|---|---|
| `diskutil list external physical` | `run_log 'diskutil list external physical'` |
| `rg 'foo' src` | `run_log "rg 'foo' src"` |
| `pgrep -fl 'app.py$'` (single quotes and a `$`), or any line over 100 characters | the heredoc |

```
PANE: machine=personal|ID=%6|pane=4.1
TYPED: run_log "$(command cat <<'RUN_LOG'
pgrep -fl 'app.py$'
RUN_LOG
)"
SENT
~ ❯ run_log "$(command cat <<'RUN_LOG'      ← the pane's copy of the typed text, not output
pgrep -fl 'app.py$'
RUN_LOG
)"
48213 python3 app.py                        ← output starts after the )" line
Captured command … rc='0'                   ← the status
~ ❯
```

A call without `--execute` runs the gate on the host, which prints under `WOULD TYPE:` the text verbatim, in the form it would paste (the `run_log` form when the host has `run_log`, else bare). Use it before a `--cmd` that holds `"`, `$`, a backtick, `\`, `!`, or is over 100 characters.

### The gate

Every non-empty `--cmd`, before any key and under a per-pane lock: the pane is opted in (its option `@ari_driving` is on, set by Ari's `ari-driving on` there); it is not in copy mode or synchronized; the foreground command is a shell; the last non-blank line ends in `prompt_end`. A failure types nothing, exits 77 or 75, and prints `REFUSED: <label> <why>`, then `REFUSED_KIND: <kind>`, then the pane tail. **Classify a refusal by its exit code, then by the `REFUSED_KIND:` line right after `REFUSED:`; never by the `REFUSED:` words, which may change, nor by a kind line further down, which is old pane text.** Only 77 and 75 carry a kind. After saying nothing was typed (the announced block stands, never reprinted), each kind's next action:

| Kind | Exit | The pane | Next action |
|---|---|---|---|
| `not_opted_in` | 77 | not marked | Ari runs `ari-driving on` there; resend, announced again, after he says so |
| `other_caller` | 75 | another session or click holds its lock | `--cmd ''` to read what it typed; a pane another session drives is not yours (Rules, **One pane per branch or fork**) |
| `copy_mode` | 75 | in copy mode | Ari presses `q` there; resend after he says so |
| `synchronized` | 75 | synchronize-panes is on | Ari turns it off; resend after he says so |
| `not_a_shell` | 75 | a program in front (vim, ssh) | the command is his for when it is free; no retry |
| `not_at_prompt` | 75 | its last line does not end in `prompt_end` | read the tail's last line: the prompt with text after it, or a last line of `)"`, `RUN_LOG` or one ending in ` \` (a laid-out `--no-enter` text still on the line), is un-entered text, Ari presses Enter or clears it; an idle prompt ending in something else, ask Ari and pass `--prompt-end`; anything else is a running command, his for when it is free |
| `pane_gone` | 75 | the pane closed, or tmux could not read it | `--list`, then as for 70 |
| `lock_unavailable` | 75 | the lock root is unwritable, or a stale lock will not clear | the host's lock root (default `/tmp/ari-driving-locks`) is the problem, not the pane: tell Ari; no retry |
| `not_zsh` | 75 | the text spans lines (**The typed text**) and the pane's shell is not zsh | the command is Ari's as the announced block, or he names a zsh pane; never `--no-run-log` to dodge it |
| `unknown` | 75 | the lib refused without a kind | quote the `REFUSED:` words to Ari, treat the pane as busy, and invoke `/ari-skill-update ari-driving-remote`: `tmux_pane_gate_check` refused without setting `ARI_DRIVING_GATE_KIND` |

```
PANE: machine=personal|ID=%6|pane=4.1
REFUSED: machine=personal|ID=%6|pane=4.1 not opted in; Ari runs 'ari-driving on' in that pane
REFUSED_KIND: not_opted_in
```

→ "`machine=personal|ID=%6|pane=4.1` isn't marked; nothing typed. Run `ari-driving on` there and say so, or run the command above yourself."

```
PANE: machine=personal|ID=%6|pane=4.1
REFUSED: machine=personal|ID=%6|pane=4.1 running vim, not a shell
REFUSED_KIND: not_a_shell
```

→ "`machine=personal|ID=%6|pane=4.1` is in vim; nothing typed. The command above, for when it is free." No retry.

After the gate, the binding: the pane belongs to the Claude session (`$CLAUDE_CODE_SESSION_ID`) that first typed into it, recorded under `~/.local/state/ari-driving-remote/bindings/<definition>/<pane>`. A `/branch` or a fork is a new session, so it is refused with exit 76:

```
REFUSED: machine=personal|ID=%18|pane=3.1 bound to another Claude session ad00f077; get a pane of your own
```

→ do not type there; ask Ari for a pane (**Create a pane for yourself**), or report the cut-off. No flag unbinds. Ari rebinds by running `ari-driving on` in the pane again, after which the next session to type owns it.

A pane that closed since it was last seen, or during the gate, fails the same exact check, with exit 70, no kind, and the host's live panes under the refusal:

```
REFUSED: no pane matches %6
PANES: every pane on the host, label command session: window -- title
machine=personal|ID=%3|pane=1.1 zsh 0: caf -- laptop
machine=personal|ID=%18|pane=3.1 zsh 0: homelab -- laptop
```

→ name the candidate under its full label and ask Ari which pane he means; `--list` adds the ✦ marks when that matters.

### Exit codes

A `--cmd`:

| Code | Meaning | Claude's next action |
|---|---|---|
| 0 | `SENT` printed, then the shell prompt returned; the command ran (`WOULD TYPE:` and no `SENT`: a dry run, nothing typed) | read the lines between the pane's copy of the typed text and the `Captured command` line as the output; `rc='N'` there is the status (Rules, **No `SENT` line means nothing ran**) |
| 124 | still running: timeout, `--no-wait`, or ssh dropped after `SENT` | `--cmd ''` to capture; never resend |
| 77 | pane not opted in (`REFUSED_KIND: not_opted_in`); nothing typed | say nothing was typed; the announced block above is his to run after `ari-driving on` there; resend (announced again) after he says so |
| 75 | pane busy; nothing typed; `REFUSED_KIND:` says why (**The gate**) | say nothing was typed; then the kind's row in **The gate**; never retry on your own |
| 76 | pane bound to another Claude session; nothing typed | ask Ari for a pane of your own (**Create a pane for yourself**); only his `ari-driving on` there rebinds it |
| 73 | tmux could not paste the text; nothing is on the line (`FAILED: paste into …`) | resend once, announced again; a second failure goes to Ari with the label |
| 74 | the text is on the line, Enter did not reach it (`FAILED: Enter to …`) | tell Ari, as for `--no-enter`; nothing else goes into that pane until he pressed Enter or cleared it |
| 1 | the text refused before connecting, no `PANE:` line (**The text check**) | a newline or `base64 -d`: it is content, **Put a file on the host**; a leading `clear`: resend without it; `pbcopy`: print the text in chat; the opt-in: tell Ari what was dropped and why, never resend it; no session id: report it as cut off (Rules, **Say when you are cut off**) |
| 70 | no pane matches, no attached client to resolve `2.4` against, or no tmux server | read the `PANES:` lines under the refusal (every pane on the host, live), name the candidate under its full label and ask Ari which he means; `--list` only for the ✦ marks; or `--session S` |
| 127 | tmux not on the host's PATH | `--path-prefix ''` (Linux) or its dir; then `--describe` the fix, and say in chat what was saved |
| 255 | ssh could not connect before anything was typed | Ari runs `ssh user@host` once in a pane (key, sleep); retry only after he says done |
| any other code, 141 among them | `run.zsh` died locally; when `TYPED:`/`SENT` printed, or nothing printed after a `--cmd`, the pane may have run the command | `--cmd ''` to capture; never resend |

A `--put` (a failure prints no `PUT:` line; the `[ERROR]` line says which row):

| Code | Meaning | Claude's next action |
|---|---|---|
| 0 | `PUT: <path>` printed; the host's hash matched | paste the path whole into the follow-up `--cmd` |
| 1 | `--project` or `--name` malformed: missing, absolute, a bad character, `..` or a dots-only segment; or a pane or typing flag given with `--put` | yours to fix in the flags; nothing is reported to Ari |
| 1 | the file is missing, unreadable or empty | rewrite the scratchpad file, then put it |
| 1 | the host refused the path (`REFUSED:` line): the project path is a file, the dir belongs to another user, a symlink or a non-file sits at the path | the same flags fail the same way: another `--project` or `--name`, or the cleanup is a `--cmd` of Ari's |
| 1 | no sha256 tool on the host, or no `sh` (its login shell's `command not found: sh` sits above the `[ERROR]` line); nothing copied | tell Ari which host and what it needs: `sh`, and `sha256sum`, `shasum` or `openssl`; never re-put, it fails the same way |
| 1 | the host could not write the file; its message is above (`No space left`, `Permission denied`) | Ari gets the message, the remote and the local path, and the choice: fix the host and say "again", or copy it himself |
| 1 | hash mismatch, or a failure with no message | re-put once; a second failure goes to Ari with both hashes and the paths |
| 255 | ssh failed before or during the copy; nothing is at the path (the write lands in a `.part` file moved into place only when complete) | Ari runs `ssh user@host` once in a pane; re-put after he says done |

### Pitfalls

| What happens | What to do |
|---|---|
| A put without `--execute` prints `WOULD PUT:` with a path that does not exist yet | the path may draft the follow-up `--cmd`; nothing runs before a real `PUT:` |
| above the pane's tmux `history-limit`, `--lines` returns fewer lines with no marker; a capture whose top lacks the pane's copy of the typed text (its first line is `run_log '…'`, `run_log "…"` or `run_log "$(command cat <<'RUN_LOG'`; a laid-out text spends several lines before any output) outgrew the pane | read the host's `/tmp/run_log/<dir>/stdout.plain` in slices with a `--cmd` (`wc -l`, then `sed -n`), never with Read and never by raising `--lines` again |
| a capture is full of shell script and reads as a run.zsh failure | it is not: exit 0 and the prompt mean the command ran (Rules, **Exit 0 means the command ran**). A `pgrep -f PATTERN` or `ps … \| grep PATTERN` matched run.zsh's own `sh -c <script>`, whose argv holds the typed command; the command's real output is the lines between the `TYPED:` echo and the dump. Next time anchor on text that argv cannot end with (`pgrep -fl 'app.py$'`; on Linux `-fa`, since `-l` prints only the name there), or find a server by port: `lsof -t -nP -iTCP:PORT -sTCP:LISTEN`, on Linux `ss -ltnp 'sport = :PORT'` |
| `pkill -f PATTERN` with text the typed command holds kills run.zsh's own `sh -c` and the pane's `run_log` wrapper: the run reads as 124 or 255 and the server is still up; and a Mac lists a `python3 app.py` server as `Python app.py`, so `pkill -f 'python3 app.py'` matches nothing | kill the pid the port names (row above); a kill mutates, so it is Ari's unless he allowed it (Rules, `--no-enter`) |
| `run_log` names its capture dir after the command's first words; a very long first word fails with "File name too long" before running | keep the first words short (`cd ~/x && …`), or `--no-run-log` |
| in the pane's zsh, `. .env` looks the bare name up on `PATH` and loads nothing | `. ./.env`, or the full path |
| a local loop calling `run.zsh` runs only its first iteration: ssh eats the loop's stdin | `</dev/null` on every call inside a loop |
| the permission classifier refuses a typed `docker run`; `docker exec` and `curl` pass | probe through a published loopback port or `docker exec`; hand a `docker run` to Ari |
| a refusal prints before `SENT`, so a filter that keys on the command text sees nothing | filter output on `^(SENT\|REFUSED)`: a `REFUSED_KIND:` line is a refusal (**The gate**); an empty filtered result means capture (`--cmd ''`) before any retry |

```
WRONG  --cmd 'pgrep -fl "python3 app.py"'            ← also matches run.zsh's sh -c; the capture fills with script text
WRONG  --cmd 'pkill -f app.py'                        ← kills run.zsh's own sh -c; the run dies mid-capture
RIGHT  --cmd 'pgrep -fl "app.py$"'                   ← anchored on text the script's argv never ends with
RIGHT  --cmd 'lsof -t -nP -iTCP:8000 -sTCP:LISTEN'    ← the server by its port; kill that pid, on Ari's word
```

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

✦ means Ari opted the pane in, `-` that he did not; `bound=` says which Claude session owns it (`this`, `other`, `none`); the next field is its foreground command. Only a pane with ✦ and `bound=this` or `bound=none` is yours to type into. The `local` definition's lines carry no `machine=` prefix. The `NEXT:` line under the list is the announcement reminder, not a pane.

### Run a command

**MUST announce first** (Rules): the label, then the bare command in a fence, then the Bash call.

`machine=personal|ID=%6|pane=4.1`
```zsh
diskutil list external physical
```

```zsh
zsh $HOME/.claude/skills/ari-driving-remote/bin/run.zsh --host-definition laptop --target %6 --cmd 'diskutil list external physical' --execute
```

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

- `--target` takes the `%N` from the label. `W.P` resolves against the most recently attached client's session, so it can name another pane than the one `--list` showed.
- `PANE:` names the pane (the host's `dotfiles machine-name`, else the definition name); `TYPED:` is the exact text pasted, one line or several (**The typed text**); `SENT` means tmux took it; then the last 60 lines of the pane once the prompt is back. Read from below the pane's copy of that text down.
- `run.zsh` hands the command to `run_log` when the host has `~/.config/bin/run_log` (else `NOTE: … typed the command bare`), so the capture lands in the host's `/tmp/run_log`; `--no-run-log` types it bare.
- A remote capture dir is read with `--cmd 'cat <dir>/stdout.plain'`, never with Read.
- When you raise `--timeout` (default 90 s), the Bash tool's timeout MUST be higher.
- Check a tricky command's quoting, and the gate, with the same call minus `--execute`: the pane is resolved, the gate and the binding check run, and the host prints, under `WOULD TYPE:`, the exact text it would paste (**The typed text**); only the keys are withheld.

```
PANE: machine=personal|ID=%6|pane=4.1
WOULD TYPE:
run_log 'diskutil list external physical'
~ ❯
```

A command that asks something: the pane ends in `[sudo] password for pi:` with exit 124. Chat: "Type the Pi's sudo password in `machine=personal|ID=%6|pane=4.1`." After he says done, capture until the last line is the laptop prompt again:

```zsh
zsh $HOME/.claude/skills/ari-driving-remote/bin/run.zsh --host-definition laptop --target %6 --cmd ''
```

### Put a file on the host

Content (Rules): a file in the scratchpad, put, then a `--cmd` that names the path. The put takes `--host-definition`, `--project` and optionally `--name`, no `--target`: it types nothing, so it needs no pane and no opt-in. Chat first: "Putting the body of bead …, on laptop under `homelab/beads`."

| the file | `--project` | `--name` |
|---|---|---|
| a bead body for the laptop's tracker | `homelab/beads` | the bead's subject, `bead-frontier` (the file is `body.md`) |
| a script against the torrent stack | `homelab/torrent` | default, `swap` from `swap.py` |
| a patch for the dotfiles | `dotfiles` | default, from the file's name |
| a commit message for a repo | that repo's name | `commit-msg` |

```zsh
zsh $HOME/.claude/skills/ari-driving-remote/bin/run.zsh --host-definition laptop --put "$SCRATCHPAD/body.md" --project homelab/beads --name bead-frontier --execute
```

```
[INFO] Putting file on the host | host='me@laptop.local' file='…/body.md' bytes='1842' remote='/tmp/homelab/beads/bead-frontier.fda28b0aa7cecefe46e1de2efe0d645b0e8395010cc08ee89b2408188259482d.txt'
PUT: /tmp/homelab/beads/bead-frontier.fda28b0aa7cecefe46e1de2efe0d645b0e8395010cc08ee89b2408188259482d.txt
```

The path is `/tmp/<project>/<name>.<sha256 of the bytes>.txt`; `run.zsh` makes the project dir, hashes the copy on the host and prints `PUT:` only when the hash matches; a file already holding the bytes is left alone.

- **The path goes into the `--cmd` character for character**: all 64 hex digits, pasted from the `PUT:` line, never a glob, never the `[INFO]` line.
- **An edited file is a new put**: the same bytes land at the same path, so a changed body is a new path and the old one still holds the old text.
- **A put file keeps its name**: no `mv`, `cp` or `chmod +x`; run it with its interpreter in front (`zsh …txt`, `python3 …txt`) or hand it to a flag (`--body-file …txt`).
- **A path is named only in the conversation that printed it**: one from an earlier conversation or a compaction summary is re-put first (macOS clears `/tmp` entries untouched for three days). Removing a put file is a `--cmd` of Ari's; Claude never removes one.

Then the follow-up, announced the same way:

`machine=personal|ID=%6|pane=4.1`
```zsh
BEADS_ACTOR=claude bd create "Graph view: Frontier toggle" -t feature --body-file /tmp/homelab/beads/bead-frontier.fda28b0aa7cecefe46e1de2efe0d645b0e8395010cc08ee89b2408188259482d.txt
```

```zsh
zsh $HOME/.claude/skills/ari-driving-remote/bin/run.zsh --host-definition laptop --target %6 --cmd 'BEADS_ACTOR=claude bd create "Graph view: Frontier toggle" -t feature --body-file /tmp/homelab/beads/bead-frontier.fda28b0aa7cecefe46e1de2efe0d645b0e8395010cc08ee89b2408188259482d.txt' --execute
```

A script with the default name, and the interpreter in front:

```zsh
zsh $HOME/.claude/skills/ari-driving-remote/bin/run.zsh --host-definition laptop --put "$SCRATCHPAD/swap.py" --project homelab/torrent --execute
```

```
[INFO] Defaulting --name to the file's basename | name='swap'
PUT: /tmp/homelab/torrent/swap.2ab0a27e0f42849bd560d2c5f4295c79938895cfde87b9483e4ba379ded916c1.txt
```

`machine=personal|ID=%6|pane=4.1`
```zsh
python3 -I /tmp/homelab/torrent/swap.2ab0a27e0f42849bd560d2c5f4295c79938895cfde87b9483e4ba379ded916c1.txt
```

Wrong, the one-line forms that pass **The text check** and lose bytes or break quoting; right, the put:

```
WRONG  --cmd 'printf "import sys\nprint(sys.argv)\n" > /tmp/x.py && python3 /tmp/x.py'
WRONG  --cmd 'bd create "Title" --body "one line that will grow"'
RIGHT  a file in the scratchpad → --put … --project homelab/torrent → --cmd 'python3 -I /tmp/homelab/torrent/x.<sha>.txt'
RIGHT  a file in the scratchpad → --put … --project homelab/beads → --cmd 'bd create "Title" --body-file /tmp/homelab/beads/<name>.<sha>.txt'
```

A flag refused before connecting is yours to fix, not Ari's:

```
[ERROR] Missing --project | hint='the dir under /tmp the file lands in: the repo or system it belongs to, e.g. homelab or homelab/torrent'
[ERROR] Invalid --project | project='/tmp/homelab' expected='relative dir of letters, digits, . _ - and /; no leading /, no segment of dots only'
[ERROR] Invalid --name | name='bead frontier' expected='letters, digits, . _ -, not dots only'
```

→ `--project homelab`; `--project homelab`; `--name bead-frontier`.

The same call without `--execute` prints the path and copies nothing; nothing runs on the host before a real `PUT:`:

```
[INFO] would copy and verify | host='me@laptop.local' remote='/tmp/homelab/torrent/swap.2ab0a27e0f42849bd560d2c5f4295c79938895cfde87b9483e4ba379ded916c1.txt'
WOULD PUT: /tmp/homelab/torrent/swap.2ab0a27e0f42849bd560d2c5f4295c79938895cfde87b9483e4ba379ded916c1.txt
```

A host with no tmux (the Pi) is reached through the host that has its key: put the file there, then one `--cmd` there forwards it and runs it, the Pi getting the flat path:

`machine=personal|ID=%6|pane=4.1`
```zsh
scp /tmp/homelab/pi/install.<sha>.txt pi@pi.local:/tmp/ && ssh -t pi@pi.local "zsh /tmp/install.<sha>.txt"
```

### Type a command for Ari to run

Announced like any send, the label line saying `--no-enter`:

`machine=personal|ID=%6|pane=4.1`, `--no-enter`
```zsh
brew upgrade
```

```zsh
zsh $HOME/.claude/skills/ari-driving-remote/bin/run.zsh --host-definition laptop --target %6 --no-enter --cmd 'brew upgrade' --execute
```

Chat: "Typed into `machine=personal|ID=%6|pane=4.1`; press Enter when ready." When the `TYPED:` block spans lines: "Typed into `…` over N lines; one Enter runs it all, or clear the line." After he says he did, capture; never resend.

### Create a pane for yourself

Only on Ari's words this turn ("make yourself a pane"). Another session driving the only pane is a reason to ask him for one, not to create one. `--list` first, so a pane he already made is reused, not doubled. This `tmux` runs on this machine, for the `local` definition; on any other host ask Ari for the window, never `ssh HOST tmux new-window`. Never with the opt-in in the startup command: `run.zsh` refuses every spelling (Rules). The plain window, in the background so his view stays put:

`machine=personal|ID=%18|pane=3.1`
```zsh
tmux new-window -d -n claude-homelab -c ~/homelab
```

`--list` again for the new pane's label. Chat: "Created window `claude-homelab` in the background: `machine=personal|ID=%35|pane=5.1`. Run `ari-driving on` there and say so." Nothing is typed there until `--list` shows ✦ and `bound=none` or `bound=this` on it.

### Poll a long run

`--cmd '…' --no-wait --execute` returns right after typing. Then one capture (`--cmd ''`) per response, telling Ari the last line each time it changes, until the prompt shows; Ctrl-C is his.

### Add or describe a host

A host never driven before: `--host-definition NAME --host user@host`, plus `--path-prefix ''` on Linux (the default is Homebrew's `/opt/homebrew/bin`) and `--prompt-end` when the prompt does not end in `❯` (**Setup** first: Ari accepts the host key once). The first `--list` writes the definition at once; a `--describe`, `--cmd` or `--put` writes it with `--execute`:

```zsh
zsh $HOME/.claude/skills/ari-driving-remote/bin/run.zsh --host-definition pi --host pi@pi.local --describe 'Pi 4 B at 192.0.2.94, no tmux; reached from the laptop with a nested ssh -t' --execute
```

The same call without `--execute` logs `would write | file=… bytes=… mode='replace'` and saves nothing; an unchanged description logs `nothing to change`. `--describe` does not connect, and it replaces the text. It describes the machine, never a window or pane (**Host definitions**). Ari later says "the Pi is on .102 now"; write back the merged text, then quote `was: … → now: …`:

```zsh
zsh $HOME/.claude/skills/ari-driving-remote/bin/run.zsh --host-definition pi --describe 'Pi 4 B at 192.0.2.102 (static lease), no tmux; reached from the laptop with a nested ssh -t' --execute
```

A host Ari says is gone: `--host-definition NAME --forget` (the dry run) shows what goes, in chat; the same call with `--execute` deletes it on his yes, in a later turn.

## Setup (once per host)

The host needs tmux, `~/.config/bin/ari-driving` (`/ari-driving-tmux` Setup) and, for captures, `~/.config/bin/run_log` from the dotfiles; a Mac also needs `/opt/homebrew/bin` on the pane's PATH, or `--path-prefix`. `BatchMode` ssh cannot accept a host key or a password, so Ari accepts the host key once with `ssh user@host` in a pane. Every host script runs under `sh -c` inside the login shell, so the host needs `sh`, and a `--put` also `sha256sum`, `shasum` or `openssl`. The driven pane runs zsh: a laid-out command (**The typed text**) is refused into any other shell.

## File storage

- `bin/run.zsh` — every host action; `--help` lists the flags and defaults. It needs the logging library from `/ari-skill-shellscripts` and the shared `~/.config/claude/lib/tmux-pane.sh`, and exits without them; a run_log-wrapped `--cmd` also needs `/ari-driving-tmux`'s `lib/wrap.zsh` (that skill owns the form, **The typed text**) and refuses, untyped, without it.
- `~/.local/share/ari-driving-remote/hosts/<name>` — the host definitions, this machine only, never committed.
- `~/.local/state/ari-driving-remote/bindings/<definition>/<pane>` — which Claude session owns a pane.
- On the host: what `--put` lands (**Put a file on the host**), and `/tmp/run_log`, the captures.
- `tests/` — an edit to `bin/run.zsh` is done when every test below exits 0; an edit to the put path (`put_file`, `validate_put_args`, `host_put_script`, `report_put_exit`, `execute_script`, `local_hash_command`, `PUT_HASH_TOOLS`, the flags) also needs one real `--put` to a known definition printing `PUT:` (it types nothing and needs no pane): the 2026-10-31 fake passed under `/bin/sh` while the laptop's zsh failed the first real put. Each is self-contained, no tmux, no network, a fake `ssh` on PATH where a host is needed.
  - `zsh $HOME/.claude/skills/ari-driving-remote/tests/run-large-capture.test.zsh` — a `--cmd` capture larger than a pipe buffer is printed whole; a failure is the SIGPIPE regression (exit 141, nothing printed) or a sibling of it.
  - `zsh $HOME/.claude/skills/ari-driving-remote/tests/run-put.test.zsh` — the put path for real, into a throwaway project under `/tmp`, the fake `ssh` running the host script in zsh, a Mac's login shell: the path shape, the default name, every flag and host refusal, the no-op on a file already holding the bytes, the dry run (no flag, and `--dry-run` over `--execute`), a put that succeeded with an unwritable hosts dir.
  - `zsh $HOME/.claude/skills/ari-driving-remote/tests/run-typed-text.test.zsh` — a `--cmd` is pasted whole, in the form `/ari-driving-tmux`'s `wrap_run_log_text` gives, never `'\''`, as a fake `tmux` records; a text over several lines is refused into a non-zsh pane (`not_zsh`, 75); a failed paste is 73, a failed Enter 74; a call without `--execute` prints the text under `WOULD TYPE:` and pastes nothing; the bare forms (`--no-run-log`, a host without `run_log`); a capture pastes nothing.
  - `zsh $HOME/.claude/skills/ari-driving-remote/tests/run-refusal-kind.test.zsh` — each gate refusal prints its `REFUSED_KIND:` line right after its `REFUSED:` line, with the kind's exit code, one case per kind, the real `tmux-pane.sh` against a fake `tmux` on PATH (once over a fake `ssh`); the kind comes from the lib's `tmux_pane_gate_check`, not from the prose, and every kind the lib holds is named in `--help`; its fake `tmux` answers the buffer commands, so a pane that passes the gate is typed into. A `--cmd` without `--execute` prints `WOULD TYPE:`, types and binds nothing, and still hits the gate.
  - `zsh $HOME/.claude/skills/ari-driving-remote/tests/run-help.test.zsh` — `--help` exits 0 with `SCRATCHPAD` unset and under `env -i`, lists `--put`, `--cmd` and `--list`, and prints its examples literally: in `help()`, every environment variable (`$HOME`, `$SCRATCHPAD`, `$CLAUDE_CODE_SESSION_ID`) is written `\$NAME`; only the script's constants expand.
