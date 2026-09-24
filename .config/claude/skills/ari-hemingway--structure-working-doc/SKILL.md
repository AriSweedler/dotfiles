---
name: ari-hemingway--structure-working-doc
description: "Keep a working doc for a session that has piled up many orthogonal asks: one file per ask holding the user's words verbatim, a dependency-ordered table (the DAG flattened so every Needs cites an earlier row, checked mechanically), and per-ask dispatch to subagents or workflows with status tracking. Modes: capture (from this session), resume (an existing folder). Use when a conversation has accumulated several independent requests, when context is about to compact, or when the user asks for a working doc, a task table with dependencies, or to fan the asks out."
---

# Working Doc

Keep one working doc for a session with many unrelated asks: what was asked, in the user's words; what each ask needs first; who is on it; what came back. The doc is a folder on disk that outlives the conversation, and its table is the one view the user needs to steer.

Formatting: GitHub-flavored Markdown as the terminal and GitHub render it; no `/ari-hemingway--format-*` sibling applies to the folder. When the user asks to publish, `/ari-hemingway--format-gdoc` rules apply to `output.md` and `/ari-hemingway--share-gdoc` publishes it. Workflow patterns (investigation folder, restore context, drafting, fact-check, present/output): see `/ari-hemingway--lib`.

## Modes

- **Capture** (default) — comb this session for every ask and build the folder.
- **Resume** — reopen an existing folder (lib `Restore context`), re-render, continue tracking.

Both modes then loop: new user messages add rows, notifications close them, the table is re-rendered.

## Document structure

The doc is a folder. `asks.json` is the source of truth for id, title, needs, status and owner; `asks/<id>.md` holds the prose; `draft.md` is the rendered view.

```
{investigation_folder}/
├── scratchpad.md      # lib baseline + the fields under Investigation folder below
├── sources.md         # lib schema
├── asks.json          # {"asks": [{id, title, needs, status, owner, dispatch?, updated}]}
├── asks/<id>.md       # one file per ask: Ask · Context · Brief · Result
├── drafts/            # scratch for dispatched agents; never linked from draft.md
├── draft.md           # Summary, the table, one line per ask with its file link
└── output.md          # Finalize: draft.md with every ask file inlined
```

### draft.md

```
# <Subject> — working doc

<Summary: 2 to 4 sentences. What the session is about; how many asks, how many done, how many running; what the user must decide next, if anything.>

## Asks
<the table, from `asks.zsh table --links`>

## Sections
### <n> <Title>
<one line: where it stands> · [asks/<id>.md](asks/<id>.md)

## Decisions
- <date> <a decision the user made that cuts across asks, verbatim when short>

## Sources
See [sources.md](sources.md).
```

### asks/<id>.md

Four sections, always in this order, from `templates/ask.md`:

- `## Ask` — the user's words, verbatim, one blockquote per message, oldest first. Nothing else. A message that constrains an ask without defining it (a language choice, a naming rule) is quoted here too, after the defining message.
- `## Context` — what is already known or decided, each finding with its source. Sibling asks by file link (`[plugged-tui](plugged-tui.md)`). Under 400 words.
- `## Brief` — self-contained instructions for whoever does the work: inputs, constraints, definition of done, where to report. Written so a fresh agent with no conversation history can execute it. Under 400 words.
- `## Result` — outcome first, then artifacts (paths, URLs, SHAs), then what is left. Whoever does the work writes it; nobody else edits it while the ask is `running`.

## Rules

### The table

