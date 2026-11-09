---
name: ari-driving-tmux
description: "Hand Ari commands for a terminal on this machine and read the results back: a click-to-run link that runs the command in his tmux pane through run_log and returns him to Claude's pane with `run_log artifact: <dir>` pasted into its prompt, a click-to-type link, or a fenced block. Owns the run_log capture contract, the `ari-driving on|off|status` pane opt-in (on and off copy the pane's label), and every clipboard rule: never write it unasked, the pbcopy guard, Raycast recovery. Part of /ari-driving; use when Ari should run something here, says \"pane 2.4\" or \"type it into my pane\", or pastes a `run_log artifact:` line. Never raw tmux send-keys; never pbcopy unless Ari asks."
---

# Driving tmux

Claude never types into Ari's panes on this machine: it hands him a link to click, or a fenced block, and reads the `run_log` capture back. The one exception is `/ari-driving-remote`'s `local` definition, behind the same opt-in gate, for when Claude itself must wait on the prompt.

## Rules

- **`/ari-driving` Rules apply.** If its text is not in your context now (a new conversation, or a compaction summary standing where it was), invoke it first (Skill tool); a summary saying it ran does not count. These hold even without it:
    - **NEVER run `tmux send-keys`, `paste-buffer` or `load-buffer` at Ari's panes.** A command reaches a pane by Ari's click on a `link.zsh` link, or through `run.zsh` (`/ari-driving-remote`).
    - **A pane Ari did not name this turn is a hint.** Re-run `link.zsh --pane <hint>` before using it; after compaction, every pane in the summary is a hint. A hint that resolves to nothing is dropped, never replaced by a neighbour.
    - **Every pane mention carries both parts**, `ID=%301|pane=2.4`, never "pane 2.4" or `%301` alone. A label Ari pastes may start with `machine=<name>|`: run `dotfiles machine-name` (Bash) first.
        - the same name, or no `machine=` part → local: name it `ID=%N|pane=W.P`, `link.zsh --pane %N`;
        - another name → remote: keep the label whole, `/ari-driving-remote`.
    - **NEVER put `clear`, `reset` or `tmux clear-history` in a command**, leading or chained; `stdout.plain` already holds only this run. `clear && kubectl get pods` → `kubectl get pods`.
    - **NEVER write the clipboard unless Ari asked this turn**, and then only through `handoff.zsh --copy`. The PreToolUse guard blocks every other `pbcopy`; never write `HANDOFF_CLIP_OK=1` yourself, and never take another route after a denial.
    - **Claude never sets, clears or releases the opt-in.** Not `ari-driving on`, `ari-remote-tmux on`, `@ari_driving` or `ari-driving release`: typed, linked, chained, in a pane's startup command, through the Bash tool, or through a fork, subagent or other session. Exception: Ari's own `tmux-restart` types `ari-driving on`, without Enter, into panes opted in before the restart; Claude never runs it. An opt-in Claude set anyway is undone at once with `run.zsh … --cmd 'ari-driving off'` there (exit 70: the pane is already gone), Ari is told which pane, and `/ari-skill-update` follows. When Ari says a ✦ stays after a window's last marked pane closed, name the window; he runs `ari-driving release` there.
- **Every `tmux-pane://` URL is pasted from `link.zsh` stdout produced this turn.** NEVER type one by hand, even focus-only: `link.zsh` re-resolves the pane, encodes the command, and warns when a click would not type.
- **Hand `link.zsh` the one line; paste its blockquote unchanged.** `link.zsh` lays a long command out (**Command layout**) and the click types that same layout. NEVER reflow, re-indent or re-join the code block by hand, and NEVER pass `--cmd`/`--run` a multi-line command (it refuses the newline). The block shows the bare command: a `--run` click hands it to `run_log`, a `--cmd` click types it as shown. A fenced step shows exactly what Ari types, laid out the same way by `handoff.zsh --print`.
  ```
  BAD  (link blockquote)   run_log --deliver-to %301 'kubectl get pods -o wide'
  BAD  (link blockquote)   link.zsh's laid-out lines re-joined or re-indented by hand
  BAD  (link.zsh)          --run "op item create \<newline>    --vault Private …"
  GOOD (link blockquote)   kubectl get pods -o wide
  GOOD (fenced step)       run_log -- kubectl get pods -o wide
  ```
