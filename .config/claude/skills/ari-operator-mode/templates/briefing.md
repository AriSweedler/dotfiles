# Briefing: the render spec

Render one briefing from one capture (`frontier.json`), in this order, with nothing the JSON does not hold (`SKILL.md › Rules › The script reads`; the exceptions are `SKILL.md › Reference › Outside facts`). When to capture, type or ask is `SKILL.md › Workflow`; this file is only the shape of the reply. The filled example is `briefing.example.md`; the capture it renders is `frontier.example.json`.

## Line 1: the header

The stdout of `brief.zsh --header`, pasted as printed, then a blank line:

```
Ready N, in progress N, human N, blocked N, stale N; <checkout> <hash> clean|dirty N; read HH:MMZ[; waited Ns for <pane>]; <phase>
```

- a section that errored reads `failed`; `human` counts the gates that wait on him (a deferred one is not among them)
- `<checkout>` is the host's, `<host> checkout failed` when its read errored, or `this Mac` when the host checkout was skipped or unread
- `; waited Ns for <pane>` appears when the capture waited on an agent's command there; the pane is `pane`, without its nickname
- `; host answered` appears once, on the capture that ended an announced absence (`away_ended` true)
- `<phase>` is `fresh read`, `--phase 'after row N'` once his row landed, or `--phase 'after <bead id or instruction>'` once Claude's run, or its record of his answer, ended
- the time is the capture's: a reply that did not capture shows the older time
- a cut-off capture prints `Cut off: <label> (<reason>); tracker unread; read HH:MMZ`, and the paragraph replaces it
- for the four wait reasons (`own_command`, `own_command_persists`, `row_pending`, `row_running`) the header is the waiting line itself
- an announced absence (`away` set, `host_unreachable` or `read_timed_out`) prints `Away: <host_definition> (<reason>); tracker unread; read HH:MMZ`, and the away line replaces it; the host is named, not a pane, because a listing that never answered resolves none

The replies that do not open with the header: the entry turn (the acknowledgement comes first, the header second), the unknown-pane and unknown-scope replies (the acknowledgement and one question), every cut-off reply (`brief.zsh --cut-off` is the whole reply), and the one-line replies (`Which row?`, `What is wrong?`, `Fixed?`, a second capture failure).

## Which parts each reply carries

