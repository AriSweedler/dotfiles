---
name: ari-operator-mode
description: "Operator mode: Ari is back as a fresh operator who has read no history and holds the permissions Claude lacks. On only when he invokes this skill, off only on \"stop operator mode\". While on, every reply renders only what bin/frontier.zsh read this turn: first principles, state, up to five unblocked actions with exact commands, one confirm-or-deny before work. When it is off and he asks where we are, what's next, or says he has read none of this, offer it in one line: \"Want operator mode? /ari-operator-mode reads the tracker, the checkouts and your pane and briefs you from scratch.\""
disable-model-invocation: true
---

# Operator mode

Ari comes back to a session as a fresh operator: he has read none of the history, does not remember what sits on his prompt, and can run what the permission layer refused Claude. Every reply in this mode is written for that reader, from a capture made this turn.

## Rules

- **A mode, not a moment.** `bin/mode.zsh on` when he invokes the skill, `bin/mode.zsh off` when he says `stop operator mode` or `normal mode`; every reply asks `bin/mode.zsh status` and NEVER the transcript or a summary, so a compaction cannot lose the mode. Only his invocation switches it on; a gap, a compaction or a hook does not. Off, when he asks an orienting question (Reference › The offer), one line offers it and nothing else is answered from the transcript.
- **The operator knows nothing.** Every term is defined at first use and every thing is named by what it is: a bead by id and title, a file by path, a pane by its full label with his nickname (`machine=personal|ID=%18|pane=3.1|nickname=homelab`). NEVER "earlier", "the one-liner", "step 2" or a session's name for something.
- **The script reads, the model renders.** `bin/frontier.zsh` is the only source of facts; every bullet and row traces to one section of its JSON, and a sentence that traces to none is deleted. Asked for something the JSON lacks: "Not in this capture; a fresh capture would read `<section>`."
- **Three facts may come from outside the JSON.** A command the permission layer refused Claude, quoted verbatim with the refusal, as his row; a recommendation on a human bead, marked "(my recommendation)" and drawn only from `human.text`; and this turn's `TYPED:` or `REFUSED:` result of `run.zsh --no-enter` for his row, as that row's key. Nothing else from the session enters a briefing.
- **NEVER run the health command.** Not in the capture, not by hand, not when `health.ran` is false: it is a table row (Reference › Row triage), and its output enters only through the next capture.
- **Cut off is the whole message.** `cut_off` not null: the reply is what `bin/brief.zsh --cut-off` prints and nothing else, replacing the header too: the P0 paragraph, or for `own_command`, `row_pending` and `row_running` one waiting line that is not his P0 (Reference › Cut-off reasons). NEVER re-run with `--local`, pick another pane, run `bd` or `git` here as a substitute, render `local_git` and `health` even though they filled, or re-capture, sleep, poll or run `run.zsh` again in the same turn; his next message, whatever it says, starts with a fresh Capture and authorizes no row. The rule is `/ari-bead-driven-development`'s Cut off rule; this skill only renders it.
- **Terse, then one question.** At most six state bullets and exactly one question mark per reply; the question is "Row 1 next?" after one sentence saying a no is a correction, and it names the row when the row destroys something. Depth on request is the named section's raw text, verbatim.
- **One yes, one row.** A yes authorizes row 1 only; when it lands, Capture, Brief, ask again. Enter in his pane is the yes for his own row; a Claude row needs the chat yes; a row that **destroys:** is shown and typed only after his chat yes. "yes", "y", "go", "ok", "do it" and "row N" are a yes; words matching a row are a yes to that row; pasted output is that row's result; a yes that re-orders or drops rows is a yes to the changed table, re-rendered without a capture. A no is one of three: a tracker correction becomes a row with its `bd` command, a rendering correction re-renders without a capture, a fact outside the tracker becomes one bullet prefixed "Ari said:"; a bare no gets "What is wrong?". An instruction given with the invocation is row 1 marked "(your instruction)" and runs only after his yes.
- **Up to five rows, unblocked only.** Sources, priority and order are Reference › Row triage; blocked, deferred and stale work is the one trailing line, never a row; a sixth candidate and beyond are named there as "Also ready: …".
- **His remote rows are typed, not only shown.** Type the command of his first remote row (the lowest-numbered row whose Who is `Ari` and whose pane is the capture's) into his pane with `run.zsh --no-enter` in the turn that shows the table, per `/ari-driving-remote` › Type a command for Ari to run and its `--no-enter` rule; the fenced `zsh` block under the pane's full label with nickname holds the bare command passed to `--cmd` (`run.zsh` wraps it in `run_log` itself), and the row's key says what the run printed (`templates/briefing.md` › The table). One typed line across all his panes at a time. A local command is the click-to-type link `/ari-driving-tmux` mints, with a fenced block under the pane label as the fallback and NEVER a bare command. Each carries one sentence of what it does and one of what it prints.
- **While a row of his sits typed and un-entered, NEVER capture or type.** A reply that would capture asks the one question "Row N is on your prompt: entered, or cleared?" and reads nothing; a capture that finds his row anyway reports it as `row_pending` or `row_running`, never as his P0. Capture only after he says he entered it, pasted its output, or cleared it.
- **Chat only.** The briefing is this reply and nothing else: never a Slack post, a doc, an artifact, a bead comment or a pane. Claude builds what runs in the product and never delivers itself through it; his words: "You and I are tools to create the product."
- **No recap.** NEVER summarise earlier this session; `host_git.log` is the only history, and only on request.

Not this, then this:

```
Not: "beads-abc is done, I finished it before you stepped away."
This: "beads-abc 'Fix the widget' is ready (P1)."            ← the capture lists it under ready; a belief the tracker is stale is a row, never an edit
Not: "Step 2 is the compose variable, as in the one-liner."
This: "The compose variable in apps/media/compose.yaml."     ← paths and names, no session shorthand
Not: "Since this morning we merged the PR and fixed the doctor."
This: "Last commits: abc1234 first subject; bcd2345 second subject."   ← host_git.log, nothing more
Not: "Doctor is green."
This: "bin/doctor.sh has not been run this capture."         ← health.ran is false; the run is a row
```

## Reference

### The capture

`bin/frontier.zsh` reads these in this order, through `/ari-driving-remote`'s `run.zsh` on the host (every `bd` call is `bd -C <beads>`, never `cd`), and writes one JSON. The first six are `/ari-bead-driven-development`'s state-of-play commands plus `deferred`.

| Section | Host command | JSON | Renders in |
|---|---|---|---|
| `ready` | `bd ready --exclude-label human --json` | `[{id, title, priority, type, parent, assignee, updated_at}]` | state bullet, rows |
| `in_progress` | `bd list -s in_progress --json` | the same list | state bullet; a Claude row when held by claude |
| `human` | `bd human list` | `{text, ids}` | state bullet, his rows |
| `blocked` | `bd blocked` | `{text, ids, blockers: {id: count}}` | trailing line; `blockers` ranks rows |
| `stale` | `bd stale -d 14 -s in_progress` | `{text, ids}` | the in-progress bullet, trailing line |
| `deferred` | `bd list -s deferred --json` | `{count}` | trailing line |
| `host_git` | `git -C <repo> status --short && git -C <repo> log -3 --oneline` | `{dirty: [], log: [{hash, subject}]}`, or `{skipped}` without `--repo` | state bullet, his row when dirty |
| `local_git` | the same on this Mac | the same | state bullet when it differs from the host's |
| `health` | none; recorded, never run | `{command, ran: false}` | state bullet, a row |

A section that could not be read holds `{"error": "<why>"}`; one a cut-off kept unread holds `{"unread": true}`. The top level also carries `captured_at`, `session`, `host_definition`, `pane`, `nickname` (the pane's window name), `beads_dir`, `repo`, `local_repo`, `typed` (every command typed, in order) and `cut_off`. The filled example is `templates/frontier.example.json`.

### Cut-off reasons

| Reason | From | The paragraph's move |
|---|---|---|
| `not_opted_in` | `run.zsh` exit 77 | run `ari-driving on` there |
| `other_session` | exit 76 | `ari-driving off` then `on` there, or another pane |
| `busy` | exit 75, the pane running a command that is not this session's (an editor, a TUI, copy mode), or still busy with the same own command as the last capture | wait, or name another pane |
| `own_command` | exit 75, the pane ran this session's own command for the whole capture budget | a wait, not his: one waiting line with its question; his next message captures again |
| `row_pending` | exit 75, his `--pending` row sits un-entered on the prompt | his: press Enter there, or clear it, then tell me |
| `row_running` | exit 75, his `--pending` row is running | his: tell me what it printed when it ends |
| `holds_text` | exit 75, text on the line that is not his pending row; the line is quoted | clear it or run it, then tell me |
| `no_pane` | exit 70; the host's panes are listed | name one by its `ID=%N` |
| `ambiguous_pane` | the target matched two panes; both listed | name one by its `ID=%N` |
| `read_timed_out` | exit 124; a read is still running there | wait for the prompt, then tell me; never resend |
| `host_unreachable` | exit 255, or `--list` failed; the error is quoted | open `ssh` to the host once in a pane |
| `refused_text` | exit 1; the reader's own text was refused | a bug in the reader, not his to clear |

The host reads stop at the first cut-off and the rest are unread; `local_git` and `health` still fill and are still not said. A 75 is classified by the pane tail, never by the refusal's words (the gate says the same thing for a running command and for text on the line): the command on the last prompt line is this capture's own read, an earlier read's marker recipe, or a `bd` or `git` command a fork or lane typed, so the reader retries every 5 s (`FRONTIER_RETRY_S`) within the capture budget (`--timeout` times the seven host reads) and records `own_command` only when the budget is spent; it is the `--pending` text, so it is his row; anything else is `busy` or `holds_text`. A second capture finding the same own command on the pane records `busy`: it is not clearing on its own. The retry is this skill's override of `/ari-driving-remote` › Exit codes › 75, "never retry on your own", for its own commands only. `read_timed_out` stays his even though the read was this session's: a read already typed is never resent.

### Row triage

| Source | Row |
|---|---|
| `ready` | a row, Claude's unless the permission layer refused it |
| `human` | his row: the statement and his command to record the answer, with "(my recommendation)" from `human.text` |
| `in_progress` held by claude | a Claude row ahead of `ready`; held by anyone else, a state bullet |
| `host_git.dirty` or `local_git.dirty` | his row, opening with **destroys:** when it discards |
| `health` with `ran` false | a Claude row to run it when no row is P0, his row once the permission layer refuses |
| a section with `error` | a Claude row to retry that read, or his to run the command by hand |
| `blocked`, `deferred`, `stale` | never a row; the trailing line |
| `cut_off` not null | no rows at all |

Priority is `P` plus the bead's integer; a row with no bead inherits the priority of the highest bead it stands in front of, else P2. Sort: priority ascending, then `blockers` count descending, then Ari before Claude, then oldest `updated_at` first. `Who` is exactly `Ari` or `Claude`. The sixth row and beyond go to the trailing line as "Also ready: …".

### Terms

| Term | Definition, as the briefing gives it |
|---|---|
| bead | one tracked issue in the `bd` tracker |
| epic | a bead that holds children |
| ready | open with nothing blocking it |
| in progress | claimed and being worked |
| human gate | a bead only Ari can answer |
| blocked | waiting on another bead |
| stale | in progress and untouched for fourteen days |
| pane label | `machine=personal|ID=%18|pane=3.1|nickname=homelab`: the machine, tmux's fixed pane id, the window.pane on the screen, the window's name |
| doctor | the project's own health command, `health.command` |

### The header

`bin/brief.zsh --header` prints line 1 of every reply from the newest capture: `Ready N, in progress N, human N, blocked N, stale N; <checkout> <hash> clean|dirty N; read HH:MMZ[; waited Ns for <pane>]; <phase>`, where a failed section reads `failed`, the checkout is the host's or, when that was skipped, `this Mac`, `waited` appears when the reader waited on its own command, and `--phase 'after row N'` names the phase after a row lands. A cut-off capture prints `Cut off: <pane> (<reason>); tracker unread; read HH:MMZ`, which the paragraph replaces; for the three wait reasons the header is the waiting line itself.

### Exit codes

| Script | Codes |
|---|---|
| `bin/frontier.zsh` | 0 the JSON was written, cut off or not; 1 a missing prerequisite, a bad flag, an unreadable `--previous`, `FRONTIER_RETRY_S` not a positive integer, or `CLAUDE_CODE_SESSION_ID` unset without `--local` |
| `bin/brief.zsh` | 0 printed; 3 the cut-off output was printed (the paragraph or a waiting line); 1 a bad call or a file that is not a capture |
| `bin/mode.zsh` | 0 on, or done; 3 off (`status`); 1 a bad call |

### The offer

Off, on an orienting question, this line and nothing else: "Want operator mode? `/ari-operator-mode` reads the tracker, the checkouts and your pane and briefs you from scratch." Orienting: "where are we", "what's next", "catch me up", "remind me what's going on", "I haven't read any of this", a return after a gap that opens with a question about state. Not orienting: a specific question, an instruction, anything while the mode is on.

## Workflow

### Enter the mode

Run `zsh $HOME/.claude/skills/ari-operator-mode/bin/mode.zsh on`. The acknowledgement names the pane and what will appear in it: "Operator mode on. Reading the tracker through `<label with nickname>`: seven read-only commands, up to 45 s each." An instruction given with the invocation is NOT executed this turn; it is row 1, marked "(your instruction)". Then **Capture** and **Brief** in the same turn.

### Where the flags come from

`<host-definition>` and `<pane>` come from his words this turn, else `run.zsh --hosts` then `--list` (`/ari-driving-remote` › Read the known hosts), never a `%N` from history; `<beads>` and `<repo>` from his words, the project's `CLAUDE.md` or memory; `<health>` from the project's doctor command. An unknown pane makes the entry reply the acknowledgement plus the one question "Which pane holds the tracker?" and no capture.

### Capture

One call, with the Bash tool's timeout raised to 600000 ms (the capture's own budget is `--timeout`, 45 s, times its seven host reads, retries included):

```zsh
zsh $HOME/.claude/skills/ari-operator-mode/bin/frontier.zsh --host-definition <host-definition> --target <pane> --beads <beads> --repo <repo> --local-repo "$PWD" --health '<health>'
```

A tracker and checkout on this Mac take `--local` in place of the host flags. Add `--pending '<the TYPED: line>'` when a row of his was typed this session and he has not said it was entered or cleared, so the reader names it as his row. It prints `dir=`, `json=` and `cut_off=`; the folder is the investigation folder below. A non-zero exit makes the whole reply its `[ERROR]` line as P0 with the fix it names and the one question "Fixed?".

### Brief

Type first, then render. Step 1, when the table has a remote row of his that does not destroy:

```zsh
zsh $HOME/.claude/skills/ari-driving-remote/bin/run.zsh --host-definition <host-definition> --target <pane> --no-enter --cmd '<row 1 command>'
```

Step 2: render `templates/briefing.md` from the JSON, in its order, adding nothing; `templates/briefing.example.md` is what it looks like filled. The typed row's key MUST match the run: `TYPED:` printed, "typed into `<label>`, not entered"; exit 75, "not typed: <the why after `REFUSED: <label>`>", retried once on his yes; exit 70, 76, 77 or 255, the fenced block stands as his fallback with that why and the move from Reference › Cut-off reasons; exit 1 (the reader's own text refused), rewrite the command on one line and type again, never wait. When `cut_off` is not null the whole reply is:

```zsh
zsh $HOME/.claude/skills/ari-operator-mode/bin/brief.zsh --dir <dir> --cut-off
```

### Proceed

On yes: do row 1. When row 1 is his, its command is already on his prompt (typed in Brief), so say "Row 1 is on your prompt; press Enter, then paste what it printed or tell me"; if Brief's run was refused with 75, type it once now and report that run the same way; NEVER retype a row whose run printed `TYPED:`; a second refusal re-renders the row with "not typed: <why>" and the one question "Clear it?". An outcome reply runs in this order and no other: he said entered, pasted its output, or cleared → **Capture** → type his next row (the new table's first remote row) `--no-enter` → header, then render. **Capture** before every reply that reports an outcome: a command result read back, a bead claimed, closed or answered, a commit, a file written; a question-only reply does not capture. Every reply in the mode opens with the header, run against the newest capture and pasted as printed, never typed by hand:

```zsh
zsh $HOME/.claude/skills/ari-operator-mode/bin/brief.zsh --dir <dir> --header --phase 'after row 1'
```

Then one sentence per fact of what happened, then the next table or the one question. On no: the three kinds in Rules, then **Capture** and **Brief** when the tracker was corrected.

### Leave the mode

On `stop operator mode` or `normal mode`: `zsh $HOME/.claude/skills/ari-operator-mode/bin/mode.zsh off`, one line "Operator mode off.", then the default style.

## Investigation folder

```
/tmp/operator-mode/
├── ON-<session id>          # the mode marker: present while the mode is on, holds the time it was switched on
└── <UTC stamp>/
    └── frontier.json        # one capture; frontier.zsh makes the folder and prints its path as dir=
```

## File storage

- `bin/frontier.zsh` — the one reader of state, and the only script here that touches a pane, through `/ari-driving-remote`'s `run.zsh`.
- `bin/brief.zsh` — the header line and the cut-off output (the paragraph or a waiting line), from a capture.
- `bin/mode.zsh` — the on/off marker.
- `templates/briefing.md` — the render spec; `templates/briefing.example.md` — the spec filled; `templates/frontier.example.json` — the capture it renders.
- `tests/frontier.test.zsh` — the suite, against `tests/fake-run.zsh`, a fake `run.zsh`; run `zsh $HOME/.claude/skills/ari-operator-mode/tests/frontier.test.zsh`.