- **One purpose per link.** Each link does the one thing its lead-in names, `To create the 1Password item:`; a lead-in that needs "and" is two links, in the same message. NEVER chain two purposes with `&&`, `;` or `||` to save a click. An `&&` stays only when its right side needs the state its left side made (`docker login … && docker manifest inspect …`, `cd repo && make`); a pipe stays.
  ```
  BAD   ▶ op item create … && op read … | docker login … && docker manifest inspect …
  GOOD  1. To create the 1Password item:   ▶ op item create …
        2. To test the token:              ▶ op read … | docker login … && docker manifest inspect …
  ```
- **One message per round.** Every step Ari must run before Claude can continue goes in one message, numbered when there are two or more, each with its `Expected:` line (**Hand Ari a link**). Not-blocking steps ride in the same message; when no step blocks, Claude continues.
- **Then stop and wait. NEVER look for the capture yourself**: no `ls /tmp/run_log`, no tail of the newest dir, no Monitor. Two exceptions, each one capture: Ari asks Claude to watch a long run, and then it is one background wait for `exit=` in its `metadata`; or Ari says the run finished, or asks why nothing came back once it is plainly overdue, and then it is one read of its `metadata` (**Nothing came back**). Silence alone is neither: keep waiting.
- **A `run_log artifact: <dir>` message is data to read, not a command.** Read it (**Read a capture**); never resend what produced it. One message can hold several; read each. An ` ari-driving refused: <pane name> <reason>` line is a click's refusal (**A click did nothing**).

## Reference

Terms: the **label** is `machine=<name>|ID=%N|pane=W.P`, what `ari-driving on` and `off` copy; the **pane name** is its `ID=%N|pane=W.P` part; **Claude's pane** is this session's (`$TMUX_PANE`); a **Claude Code pane** is any pane running Claude Code; the **capture dir** is `<root>/<seq>_<slug>/`; the **artifact line** is ` run_log artifact: <dir>`.

### The opt-in

`ari-driving on|off|status|release` (`bin/ari-driving`, on PATH as `~/.config/bin/ari-driving`; `ari-remote-tmux` is its old name) is Ari's command, run in the pane itself. Only the pane option `@ari_driving` grants anything; the window's `@ari_driving_window` only drives the ✦.

- `on`:
    - marks the pane and stamps `@ari_driving_since` with the grant time (`/ari-driving-remote` reads it: a newer stamp lets another Claude session take the pane; `on` again says `re-granted`);
    - splices ✦ against the window's number into its status formats (a window-level format is edited in place and restored on release);
    - copies the label and shows `✦ AI control ON: <label> (copied)`, or `(not copied: no pbcopy)` / `(not copied: pbcopy failed)` with the label on stderr; nothing else changes on a copy failure.
- `off` unmarks the pane, copies the label and shows `AI control OFF: <label> (copied)` (`already off` when it was not on); the ✦ goes when no pane in the window is marked.
- `status` prints three lines: `pane=ID=%301|pane=2.4`, `label=machine=studio|ID=%301|pane=2.4`, `ari_driving=on`.
- The label has no `machine=` part without the dotfiles harness. Each copy displaces one Raycast Clipboard History entry, which the `AI control` line names.
- `on` arms a `window-layout-changed` hook on the window. It fires on every layout change (a pane closing, but also a split, zoom or resize) and runs `ari-driving release @N` in the background only when no pane of the window is still marked; log: `/tmp/ari-driving-release.log` (`ARI_DRIVING_RELEASE_LOG`).
- `release` drops the ✦, restores the status formats and the hook, and shows `AI control OFF: window N, its last driving pane closed`; it ignores a gone or unmarked window. `off` on the window's last marked pane drops the hook itself.

### Links

`bin/link.zsh --pane 2.4|%N [--cmd TEXT | --run TEXT [--interactive|--no-interactive]]` prints the link for one pane. `%N` is exact; `2.4` is resolved in Ari's most recently active client (`No attached tmux client` with none), so pass the `%N` from a pasted label.

