# Briefing: the render spec

Render one briefing from one capture (`frontier.json`), in this order, with nothing the JSON does not hold. Every sentence traces to one section of the JSON, or to this turn's `run.zsh --no-enter` result for row 1 when it is Ari's; delete a sentence that traces to neither. When to capture, type or ask is `SKILL.md › Workflow`; this file is only the shape of the reply. The filled example is `briefing.example.md`; the capture it renders is `frontier.example.json`.

## Line 1: the header

The stdout of `brief.zsh --header`, pasted as printed, then a blank line:

```
Ready N, in progress N, human N, blocked N, stale N; <checkout> <hash> clean|dirty N; read HH:MMZ[; waited Ns for <pane>]; <phase>
```

- a section that errored reads `failed`; `human` counts the gates that wait on him (a deferred one is not among them)
- `<checkout>` is the host's, or `this Mac` when the host checkout was skipped or unread
- `; waited Ns for <pane>` appears when the capture waited on an agent's command there
- `<phase>` is `fresh read`, or `--phase 'after row N'` once a row landed
- a cut-off capture prints `Cut off: <label> (<reason>); tracker unread; read HH:MMZ` and the paragraph replaces it; for the four wait reasons the header is the waiting line itself
- the time is the capture's: a reply that did not capture shows the older time

## First principles: one sentence

Where the tracker is (`beads_dir` on `host_definition`), how Claude reaches it (`pane` with `nickname`), where the checkouts are (`repo`, `local_repo`), and the health command (`health.command`), with every term the briefing goes on to use defined at its first appearance as a two-to-five-word parenthetical from `SKILL.md › Reference › Terms`. Ninety words at most. A term whose section is empty this capture is left out; a null `health.command` means no doctor is named.

## `**State right now**`

One sentence per bullet, at most six; a section that is empty has no bullet:

- `ready`: the count and the top bead as id, title and priority.
- `in_progress`: each bead as id, title and holder; one that `stale` lists says so.
- `human`: the count and each id with its title; `deferred_ids` are not counted.
- `blocked` and `deferred`: one bullet, counts only; the ids go in the trailing line.
- `host_git` and `local_git`: one bullet: the host's dirty paths by name or "clean", then its three latest commits as hash and subject; then this Mac's head and dirt only when its head differs from the host's or its `dirty` is non-empty.
- `health`: "<command> has not been run this capture" when `ran` is false; no bullet when `command` is null.
- A section holding `{"error": …}`: "`<section>` could not be read: <why>"; one with `precondition: true` is said once for all of them.

## The table

At most five rows, unblocked only, columns `# | Action | Priority | Who | Why now`; sources, priority, order and pane are `SKILL.md › Reference › Row triage`. Cell formats: `Who` is exactly `Ari` or `Claude`; a priority of null renders P2; a Claude row's Action names its writes (claim, branch, PR, merge, deploy); an Action that discards work opens with **destroys:** and what is lost, one that ships work (merge, deploy, push to main, delete data) opens with **irreversible:** and what ships.

Every row of Ari's carries its command under the table, keyed by row and pane, with one sentence of what it does and one of what it prints. The block holds the bare command passed to `--cmd`; `run.zsh` wraps it in `run_log` on his prompt. Only row 1 is ever typed; the key says what happened:

| When | Key, ending in the colon that opens the fence |
|---|---|
| row 1, `run.zsh --no-enter` printed `TYPED:` | "Row 1, typed into `<label>`, not entered:" |
| row 1, the run was refused (exit 75, 70, 76, 77 or 255) | "Row 1, for `<label>`, not typed: <the why after `REFUSED: <label>`>; <the move from Cut-off reasons>:" |
| row 1, no run attempted: `waited_s` > 0, or a background agent of this session is using the pane | "Row 1, for `<label>`, not typed: another agent is using this pane; typed when it is free:" |
| row 1 opens with **destroys:** or **irreversible:** | "Row 1, for `<label>`, not typed: destroys <what>; typed after your yes:" |
| any later row of his | "Row N, for `<label>`, not typed yet:" |

A local row (this Mac) carries the click-to-type link `/ari-driving-tmux` mints under the local pane's label, never a hand-written one; when no link can be minted, a fenced block under that label, never a bare command.

When no row is unblocked, one line replaces the table: "Nothing is unblocked: N blocked, N deferred, N waiting on you." (`failed` for an errored count). The trailing line and the question stay.

## One trailing line

"Blocked: N (<id> on <blocker>, …). Deferred: N. Stale: N (<id>, <age>). Also ready: <ids beyond row five>." Each clause only when its count is non-zero.

## Exactly one question

One sentence saying what a no does, then the one question mark of the reply. Row 1 is Claude's: "A no is a correction. Row 1 next?" Row 1 is his and typed: "A no is a correction. Row 1 is on `<label>`: Enter it?" Row 1 destroys or is irreversible: "A no is a correction. Discard the edit to `bin/lab` (row 1)?" (the thing named). A bead title that holds a question mark is paraphrased as a statement.

## Cut off

`cut_off` not null: the whole reply is the stdout of `brief.zsh --cut-off`, nothing before or after it (`SKILL.md › Rules › Cut off`).
