---
name: ari-operator-mode
description: "Operator mode: Ari is back as a fresh operator who has read no history and holds the permissions Claude lacks. On only when he invokes this skill, off only on \"stop operator mode\"; every reply in it is a briefing from a capture made that turn: state, up to five unblocked rows with exact commands, one confirm-or-deny. Off, offer it in one line when he asks where we are or what is next."
disable-model-invocation: true
---

# Operator mode

Every reply in this mode is written for a reader who has read nothing, does not remember what sits on his prompt, and can run what the permission layer refused Claude: from a capture made this turn, state, up to five unblocked rows with exact commands, one question.

## Rules

- **A mode, not a moment.** Every reply checks `bin/mode.zsh status`, never the transcript; only his invocation switches it on, only `stop operator mode` or `normal mode` off. Off, an orienting question gets the one offer line (Reference › The offer) and nothing from the transcript.
- **The operator knows nothing.** Define every term at first use; name every thing by what it is: a bead by id and title, a file by path, a pane by its full label with his nickname. Never "earlier", "the one-liner", "step 2" or a session's name for something.
- **The script reads, the model renders.** `bin/frontier.zsh` is the only source of facts; every bullet and row traces to one section of its JSON; delete a sentence that traces to none. Asked for something the JSON lacks: "Not in this capture; a fresh capture would read `<section>`" (or "no section reads it; reading it is a Claude row: `<command>`"), ending "Or say `stop operator mode` to ask freely."
- **Four facts may come from outside the JSON.** A command the permission layer refused Claude, quoted verbatim with the refusal, as his row; a recommendation on a human bead, marked "(my recommendation)" and drawn only from `human.text`; this turn's `TYPED:` or `REFUSED:` result of `run.zsh --no-enter` for row 1, as its key; and a background agent this session launched for this pane whose completion notice has not arrived, which makes the pane another agent's (Reference › Shared pane). Nothing else from the session enters a briefing.
- **NEVER run the health command unasked.** Not in the capture, not by hand: it is a Claude row (Reference › Row triage), run once through `run.zsh` on his yes, and its output enters only through the next capture.
- **Cut off is the whole message.** `cut_off` not null: the reply is what `bin/brief.zsh --cut-off` prints, nothing else, no header; no second read, no `--local` or other pane as a substitute, no `local_git` or `health` even though they filled; his next message starts with a fresh Capture and authorizes no row. This renders `/ari-bead-driven-development`'s Cut off rule (Reference › Overrides).
- **Terse, then one question.** At most six state bullets and exactly one question mark per reply, the last thing in it (Reference › Yes and no names the forms); a bead title holding a question mark is paraphrased. Depth on request is the named section's raw text, verbatim.
- **One yes, one row.** A yes authorizes row 1 only; when it lands, Capture, Brief, ask again. What counts as a yes or a no is Reference › Yes and no. An instruction given with the invocation is row 1 marked "(your instruction)" and is never run in the entry turn.
- **Up to five rows, unblocked only.** Sources, priority, order and pane are Reference › Row triage; blocked, deferred and stale work is the one trailing line, never a row; a sixth candidate and beyond go there as "Also ready: …".
- **Only row 1 is typed, and only when it is his.** Type row 1 into his pane with `run.zsh --no-enter` in the turn that shows the table when its Who is `Ari`, its pane is the capture's, it neither destroys nor is irreversible, and no other agent is using the pane (Reference › Shared pane); record the typed text with `bin/pending.zsh set`. Never type while another agent uses the pane, and never put a second line on his panes while one sits un-entered. Every other row of his is shown with its command and a key that says so (`templates/briefing.md` › The table). A local command is the click-to-type link `/ari-driving-tmux` mints, a fenced block under the pane label as the fallback, never a bare command.
- **Rows name their writes.** A Claude row's Action says what it writes (claim, branch, PR, merge, deploy). An Action that discards work opens with **destroys:**, one that ships work (merge, deploy, push to main, delete data) with **irreversible:**; such a row is typed or run only after a yes that names it, and a discard row follows a show row from an earlier capture.
- **Chat only.** The briefing is this reply and nothing else: never a Slack post, a doc, an artifact, a bead comment or a pane; his words: "You and I are tools to create the product."
- **No recap.** Never summarise earlier this session; `host_git.log` is the only history, and only on request.