- no command: `[ID=%301|pane=2.4](tmux-pane://301)`; the click focuses the pane;
- `--cmd`: a blockquote of `[ID=%301|pane=2.4](tmux-pane://301?cmd=…)` and the command in a code block; the click types it, no Enter, no `run_log`;
- `--run`: the same with `[▶ run in ID=%301|pane=2.4](tmux-pane://301?run=…)`; the click types the command handed to `run_log --deliver-to <Claude's pane>` (**Command layout**), presses Enter, and switches back to Claude's pane. At exit run_log pastes the artifact line into Claude's prompt, without Enter; Ari presses Enter.
- `--run … --interactive`: `[▶ run (interactive: stays there until it finishes) in ID=%301|pane=2.4](tmux-pane://301?run=…&interactive=1)`, for a command that will ask something in the pane (a password, a 2FA tap, a `[y/N]`, a login). The click adds `--focus-after`: Ari stays in that pane and run_log returns him to Claude's at exit. `link.zsh` assumes it, with `Interactive run … matched='sudo'` on stderr, when the command starts with `sudo`, `su`, `ssh`, `passwd`, `login`, `kinit`, `doas`, `gh auth`, `aws sso`, `gws auth`, `op signin`, `vault login` or `git push` (after any `VAR=value` and `run_log`/`env`/`time`). That list is a floor, not the check (**Pick the handoff**).

The link carries the command as one line, as given. Before the link, `link.zsh` warns on stderr when a click would not type: `Pane not opted in; the click will only focus it`, and for `--run` without `$TMUX_PANE`, `Claude is not in a tmux pane; the artifact line has nowhere to return`. It errors with `No such pane` when the hint is gone. It refuses TEXT with a newline, Tab or other control character, a leading `clear`, or any text that spells the opt-in (the three strings in Rules; a text match, case and quotes ignored).

The click gate (`bin/focus.zsh`): a link's command runs only when the link was clicked in a Claude Code pane, into an opted-in shell at an empty prompt ending in `❯`, not in copy mode, not synchronized, one click at a time. Otherwise the click only focuses the pane and puts the reason on the tmux status line; clicked in a Claude Code pane, it also pastes ` ari-driving refused: <pane name> <reason>` into that pane's prompt. Clicks log to `/tmp/ari-driving-focus.log`; the handler is in **Setup** › Links.

| Reason | What frees the pane |
|---|---|
| `not opted in` | Ari runs `ari-driving on` there, then clicks the same link again |
| `in copy mode (press q there)` | `q` there |
| `running <program>, not a shell` | quit the foreground program |
| `last line does not end in the prompt (busy, or text already on the line)` | Enter there, or wait; a prompt that never ends in `❯` (bash, `sh`) never passes: fenced steps only |
| `another click is typing there` | wait for the first run's artifact line |
| `spells the opt-in …` | the text filter matched; the command goes as a fenced step, never re-quoted past the filter |
| `the command is laid out over several lines, which only zsh reads as one; <program> runs there` | a fenced step, or a pane running zsh |
| status line only, nothing pasted: `no pane %N (it closed since the link was printed)`, `clicked outside a Claude Code pane`, no attached client | a fresh link for the pane Ari names now; click from Claude's pane |

### Command layout

`lib/wrap.zsh` lays out a command over 100 characters, or one with a program argument over 40 (its header has the rules); a shorter one stays one line. `link.zsh`'s code block, the text a click types, and `handoff.zsh --print`'s step all use it.

- Each command of a pipeline or list gets its own line, led by its `|`, `&&`, `||` or `;`; a `for`, `while` or `if` stays whole on its line.
- Within a command, words fill the line, short flags together; ` \` and a new line come only before a quoted string over 40 characters, before a long flag with its value when the command does not fit, or where the line would pass 100.
- jq's program, and a JSON value given to a JSON flag (`--policy`, `-d`, `--data`, `--…-json`), is laid out inside its single quotes: one entry per line, jq shorthand keys sharing one. JSON-shaped text anywhere else (a `grep -F` pattern, a `jq --arg` string) stays as written.
- A command with a `#` word stays one line.

