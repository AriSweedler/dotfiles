# Briefing: the render spec

One briefing is rendered from one capture (`frontier.json`), in this order, with nothing the JSON does not hold. Every sentence traces to one section of the JSON; a sentence that traces to none is deleted. The filled example is `briefing.example.md`; the capture it renders is `frontier.example.json`.

## Line 1: the header

The stdout of `brief.zsh --header`, unformatted, then a blank line. Its forms:

```
Ready 2, in progress 1, human 1, blocked 1, stale 1; laptop abc1234 dirty 1; read 09:07Z; fresh read
Ready failed, in progress 1, human 1, blocked 1, stale 1; laptop abc1234 clean; read 09:07Z; after row 1
Ready 2, in progress 0, human 0, blocked 0, stale 0; this Mac f00ba12 clean; read 09:07Z; fresh read
```

`failed` is a section that errored; `this Mac` appears when the host checkout was skipped or unread; the time is the capture's, so a reply that did not capture shows the older time.

## First principles: one sentence

Where the tracker is (`beads_dir` on `host_definition`), how Claude reaches it (`pane` with `nickname`), where the checkouts are (`repo`, `local_repo`), and the health command (`health.command`), with every term the briefing goes on to use defined at its first appearance as a two-to-five-word parenthetical, from Reference › Terms. About ninety words at most. A term whose section is empty this capture is left out.

## `**State right now**`

One bullet per non-empty section, one sentence each, at most six:

- `ready`: the count and the top bead as id, title and priority.
- `in_progress`: each bead as id, title and holder; past `stale` it says so.
- `human`: the count and each id with its title.
- `blocked` and `deferred`: counts only; the ids go in the trailing line.
- `host_git`: the dirty paths by name or "clean", then the three latest commits as hash and subject.
- `local_git`: only when its head hash differs from the host's or its `dirty` is non-empty.
- `health`: "<command> has not been run this capture" when `ran` is false.
- A section holding `{"error": …}`: "`<section>` could not be read: <why>", and a retry row.

## The table

At most five rows, unblocked only, columns `# | Action | Priority | Who | Why now`; sources, order and cell formats are Reference › Row triage. A row of Ari's carries its command under the table, keyed by row and pane:

```
Row 2, `machine=personal|ID=%18|pane=3.1|nickname=homelab`:
```zsh
git -C ~/homelab diff bin/lab
```
Shows the uncommitted change to `bin/lab`. Prints a unified diff, or nothing when only the mode changed.
```

A local row carries the click-to-type link `/ari-driving-tmux` mints, never a hand-written one; when no link can be minted, a fenced block under the pane label, never a bare command. A destructive row opens its Action with **destroys:** and what is lost.

When no row is unblocked, one line replaces the table: "Nothing is unblocked: N blocked, N deferred, N waiting on you." The trailing line and the question stay.

## One trailing line

"Blocked: N (<id> on <blocker>, …). Deferred: N. Stale: N (<id>, <age>). Also ready: <ids beyond row five>." Each clause only when its count is non-zero.

## Exactly one question

One sentence saying what a no does, then the one question mark of the reply: "A no is a correction. Row 1 next?" When row 1 is destructive the question names it: "Discard the edits to `bin/lab` (row 1)?"

## After a row lands

Header first (`--phase 'after row N'`), one sentence per fact of what happened and what it printed, then the next table or the one question. Every reply in the mode opens with the header from the newest capture; one that captured nothing shows the older time, which is the signal that it is stale.

## Cut off

`cut_off` not null: the whole reply is the paragraph `brief.zsh --cut-off` prints. No header, no table, no state, no local facts, no other work that turn.