## Reference

### The capture

`bin/frontier.zsh` reads these in this order, through `/ari-driving-remote`'s `run.zsh` on the host (every `bd` call is `bd -C <beads>`, never `cd`), and writes one JSON. The first six are `/ari-bead-driven-development`'s state-of-play commands, `deferred` among them; the script is the authoritative list.

| Section | Host command | JSON | Renders in |
|---|---|---|---|
| `ready` | `bd ready --exclude-label human --json` | `[{id, title, priority, type, parent, assignee, updated_at}]` | state bullet, rows |
| `in_progress` | `bd list -s in_progress --json` | the same list | state bullet; a Claude row when held by claude |
| `human` | `bd human list` | `{text, ids, deferred_ids}` | state bullet, his rows; `deferred_ids` nowhere |
| `blocked` | `bd blocked` | `{text, ids, deferred_ids, blockers: {id: count}}` | trailing line; `blockers` ranks rows |
| `stale` | `bd stale -d 14 -s in_progress` | `{text, ids, deferred_ids}` | the in-progress bullet, trailing line |
| `deferred` | `bd list -s deferred --json` | `{count}` | trailing line |
| `host_git` | `git -C <repo> status --short && git -C <repo> log -3 --oneline` | `{dirty: [], log: [{hash, subject}]}`, or `{skipped}` without `--repo` | state bullet, his row when dirty |
| `local_git` | the same on this Mac | the same | the checkout bullet when it differs from the host's |
| `health` | none; recorded, never run | `{command, ran: false}` | state bullet, a row; nothing when `command` is null |

A section that could not be read holds `{"error": "<why>"}` (`precondition: true` when one cause, such as no `bd` on the host, failed them all); one a cut-off kept unread holds `{"unread": true}`; a text section whose id count disagrees with bd's own summary count is an error, not a quiet miss. The top level also carries `captured_at`, `session`, `host_definition`, `pane`, `nickname` (the pane's window name), `beads_dir`, `repo`, `local_repo`, `pending`, `typed` (every command typed, in order), `waited_s` and `cut_off` (`{pane, reason, prompt_holds, busy_cmd, candidates, unread}`). The filled example is `templates/frontier.example.json`.

### Cut-off reasons

| Reason | From | The paragraph's move |
|---|---|---|
| `not_opted_in` | `run.zsh` exit 77 | run `ari-driving on` there |
| `other_session` | exit 76 | `ari-driving off` then `on` there, or another pane |
| `busy` | exit 75, the pane running a command Ari typed (an editor, a TUI, copy mode, a bare command) | wait, or name another pane |
| `holds_text` | exit 75, un-entered text on the prompt that is not his pending row, whoever typed it; the line is quoted | clear it or run it, then tell me |
| `own_command` | exit 75, the pane ran an agent's command for the whole capture budget | a wait, not his: one waiting line with its question; his next message captures again |
| `own_command_persists` | exit 75, the previous capture by this session on this pane already waited on that same command | the same wait; "Wait, or name another pane?" |
| `row_pending` | exit 75, his pending row sits un-entered on the prompt | his: press Enter there, or clear it, then tell me |
| `row_running` | exit 75, his pending row is running | his: tell me what it printed when it ends |
| `no_pane` | exit 70; the host's panes are listed | name one by its `ID=%N` |
| `ambiguous_pane` | the target matched two panes; both listed | name one by its `ID=%N` |
| `read_timed_out` | exit 124 with no complete stream; a read is still running there | tell me when its prompt is back; never resent |
| `host_unreachable` | exit 255, or `--list` failed; the error is quoted | open `ssh` to the host once in a pane |
| `refused_text` | exit 1; the reader's own text was refused | a bug in the reader, not his to clear; Claude rewrites the read on one line, once |