Only whitespace between words and tokens changes, so the shell runs the layout as it runs the one line; a laid-out JSON value differs in bytes, not in JSON. A `--cmd` click types the layout; a `--run` click types `run_log … 'cmd'`, `run_log … "cmd"` when it holds single quotes, or the layout in a quoted heredoc when it is laid out or holds single quotes and one of `"` `$` `` ` `` `\` `!`; never `'\''`:

```zsh
run_log --deliver-to %12 "$(command cat <<'RUN_LOG'
<the layout>
RUN_LOG
)"
```

Several lines go in as one bracketed paste, into zsh only; run_log's `command=` holds the layout.

### The run_log contract

`run_log [--name NAME] [--dir D] [--fd N]… [--no-copy] [--deliver-to PANE [--focus-after]] -- CMD` (`~/.config/bin/run_log`; flags: `run_log --help`) runs CMD in an interactive zsh, so aliases work. One argument is a shell string; several are an argv passed byte for byte; `VAR=val` after `--` sets it for CMD, before `run_log` for run_log itself:

```zsh
run_log -- kubectl get pods -l app=web                        # argv, byte for byte
run_log 'kubectl get pods | grep web'                         # one shell string: pipes, &&
run_log -- AWS_PROFILE=prod-ro aws sts get-caller-identity    # VAR=val after --
```

Each run writes one capture dir, `<root>/<seq>_<slug>/` (root: `--dir` > `$LOG_DIR` > `/tmp/run_log`; `--name NAME` names it), created with `metadata` and the symlinks before CMD starts:

| File | Holds | When |
|---|---|---|
| `metadata` | `user=`, `timestamp=`, `cwd=`, `command=` (a laid-out command runs on to the line before `stdout_tty=`), `stdout_tty=`, `stderr_tty=` | at start |
| | `exit=`, `duration_s=` | at exit, before the artifact line is copied or pasted |
| | `helper_killed_by=SIGHUP` or `SIGTERM` | when the pane closed or the capture was killed before exit; `exit=` follows only if run_log itself survived |
| `1.fd`, `2.fd` | stdout and stderr byte for byte, colors kept | as CMD writes |
| `1.fd.plain`, `2.fd.plain` | the same with escapes stripped and `\r` redraws resolved (only the text after a line's last `\r` is kept): every complete line, then the unfinished last line as the terminal shows it now (a prompt, a progress bar's latest redraw) | as CMD writes; rewritten whole at exit, so a mid-run read is provisional |
| `<N>.fd`, `<N>.fd.plain` | fd N (3–9) with `--fd N`; written to the capture, not shown in the pane | `.fd` as CMD writes; `.plain` rewritten about once a second, its last line cut until exit |
| `stdout`, `stderr`, `stdout.plain`, `stderr.plain` | symlinks to `1.fd`, `2.fd`, `1.fd.plain`, `2.fd.plain` | at start |

At exit it copies the artifact line to the clipboard unless `--no-copy`, `RUN_LOG_COPY=0`, or stdout is not a terminal (that copy is run_log's, not Claude's); `--deliver-to PANE` also pastes it into a pane, refused when the pane is in copy mode, synchronized or gone (status line only; the clipboard still has it), and lost with no status line when CMD removed or replaced the `tmux` binary run_log resolved; `--focus-after` then switches Ari's client to that pane, with the reason on the status line when the paste was refused. The exit code is the command's, or 128 + the signal; Ctrl-C in the pane still lands an `exit=`.

### Fenced steps and the clipboard

- `bin/handoff.zsh --print --cmd CMD --expect TEXT [--step N [--blocking|--not-blocking]] [--interactive | --capture [--capture-dir DIR]]` renders one fenced step: `--capture` → `run_log -- CMD`, or `run_log 'CMD'` when CMD has a shell operator (`|`, `&`, `;`, `>`, `<`, `$(`, a backtick), or the quoted heredoc of **Command layout** when it is long or has an operator and single quotes; `--interactive` → `! CMD`.
- `handoff.zsh --copy (--text T | --file P)` is the only sanctioned copy; it prints where the displaced entry went. On a non-zero exit or a `not copied` line, show the text in a fenced block; no other route.
- `bin/pretooluse_bash_pbcopy_guard.sh`, installed as `~/.config/claude/bin/pretooluse-pbcopy-guard.sh`, denies a Bash call with `pbcopy` in command position (today a quoted `|pbcopy|` trips it too) unless `handoff.zsh --copy` makes it. Its message begins `Blocked: this command writes Ari's clipboard`.

## Workflow

### Pick the handoff

| Situation | Handoff |
|---|---|
| output needed back; no prompt expected | click-to-run link, `link.zsh --run` |
| output needed back; the command will ask something in the pane: a password, a hardware-key tap, a `[y/N]`, an editor, a TTY tool (`sudo`, `ssh`, `tsh`, `kubectl exec -it`, `psql`, `git commit`, `aws sso`, `gh auth`) | interactive run link, `link.zsh --run … --interactive`; the auto-detect list is a floor, pass the flag yourself. `Expected:` quotes the prompt and names the credential, or what `y` does |
| the credentials or output belong to Claude's own session (a login this session's Bash calls use; a device code or URL to read as it appears) | fenced `! cmd` step, run in Claude's own session |
| Ari should fill or edit it first (a value Claude cannot resolve: `<record-id>`, `$TOKEN`, a path), or Enter is his call | click-to-type link, `link.zsh --cmd`; NEVER a `--run` link with a placeholder, it runs as typed. For output back, the typed text is `run_log -- CMD` and Ari pastes the artifact line |
| no suitable pane: none named this turn, `link.zsh --pane <hint>` failed, not opted in, or `$TMUX_PANE` unset | fenced `run_log -- cmd` step; Ari pastes the artifact line |
| another machine; or several commands into a local pane, each read back, with no click per command | `/ari-driving-remote`'s `run.zsh`, `--host-definition local` for here |