- The entry turn: every part below, in order.
- A later fresh read: every part but First principles.
- After a run (his row, Claude's run, or Claude's record of his answer): the header, the outcome sentence in place of First principles and the state bullets, then the table, the trailing line and the question, when one fits.
- His instruction, with the invocation or later: the briefing that turn carries (the entry turn's parts, or none mid-mode) without its question, then the start line "Starting <the instruction>: <its writes>; <its step that ships or destroys> waits on your yes." (with none, it ends at its writes), then the run's progress lines, then the after-a-run parts, whose question names the step that ships or destroys, else row 1's form or the no-row form.
- A progress or completion-notice line: the newest header plus one sentence, no question.

## First principles: one sentence

Where the tracker is (`beads_dir` on `host_definition`), the *scope* read from it (`scope.epics`, or the whole workspace when `scope` is null or `all`), how Claude reaches it (`pane` with `nickname`), where the checkouts are (`repo`, `local_repo`), and the health command (`health.command`), with every term the briefing goes on to use defined at its first appearance as a two-to-five-word parenthetical from `SKILL.md › Reference › Terms`. Ninety words at most. A term whose section is empty this capture is left out; a null `health.command` means no doctor is named.

## `**State right now**`

One sentence per bullet, at most six; a section that is empty has no bullet; when more would fill, drop the `health` bullet, then the `blocked` and `deferred` bullet (the header and the trailing line carry its counts), never the `scope` bullet. An empty tracker (every `bd` section empty) is one bullet, "The tracker holds nothing ready, in progress, blocked, deferred or waiting on you.", and the header `**State right now**` is left out:

- `ready`: the count (epics included) and the first bead that is not an epic (`type` `epic`), in Row triage's sort, as id, title and priority; the count alone when every one is an epic.
- `in_progress`: each bead as id, title and holder, "held by this session" for `holder` `self`, "held by another session" for `other` (a bare `claude` or a `claude:<uuid>` that is not this session's) and the assignee itself when it is a person; one that `stale` lists says so.
- `human`: the count (the header's, "mine" gates included) and each id with its title (the text after the id up to the first `: `), a gate whose act Claude's tools can perform marked "mine"; `deferred_ids` are not counted.
- `blocked` and `deferred`: one bullet, counts only; the ids go in the trailing line.
- `host_git` and `local_git`: one bullet. For the host: "clean" when `dirty` is empty; else the `own` paths by name, then the other `dirty` entries as "N uncommitted edits not listed as this session's", never by path. Then its three latest commits as hash and subject. Then this Mac's head and dirt the same way, only when its head differs from the host's or its `dirty` is non-empty.
- `scope`: a bullet only for `unknown` ("`<id>` is no open bead in this workspace (a typo, or a closed epic); only its open children with its id in theirs are shown.") or `error` ("The bead map could not be read: <why>; a bead joined to the epic after it was created may be missing.").
- `health`: "<command> has not been run this capture" when `ran` is false; no bullet when `command` is null.
- A section holding `{"error": …}`: "`<section>` could not be read: <why>"; one with `precondition: true` is said once for all of them.

## The table

At most five rows, columns `# | Action | Priority | Why now`. **The only sources, and what is never a row, are `SKILL.md › Reference › Row triage`;** priority, order and pane are there too. Cell formats: a priority of null renders P2; the Action names its writes (I record your answer, commits, discards); an Action that discards work opens with **destroys:** and what is lost, one that ships work (`SKILL.md › Reference › Terms`) opens with **irreversible:** and what ships.

Every row but an answer row carries its command under the table, keyed by row and pane, with one sentence of what it does and one of what it prints. The block holds the bare command passed to `--cmd`; `run.zsh` wraps it in `run_log` on his prompt. An answer row has no command; its key is one line, "Row N, your answer, said here; I record it on <id>." Only row 1 is ever typed; the key says what happened:

| When | Key, ending in the colon that opens the fence |
|---|---|
| row 1, `run.zsh --no-enter` printed `TYPED:` | "Row 1, typed into `<label>`, not entered:" |
| row 1, the run was refused (exit 75, 70, 76, 77 or 255) | "Row 1, for `<label>`, not typed: <the why after `REFUSED: <label>`>; <the move from Cut-off reasons, for the reason the `REFUSED_KIND:` line gives (SKILL.md › How a 75 is classified)>:" |
| row 1, no run attempted: another agent uses the pane (`SKILL.md › Reference › Shared pane`) | "Row 1, for `<label>`, not typed: another agent is using this pane; typed when it is free:" |
| row 1 opens with **destroys:** or **irreversible:** | "Row 1, for `<label>`, not typed: <destroys|ships> <what>; typed after your yes:" |
| a row on this Mac (a `local_git` row, or any row of a `--local` capture) | "Row N, for `<label>`, a link:", or "Row N, for `<label>`, a link; it destroys <what>:" |
| any later row, or row 1 on a pane that is not the capture's | "Row N, for `<label>`, not typed yet:" |

A local row (this Mac) carries the link `/ari-driving-tmux` mints under the local pane's label, never a hand-written one: click-to-run for a show row, so its output comes back, click-to-type for a **destroys:** row; when no link can be minted, a fenced block under that label, never a bare command.

When there is no row, one line replaces the table: "Nothing needs you." when `human`, `host_git` and `local_git` were read, else "Nothing known to need you; `<section>` could not be read." The trailing line stays.

## One trailing line

"Blocked: N (<id> on <blocker>, …). Deferred: N. Stale: N (<id>, <age>). Also yours: <rows beyond row five, by name>." Each clause only when its count is non-zero; a blocker outside the scope is "a bead outside the scope", as `blocked.text` already says.

## At most one question

A question only when something waits on him; then one sentence saying what a no does and the one question mark of the reply, in the first form that fits, and with no form fitting, the reply ends on a statement:

| When | The question |
|---|---|
| row 1 destroys or is irreversible | "A no is a correction. Discard the edit to `bin/lab` (row 1)?" (the thing named) |
| a step of Claude's run destroys or ships | "A no is a correction. Merge PR #12 for beads-abc?" (the step named) |
| Claude's run of his instruction failed | "A no is a correction. Retry <the failed step> for <the bead id or instruction>?" |
| row 1 is an answer row | "A no is a correction; other words are your answer. Answer beads-h1 "Decide the indexers" (row 1) with my recommendation, stop at 1337x and TPB?"; with no recommendation, "A no is a correction; other words are your answer. Your answer to beads-h1 "Decide the indexers" (row 1)?" |
| row 1 on this Mac (a link) | "A no is a correction. Click row 1's link for `<label>`?" |
| row 1 typed | "A no is a correction. Row 1 is on `<label>`: Enter it?" |
| row 1 not typed: the pane runs his program | "A no is a correction. Free `<label>` (<the why>) so I can type row 1?" |
| row 1 not typed: another agent uses the pane | none: the key already says it is typed when the pane is free |
| no row | none: the reply ends "Your next message reads again, and `stop operator mode` leaves." |

The one-line replies a question may also take: "Which bead or row?", "What is wrong?", "Fixed?", "Which pane holds the tracker?", "Which epic is this session's?", "Name an epic, or `stop operator mode`?", and the cut-off and waiting lines `brief.zsh` prints. **NEVER another question, and NEVER one whose yes only starts work** (`SKILL.md › Rules › What he said is not asked again`). A form that loses keeps its row or step pending; a yes answers only the form asked. A bead title that holds a question mark is paraphrased as a statement, anywhere in the reply.

## Not in this capture

Asked for something the JSON lacks, a fact a read can supply is his instruction to read it: a section the capture holds is captured again, a bead's body is read with `bd -C <beads> show <id>` through `run.zsh` for a bead the capture lists, and the answer is that output, verbatim. Only a fact no read supplies, or a bead outside the scope, is "Not in this capture; no read gives it." Either ends with the newest briefing's one question, when it has one. Depth on a section the capture holds is its raw text, verbatim, then that question.

## Cut off

`cut_off` not null: the whole reply is the stdout of `brief.zsh --cut-off`, nothing before or after it (`SKILL.md › Rules › Cut off`).