- Columns `# | Ask | Needs | Status | Owner`, nothing more. `#` is the row's position after flattening; `Needs` lists positions of earlier rows or `-`.
- Rows are in dependency order: a row may Need a row ONLY if that row is earlier. The order is computed from `asks.json` (Kahn's algorithm, stable on file order), never hand-arranged, so the DAG is linear by construction. Two rows with no path between them keep their file order.
- A row Needs another only when it cannot start, or cannot finish correctly, before the other is `done` or `dropped`. "Nicer after" is not a Need; say so in Context. Sparse edges keep the table readable.
- Status is one of `todo`, `running`, `review`, `done`, `dropped`. `review` means the work came back and the user has not looked. Blocked is not a status: a `todo` row whose Needs are unsettled is blocked, and `check` prints the ready set.
- Owner is `main` (this thread), `user` (only the user can do it), `agent:<name>`, `fork:<name>` or `wf:<id>`.
- Titles are at most 8 words and are the only place an ask is paraphrased. Target under 25 rows; hard maximum 40. Past that, group asks under one row and split the details into that row's Context, or open a second working doc.
- The table MUST pass the mechanical check before it is shown and again before Output. `table` refuses to render a failing table; fix every violation, never present one.
  ```zsh
  zsh $HOME/.claude/skills/ari-hemingway--structure-working-doc/bin/asks.zsh check --file <folder>/asks.json
  zsh $HOME/.claude/skills/ari-hemingway--structure-working-doc/bin/asks.zsh table --file <folder>/asks.json
  ```
- The table is how the DAG surfaces to the user, in chat, in one message. When a flow chart can be shown in chat, show `asks.zsh graph` (a Mermaid `flowchart LR` of the same rows) instead; until then the table is the surface, and the graph is baked into `draft.md` only on request via `/ari-diagram-mermaid`.
- Glyphs in table cells are ASCII or single-cell symbols; no emoji with variation selectors, no keycaps.

### Capturing asks

- Every user message counts, including messages that arrived mid-turn and the arguments of a `/subtask` or other slash command. An ask is an imperative or a question the user expects acted on. A statement of preference or constraint attaches to the ask it scopes.
- Quote, never paraphrase, inside `## Ask`. Keep the user's spelling. One blockquote per message, in arrival order.
- One row per distinct deliverable. A question answered in chat becomes a row only when the user will want to find the answer later; otherwise its answer goes into the Context of the ask it informs.
- Work already finished before the doc existed still gets a row, status `done`, with the Result filled from the session. The doc is the record, not a to-do list.

### Ownership and dispatch

- An ask is dispatchable when its Brief is self-contained, its work writes only under paths the Brief names (a repo the ask owns, `drafts/` in this folder), it commits nothing to a dotfiles tier, pushes nothing, creates no remote resource, and needs no user decision midway. Anything else stays `main` or `user`.
- Vehicles: `Explore` for read-only research; `general-purpose` for building; `fork` only when the Brief cannot be made self-contained, because a fork carries the whole conversation and costs accordingly; `Workflow` only when the ask is itself a multi-agent job and the user has opted into workflows. Keep panels for new designs and reviews to about five agents; prefer a pipeline to barriers.
- Dispatch is the user's call. After the table is accepted, list the ready rows and start only those the user names. When the user said at invocation to dispatch whenever possible, `Auto-dispatch: on` in the scratchpad, and ready rows start without asking, `main`- and `user`-owned rows excepted.
- The agent prompt is the ask file's `## Ask`, `## Context` and `## Brief` verbatim, plus one instruction: write the report into `## Result` of that file and touch nothing else in the folder. Record `dispatch: vehicle:ref` and status `running` with `asks.zsh set` before the Agent or Workflow call returns.
- Never predict or invent a pending agent's result. Until its notification arrives, the row is `running` and the Result is whatever the agent last wrote.

### Durability

The lib root is under `/tmp`. macOS clears it on reboot and prunes files untouched for three days. Say so once, at Gather pointers, in one line. Output copies the folder to a durable path the user names when they want it kept; never pick that path for them.

## Investigation folder

Root path: `/tmp/hemingway/structure-working-doc/{topic-slug}/{timestamp}/`. Structure, schemas, derivation rules, and cadence all follow `/ari-hemingway--lib`. Additional files: `asks.json`, `asks/<id>.md`, `drafts/`.

Scratchpad fields appended after `Last phase`:
```
- **Asks**: <n> rows, <k> done, <r> running, ready: <ids or none>
- **Auto-dispatch**: on | off
- **Dispatched**: <id> → <vehicle>:<ref> (<status>); ...
- **Durable copy**: <path> | none
```

## File storage

- `bin/asks.zsh` — `add` a row (creates `asks/<id>.md` from the template), `set` title/needs/status/owner/dispatch, `check` (violations, missing files, ready set; exits 1 on any violation), `table` (`--links` for draft.md), `graph` (Mermaid). All writes go through jq to a temp file, then mv.
- `lib/asks.jq` — the flattening (`ordered`, `position`), `violations`, `ready`, `table_md`, `mermaid`.
- `templates/ask.md` — the four sections of an ask file.

## Workflow

### Gather pointers

Collect the subject (a phrase the user would type again to resume, dated when the session is), whether dispatch is automatic, and any destination for a durable copy. Derive `{topic-slug}` and create the investigation folder per `/ari-hemingway--lib` with `--skill-name structure-working-doc`. Write the initial scratchpad (Subject, Mode `capture` or `resume`, Pointers, Auto-dispatch). Print the one durability line.

### Restore context

Follow the `Restore context` procedure in `$HOME/.claude/skills/ari-hemingway--lib/SKILL.md`. On resume, run `check` and print the table before anything else, then continue at Track.

### Capture

Walk the session from the first user message to the latest. For each ask: `asks.zsh add --id <slug> --title "<title>" [--needs a,b] [--status s] [--owner o]`, then fill `## Ask` with the verbatim quotes and `## Context` with what the session already established, sources in `sources.md` per lib cadence. Fill `## Result` for asks already finished. Write `## Brief` for every row not `done`.

Print: `Capture complete — {n} asks from {m} messages. Next: Order.`

### Order

Run `check`; fix violations by editing Needs, never by dropping a row the user asked for. Run `table` and print it in chat, in one message, no paraphrase, followed by the ready set. Wait. Apply the user's merges, splits and reorderings with `set`, re-check, re-present until accepted.

Print: `Order complete — {n} rows, 0 violations, ready: {ids}. Next: Draft.`

### Draft

Follow the `Drafting` procedure in `$HOME/.claude/skills/ari-hemingway--lib/SKILL.md`: `draft.md` is rewritten whole each time, from the accepted table (`table --links`) and the ask files. The Summary is written last.

Print: `Draft complete — {n} rows, {words} words. Next: Fact-check.`

### Fact-check

Follow the `Fact-check gate` procedure in `$HOME/.claude/skills/ari-hemingway--lib/SKILL.md`, scoped to this doc: every path in a Context or Result exists (`test -e`); every `asks/<id>.md` link resolves; every `done` row has at least one artifact line in its Result; permalinks only when code is cited. Quotes in `## Ask` are not claims and are never edited.

Print: `Fact-check complete — {n} paths verified, {k} marked [TODO: verify]. Next: Present.`

### Present

Follow the `Present` procedure in `$HOME/.claude/skills/ari-hemingway--lib/SKILL.md`. Option 1 is labeled by state: while any row is `todo`, `running` or `review`, `Dispatch — start the ready asks (rows {positions})`; when every row is `done` or `dropped`, `Finalize — write output.md`. Option 4 is disabled.

### Dispatch

For each ask the user named (or every ready, dispatchable row when auto-dispatch is on): `asks.zsh set --status running --owner <vehicle>:<name> --dispatch <vehicle>:<name>`, then the Agent or Workflow call with the prompt from Ownership and dispatch. Update the scratchpad `Dispatched` line.

Print: `Dispatch complete — {k} asks started ({vehicles}). Next: Track.`

### Track

On each task notification: read the ask file's `## Result` (copy the agent's final report there verbatim when the agent could not write it), verify the Brief's definition of done, set status `done` or `review`, run `check`, re-render `draft.md`, and print one line. On each new user message that carries an ask: add the row at once, quote it, re-check, and print the table only when the row count or order changed.

Print per event: `Track — {id} {status}: {one line}. Ready now: {ids or none}.`

When no row is `todo`, `running` or `review`, re-enter Present.

### Output

Follow the `Output` procedure in `$HOME/.claude/skills/ari-hemingway--lib/SKILL.md`. `output.md` is `draft.md` with each ask file inlined under `## <n> <Title>` in table order, so one file travels. When the user named a durable path, copy the whole folder there and record it under `Durable copy`.