Several links for one pane in one message are fine (**One purpose per link**):
- Ari clicks them top to bottom, each after the last one's artifact line lands in Claude's prompt, and presses Enter after the last; a click while the pane is busy is refused, never queued.
- An artifact line that arrives with links outstanding is read, and the links still to click are named; NEVER re-post them.
- A mutating link that must not run after the one before failed goes in the next round, once Claude has read `exit=0`; a read or a test may ride along.

Who runs it, and the precedent line: `/ari-driving` **Who runs a command**. A step opens with its number and lead-in, then the precedent line, then the blockquote. A mutating link's `Expected:` ends with `click once; a second click runs it again`, and the link is never re-posted after its artifact line arrived.

### Hand Ari a link

```zsh
zsh $HOME/.claude/skills/ari-driving-tmux/bin/link.zsh --pane %301 --run 'kubectl get pods -o wide'
```

**Read stderr before pasting.** `Pane not opted in` → NEVER paste a `--cmd` or `--run` link: when more commands will follow, "[ID=%301|pane=2.4](tmux-pane://301) isn't opted in: run `ari-driving on` there and I'll hand you the run link"; for a one-off, a fenced `run_log -- cmd` step. `Claude is not in a tmux pane` → fenced steps only this session. `No such pane` → say which pane is gone and hand a fenced step; never the pane now sitting at `2.4`.