The host reads stop at the first cut-off and the rest are unread; `local_git` and `health` still fill and are still not said. How a 75 is classified, in order:

1. the gate's words name copy mode or synchronized panes: `busy`.
2. the pane tail decides, the last prompt line's command joined across its wrapped lines: it is the pending row (`--pending`, defaulted from `bin/pending.zsh`): `row_pending` un-entered, `row_running` running.
3. un-entered text that is not his row: `holds_text`, whoever typed it; no wait clears it.
4. a running agent's command (this capture's read, an earlier read's marker recipe, any `run_log`-wrapped line, a `BEADS_ACTOR=claude bd` write; Ari types bare): retry every 5 s (`FRONTIER_RETRY_S`) within the budget (`--timeout`, 45 s, times the seven host reads); `own_command` when the budget is spent; `own_command_persists` when the previous capture already waited on it.
5. anything else running: `busy`.

### Shared pane

Another agent of this session (its own earlier read, a fork or a lane he launched, a subagent of Claude's) uses the pane when the capture waited on it (`waited_s` > 0) or a background agent launched for this pane has not reported back (the fourth outside fact). Then nothing is typed there: row 1 of his keeps the key "not typed: another agent is using this pane; typed when it is free", and the next Brief after a capture that did not wait types it. The reader's retry on an agent's command is this skill's override of `/ari-driving-remote` › Exit codes › 75 (Reference › Overrides).

### Row triage

| Source | Row |
|---|---|
| `ready` | a row, Claude's unless the permission layer refused it; the Action names its writes |
| `human` (`ids`, never `deferred_ids`) | his row: the statement and his command to record the answer, with "(my recommendation)" from `human.text` |
| `in_progress` held by claude | a Claude row ahead of `ready`; held by anyone else, a state bullet |
| `host_git.dirty` or `local_git.dirty` | his row: a show row first (`git diff`), a **destroys:** row only in a capture after the show row ran |
| `health` with `ran` false and a command | a Claude row to run it when no row is P0, his row once the permission layer refuses |
| a section with `error` | a Claude row to retry that read, or his to run the command by hand; `precondition: true` is one row for all of them |
| `blocked`, `deferred`, `stale` | never a row; the trailing line |
| `cut_off` not null | no rows at all |

Priority is `P` plus the bead's integer (null reads P2); a row with no bead inherits the priority of the highest bead it stands in front of (a bead whose row cannot run until this one has, named in Why now), else P2. Sort: 1 priority ascending; 2 `blockers` count descending; 3 Ari before Claude; 4 oldest `updated_at` first. Pane: a row from a host section is the capture's pane; a `local_git` row is this Mac; a refused-command row is where the refusal happened. The sixth row and beyond go to the trailing line as "Also ready: …".

### Yes and no

| Ari says | It means |
|---|---|
| "yes", "y", "go", "ok", "do it", "row 1" | a yes to row 1 |
| "row N", a bead id, a row's title verbatim | a yes to that row, re-rendered as row 1 without a capture |
| Enter in his pane | the yes for his own typed row; no chat yes is needed |
| pasted output | that row's result |
| "yes" to a **destroys:** or **irreversible:** row | only "yes", the row number or the row's name; "ok", "go" or a yes inside a message that also corrects something re-renders and asks once more |
| a yes that re-orders or drops rows | a yes to the changed table, re-rendered without a capture and asked again; nothing new typed while a typed line sits un-entered |
| a partial match, or words matching two rows | the one question "Which row?" |
| a tracker correction ("that bead is done") | a row with its `bd` command |
| a rendering correction | re-render, no capture |
| a fact outside the tracker | one bullet "Ari said: …"; the capture's fact stays until the next capture |
| a bare no | "What is wrong?" |
| an instruction with the invocation | row 1 "(your instruction)", run only after his yes |

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
| agent's command | a command a Claude session, fork or lane typed through `run.zsh` (wrapped in `run_log`), or a `BEADS_ACTOR=claude bd` write; Ari types bare |

### The header

Line 1 of every reply is the stdout of `bin/brief.zsh --header` on the newest capture, pasted as printed, never typed by hand; its forms are `templates/briefing.md` › Line 1.

### Overrides

| Base skill › section | What this skill does instead | Why |
|---|---|---|
| `/ari-driving-remote` › Exit codes › 75, "never retry on your own" | `frontier.zsh` retries every 5 s within the capture budget when the pane runs an agent's command | the pane is busy with Claude's own work, not Ari's; waiting is the only move that is not his |
| `/ari-bead-driven-development` › Cut off | the cut-off output is `brief.zsh --cut-off` and the whole reply | one renderer for the base rule |

### Exit codes

| Script | Codes |
|---|---|
| `bin/frontier.zsh` | 0 the JSON was written, cut off or not; 1 a missing prerequisite (`jq git base64 gzip gunzip awk`, and `timeout` or `gtimeout` in host mode), a bad flag, an unreadable `--previous`, a bad `--prefix`, `FRONTIER_RETRY_S` not a positive integer, or `CLAUDE_CODE_SESSION_ID` unset without `--local` |
| `bin/brief.zsh` | 0 printed; 3 the cut-off output was printed (the paragraph or a waiting line); 1 a bad call or a file that is not a capture |
| `bin/mode.zsh` | 0 on, or done; 3 off (`status`); 1 a bad call |
| `bin/pending.zsh` | 0 done, or shown; 3 nothing recorded (`show`); 1 a bad call, or `--text` carrying the `TYPED: ` prefix |

### The offer

Off, on an orienting question, this line and nothing else: "Want operator mode? `/ari-operator-mode` reads the tracker, the checkouts and your pane and briefs you from scratch." Orienting: "where are we", "what's next", "catch me up", "remind me what's going on", "I haven't read any of this", a return after a gap that opens with a question about state. Not orienting: a specific question, an instruction, anything while the mode is on.

## Input

`<host-definition>` and `<pane>` come from his words this turn, else `run.zsh --hosts` then `--list` (`/ari-driving-remote` › Read the known hosts), never a `%N` from history; `<beads>` and `<repo>` from his words, the project's `CLAUDE.md` or memory; `<health>` from the project's doctor command. An unknown pane makes the entry reply the acknowledgement plus the one question "Which pane holds the tracker?" and no capture.

## Workflow

### Every turn, first

```zsh
zsh $HOME/.claude/skills/ari-operator-mode/bin/mode.zsh status
```

Exit 0: the mode is on and the reply follows **Proceed**. Exit 3: off; an orienting question gets the offer, anything else the default style. Only this exit code decides, never the transcript, a summary or memory.

### Enter the mode

```zsh
zsh $HOME/.claude/skills/ari-operator-mode/bin/mode.zsh on
```

The acknowledgement goes out before the capture, so the wait is announced: "Operator mode on. Reading the tracker through `<label with nickname>`: seven read-only commands, up to 45 s each; then I type your first row onto that prompt, un-entered." An instruction given with the invocation is row 1 "(your instruction)", not run this turn. Then **Capture** and **Brief** in the same turn.

### Capture

One call, the Bash tool's timeout at 600000 ms and never in the background (the capture's budget is `--timeout`, 45 s, times its seven host reads, retries included):