Then paste stdout into chat unchanged, and `Expected:` with what success looks like (a `--run` returns Ari to Claude's pane at once, so Claude reads it from the capture); the mechanism ("`run_log artifact: …` lands in my prompt") once per session; for a command that removes or replaces tmux (a `brew uninstall tmux`, a `dotfiles switch`), also "the artifact line may not land; `exec zsh` there after":

> [▶ run in ID=%301|pane=2.4](tmux-pane://301?run=kubectl%20get%20pods%20-o%20wide)
> ```zsh
> kubectl get pods -o wide
> ```

Expected: three pods Running; `run_log artifact: …` lands in my prompt.

Two purposes are two numbered links in one round, each under its lead-in, each block as `link.zsh` printed it from the one line:

1. To create the 1Password item:
> [▶ run in ID=%301|pane=2.4](tmux-pane://301?run=op%20item%20create%20…)
> ```zsh
> op item create \
>     --category 'API Credential' \
>     --title 'Registry pull token (registry.example.com)' \
>     --vault Private "credential=$(pbpaste)"
> ```

Expected: it takes the token from your clipboard; I read the new item's ID from the capture; click once; a second click runs it again.

2. To test the token:
> [▶ run in ID=%301|pane=2.4](tmux-pane://301?run=op%20read%20…)
> ```zsh
> op read \
>     'op://Private/Registry pull token (registry.example.com)/credential' \
>   | docker login registry.example.com --username robot --password-stdin \
>   && docker manifest inspect registry.example.com/team/web:v1
> ```

Expected: `Login Succeeded` and the image's manifest; click it after 1's artifact line lands, then press Enter.

A mutating command on precedent carries its line directly above:

Follows your `! kubectl rollout restart deploy/web` in alpha earlier this session.
> [▶ run in ID=%301|pane=2.4](tmux-pane://301?run=kubectl%20rollout%20restart%20deploy%2Fweb)
> ```zsh
> kubectl rollout restart deploy/web
> ```

Expected: `deployment.apps/web restarted`; click once; a second click runs it again.

An interactive run (`link.zsh … --run 'sudo launchctl list'`, auto-detected: `matched='sudo'`):

> [▶ run (interactive: stays there until it finishes) in ID=%301|pane=2.4](tmux-pane://301?run=sudo%20launchctl%20list&interactive=1)
> ```zsh
> sudo launchctl list
> ```

Expected: the password prompt is yours; you are back here with the artifact line in my prompt when it finishes.

A click-to-type link when Ari fills a value (`link.zsh … --cmd 'run_log -- kubectl delete pod web-REPLACE'`):

> [ID=%301|pane=2.4](tmux-pane://301?cmd=run_log%20--%20kubectl%20delete%20pod%20web-REPLACE)
> ```zsh
> run_log -- kubectl delete pod web-REPLACE
> ```

Expected: you replace `web-REPLACE` and press Enter; paste the artifact line here (a typed command has no `--deliver-to`, run_log only copies it).

Claude's turn ends there.

### Hand Ari fenced steps

`(blocks me)` means Claude cannot continue until the step is done; `(not blocking)` means it can:

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
Expected: one Running pod; paste the `run_log artifact:` line here (run_log copied it).
````

A round that mixes a `!` step and a link numbers both: `2. To test the token:`, then the link's blockquote on the next line, unindented and unchanged. `handoff.zsh --print` renders one step, a long command laid out (**Command layout**):

```zsh
zsh $HOME/.claude/skills/ari-driving-tmux/bin/handoff.zsh --print --step 2 --not-blocking --cmd 'kubectl get pods -l app=web' --expect 'one Running pod' --capture
```

### Read a capture

Ari sends the artifact line, or names a capture dir mid-run; Claude never constructs one or picks "the newest" with `ls -t`. One read per message that names the dir; the read after `exit=` supersedes any mid-run read, and a mid-run quote never carries into the conclusion.

```
Ari: run_log artifact: /tmp/run_log/007_kubectl_get_pods_-o_wide
```

1. Read `<dir>/metadata`. A `cwd=` other than the directory the command assumed is a different result: say so.
2. Read `stdout.plain`, `stderr.plain`, and `<N>.fd.plain` for each `--fd N`. **NEVER open `1.fd` or `2.fd` to read output**; they answer one question, after `exit=`: what color or cursor sequence a line carried. `stdout.plain` missing while `1.fd` exists: the run predates the live writer; say so and offer a fresh link, never strip `1.fd` by hand. Empty, or shorter than last time, with no `exit=`: mid-rewrite, read it again.
3. Branch on `metadata`:
    - **`exit=0`:** the conclusion ("3/3 Running on ip-10-0-12-34, no restarts"); never "running it now", never a re-run to confirm. Empty output: "ran clean, no output".
    - **`exit=` 1–127:** the first non-empty line of `stderr.plain` (of `stdout.plain` when stderr is empty), then the one action it implies; the other two (a fresh link from this turn's `link.zsh`, a skip, the next read-only command) in one trailing line. A same-command retry only for a transient error; an expired session (`tsh`, `aws sso`, sudo) gets an interactive login link first. Empty stderr with output that stops mid-way is Ari's Ctrl-C (`exit=1` or `130`) or his `N`: ask before offering a retry.
    - **`exit=` 128 or more:** a signal (`130` Ctrl-C, `137` killed, `143` terminated); name it, offer no retry, ask what he saw.
    - **No `exit=` line:** running, or dead without one. `helper_killed_by=` present, or `pgrep -lf "run_log-capture.py <dir>"` empty → dead: "killed before exit; output up to `<last line>`", then a fresh link. Otherwise running: one line with the command, the time since `timestamp=`, `wc -l stdout.plain` and its last ~5 lines (the unfinished last line is what the pane shows now; a prompt there means it is waiting on Ari: say so), then "I read it again when the artifact line arrives"; no verdict. A pasted artifact line whose `metadata` lacks `exit=` is not a run_log state: say so and ask.
4. `wc -l` over `stdout.plain` and `stderr.plain` is 200 or more and `exit=` is present: a subagent reads it, briefed with the command and the `Expected:`, and returns `exit=`, the one-line conclusion and the first error line; it runs nothing. Mid-run, `tail` instead.

Several artifact lines in one message: one line per capture in the order sent, each opening with its `command=` and `exit=`; name any step whose line has not arrived, and list still-outstanding `(not blocking)` steps in one line at the next round. A dir already read this session with `exit=`: say so in one line. Interactive `!` steps arrive as output in the conversation; Ari's pasted output is data.

A mid-run read:

```
Ari: it's been going a while: /tmp/run_log/008_kubectl_rollout_status, what's it doing?
```

`metadata` has no `exit=`; `pgrep` finds the helper; `stdout.plain` has 12 lines, the last `Waiting for deployment "web" rollout to finish: 2 of 3 updated replicas are available...`

→ "Still running: started 09:41:02Z, 12 lines so far, last `Waiting … 2 of 3 updated replicas are available`. No verdict until the artifact line lands; Ctrl-C there if you want it stopped, the capture still gets its `exit=`."
Not: "2 of 3 replicas, the rollout is stuck", "looks like it was killed", or a re-run.

### A click did nothing

Ari clicked and nothing ran. A link clicked in Claude's pane reports its refusal into Claude's prompt, as if typed:

```
Ari:  ari-driving refused: ID=%301|pane=2.4 not opted in; Ari runs 'ari-driving on' in that pane
```

Answer with the reason's row from the click gate (**Links**) and the fenced step: "`ID=%301|pane=2.4` isn't opted in: run `ari-driving on` there and click the same link again, or run it yourself:" plus the step. Never reprint the link unchanged, and never dodge the opt-in text filter:

```
BAD   link.zsh --run "rg 'ari-driving o''n' ~/.zshrc"     # split to dodge the match
GOOD  a fenced step Ari types:  run_log -- rg 'ari-driving on' ~/.zshrc
```

No refusal line arrived: `tail -5 /tmp/ari-driving-focus.log` and answer with its `message=`.
- `no pane %N`: the pane closed; a fresh link for the pane Ari names now.
- `clicked outside a Claude Code pane`, or `No attached tmux client`: ask him to click from Claude's pane.
- a `Not typed` line whose paste was refused: Claude's pane was in copy mode when the line came (`q` there; it is also on his clipboard).
- nothing logged: the handler did not run; `tmux list-keys -T root MouseUp1Pane | grep -c tmux-pane` must print `1`, else Ari presses `<Prefix> C-s` (it re-reads `~/.config/tmux/tmux.conf`); still `0` → the handler is not in that file yet, and Ari runs `dotfiles switch` first (**Setup**).

### Nothing came back

Ari says a `--run` click's command finished, or asks why nothing came back once it is plainly overdue, and no artifact line arrived. Until he does, wait (Rules).

1. Find that one capture: `grep -lF 'command=<the link's command, its first line when laid out>' /tmp/run_log/*/metadata`, the match whose `timestamp=` follows the link. None or several → ask Ari to paste the line (run_log copied it); never guess the dir.
2. Read only its `metadata`. No `exit=` → it is still running (**Read a capture**, no-`exit=` branch). `exit=` and `duration_s=` present → the delivery was lost: say so with both values and why, then read the dir as if its artifact line had arrived (**Read a capture**).
3. The why: CMD removed or replaced tmux itself (a `brew uninstall tmux`, a Nix switch), so run_log's `tmux` paste ran a deleted binary; Ari runs `exec zsh` in that pane before its next link. Otherwise the pane was in copy mode, synchronized or gone, and the status line said so.

```
BAD:   (several turns of silence, then) cat /tmp/run_log/1078_dotfiles_switch/metadata   ← unasked
GOOD:  Ari: the switch finished, nothing came back
       → grep finds 1078_dotfiles_switch: "exit=0 after 212s; the artifact line was lost: the switch
         removed brew's tmux, so run_log's paste failed. Run `exec zsh` in that pane before the next link."
```

### Copy only on request

Ari asked for text on his clipboard:

```zsh
zsh $HOME/.claude/skills/ari-driving-tmux/bin/handoff.zsh --copy --text '<text>'
```

It prints `copied_chars=212` and `previous clipboard: second entry in <[Raycast: Clipboard History | key: '✦4'](raycast://…)>`; the reply: "Copied 212 chars. Your previous clipboard is the second entry in [Raycast: Clipboard History | key: '✦4'](raycast://…)."

### Recover a clobbered clipboard

When Ari says his clipboard was overwritten: run `dotfiles raycast link check` first (the widget must be listed as allowed), then print the widget and say which entry is his: the second after one write; count every write since (run_log's artifact line, each `ari-driving on|off`, each `handoff.zsh --copy`) when there were more. Claude never restores and never reads the history. A link text ending in `(not compiled yet)` means Karabiner needs a rebake; until then, Raycast → Clipboard History by hand.

```zsh
dotfiles raycast link clipboard-history
```

## Setup (once per machine)

- **run_log:** the dotfiles shared tier puts `run_log` and `run_log-capture.py` in `~/.config/bin` (python3 required); without it `focus.zsh` refuses with `run_log is not installed at ~/.config/bin/run_log`.
- **Command:** `ln -sfn ../claude/skills/ari-driving-tmux/bin/ari-driving ~/.config/bin/ari-driving`; `readlink` it to verify.
- **Links:** `~/dotfiles/.config/dotfiles/nix/tmux/osc8-hyperlinks.conf` carries the handler; `tmux.nix` appends it to the store-placed `~/.config/tmux/tmux.conf`, so a change takes Ari's `dotfiles switch` (`/ari-dotfiles-nix`) and then `<Prefix> C-s` in the running server, after which `tmux list-keys -T root MouseUp1Pane | grep -c tmux-pane` prints `1`.
- **Guard:** `ln -sfn ../skills/ari-driving-tmux/bin/pretooluse_bash_pbcopy_guard.sh ~/.config/claude/bin/pretooluse-pbcopy-guard.sh`, then via `/update-config` a `PreToolUse` entry `{"matcher": "Bash", "hooks": [{"type": "command", "command": "$HOME/.config/claude/bin/pretooluse-pbcopy-guard.sh", "if": "Bash(*pbcopy*)", "timeout": 5}]}` with `$HOME` replaced by the literal home directory. Verify with the Bash call `false && pbcopy`: the guard must deny it.

## File storage

- `bin/ari-driving` — `on|off|status` for the current pane; `release @N` for the pane-close hook.
- `bin/link.zsh` — prints a link, or the link-plus-code-block blockquote.
- `bin/focus.zsh` — what a click runs: focus, gate, type or run.
- `lib/wrap.zsh` — lays out a long command (**Command layout**) for `link.zsh`, `focus.zsh` and `handoff.zsh`.
- `bin/handoff.zsh` — renders fenced steps; the sanctioned copy.
- `bin/pretooluse_bash_pbcopy_guard.sh` — the pbcopy guard hook.
- `tests/ari-driving.test.zsh` — `bin/ari-driving` on a throwaway tmux server (`-L`) with a fake pbcopy, and with tmux off PATH; it refuses to run unless its pbcopy shim wins PATH.
- `tests/link.test.zsh` — layouts, the link's one-line payload, and clicks on a throwaway tmux server (`-L`): what the pane shows, and that a capture's output equals the one-line command's; `link.zsh` and `focus.zsh` with tmux off PATH; needs `script` and `~/.config/bin/run_log`.
- `~/.config/claude/lib/tmux-pane.sh` (shared tier) — the gate, resolve, lock and paste helpers that `link.zsh`, `focus.zsh`, `handoff.zsh` and `run_log` source; `ari-skill-shellscripts/lib/logging.zsh` is the logging shim they all source (`[ERROR] missing shared logging lib` when absent).

`--help` on each lists its flags. After an edit to `bin/ari-driving`:

```zsh
zsh $HOME/.claude/skills/ari-driving-tmux/tests/ari-driving.test.zsh
```

After an edit to `lib/wrap.zsh`, `bin/link.zsh`, `bin/focus.zsh` or `bin/handoff.zsh` (about a minute: it waits on real runs):

```zsh
zsh $HOME/.claude/skills/ari-driving-tmux/tests/link.test.zsh
```