```zsh
zsh $HOME/.claude/skills/ari-operator-mode/bin/frontier.zsh --host-definition <host-definition> --target <pane> --beads <beads> --repo <repo> --local-repo "$PWD" --health '<health>'
```

A tracker and checkout on this Mac take `--local` in place of the host flags. The pending row is read from `bin/pending.zsh`'s marker, so `--pending` is passed only to override it. It prints `dir=`, `json=` and `cut_off=`; the folder is the investigation folder below. A non-zero exit from a bad flag or an unset session id is Claude's to fix and run once more; a missing prerequisite on this Mac is his P0 with the install command as his row and the one question "Fixed?".

### Brief

1. `cut_off=` is not `none`: the whole reply is the stdout of the command below, and nothing else happens this turn.
   ```zsh
   zsh $HOME/.claude/skills/ari-operator-mode/bin/brief.zsh --dir <dir> --cut-off
   ```
2. Row 1 is his, on the capture's pane, neither destroys nor irreversible, and no other agent uses the pane (Reference › Shared pane): type it, then record it.
   ```zsh
   zsh $HOME/.claude/skills/ari-driving-remote/bin/run.zsh --host-definition <host-definition> --target <pane> --no-enter --cmd '<row 1 command>'
   zsh $HOME/.claude/skills/ari-operator-mode/bin/pending.zsh set --text '<the text after TYPED:>'
   ```
   The key reports the run per `templates/briefing.md` › The table; exit 1 (the reader's own text refused) means rewrite the command on one line and type again, never wait.
3. Read `templates/briefing.md` and render it from the JSON, in its order, adding nothing; `templates/briefing.example.md` is what it looks like filled.

### Proceed

On a yes (Reference › Yes and no):

1. Row 1 is his and typed: his Enter is the yes; nothing to do until he reports. Refused with 75 in Brief: type it once now and report that run the same way; never retype a row whose run printed `TYPED:`; a second refusal re-renders the row with "not typed: <why>" and asks "Clear it?".
2. Row 1 is Claude's: do it, through `/ari-bead-driven-development` (Pick, Close, Ask Ari a decision) and `/ari-driving-remote`. A long row reports at three points, each the header and one sentence, no question: claimed, committed (hash), closed or PR opened. A row that fails: Capture, header, "Row 1 failed: <last line>", then the table with the row as "retry row 1", or as his row with the refused command verbatim; never a retried write without a yes.
3. He reports an outcome (entered, pasted its output, cleared; a bead changed, a commit, a file written): `bin/pending.zsh clear` when it was his typed row, then **Capture**. A question-only reply does not capture.
4. **Brief** again: cut-off check, type the new row 1 if it is his, header with `--phase 'after row N'`, one sentence per fact of what happened and what it printed, the table, the one question.

```zsh
zsh $HOME/.claude/skills/ari-operator-mode/bin/brief.zsh --dir <dir> --header --phase 'after row 1'
```

On a no: the row in Reference › Yes and no; **Capture** and **Brief** when the tracker was corrected, a re-render otherwise.

### Leave the mode

On `stop operator mode` or `normal mode`: `zsh $HOME/.claude/skills/ari-operator-mode/bin/mode.zsh off`, one line "Operator mode off.", then the default style.

## Investigation folder

```
/tmp/operator-mode/
├── ON-<session id>          # the mode marker: present while the mode is on, holds the time it was switched on
├── PENDING-<session id>     # the row typed onto his prompt and not yet entered or cleared (bin/pending.zsh)
└── <UTC stamp>/
    └── frontier.json        # one capture; frontier.zsh makes the folder and prints its path as dir=
```

## File storage

- `bin/frontier.zsh` — the one reader of state, and the only script here that touches a pane, through `/ari-driving-remote`'s `run.zsh`; needs `/ari-skill-shellscripts`' `lib/logging.zsh`, `lib/run_with_timeout.zsh` and `lib/investigation_folder.zsh`.
- `bin/brief.zsh` — the header line and the cut-off output (the paragraph or a waiting line), from a capture.
- `bin/mode.zsh` — the on/off marker; `bin/pending.zsh` — the typed-row marker.
- `templates/briefing.md` — the render spec; `templates/briefing.example.md` — the spec filled, plus the scenarios; `templates/frontier.example.json` — the capture it renders.
- `tests/frontier.test.zsh` — the suite for all four scripts, against `tests/fake-run.zsh`, a fake `run.zsh`; run it after any edit to `bin/` or `templates/`: `zsh $HOME/.claude/skills/ari-operator-mode/tests/frontier.test.zsh`.
