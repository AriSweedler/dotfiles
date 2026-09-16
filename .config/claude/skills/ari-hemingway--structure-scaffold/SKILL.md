---
name: ari-hemingway--structure-scaffold
description: "Produce a scaffold article: a complex topic broken into the sum of its parts — a summary, a linear table of shared-jargon definitions (each row uses only earlier rows), and one standalone section per subsystem. Iterative and strictly checked; definitions are built by multi-agent workflows and verified mechanically before anything else is written. Use to come up to speed on, or explain, a system you don't yet have a vocabulary for."
---

# Scaffold

Produce a scaffold article for a complex topic: a summary, a table of shared-jargon definitions, and one standalone section per subsystem. The definitions come first and are strictly checked; everything else is written in that vocabulary. Targets gdoc.

Formatting rules: see `/ari-hemingway--format-gdoc`. Workflow patterns (investigation folder, restore context, drafting, permalink resolution, fact-check, present/output): see `/ari-hemingway--lib`. Publishing: `/ari-hemingway--share-gdoc`. If any rule here appears to contradict `/ari-hemingway--format-gdoc`, the format skill wins.

## Document structure

Required sections, in order:
- Title (plain text, `[ari-hemingway scaffold] <Topic> [🤖 AI generated]`)
- `# Summary` — what the topic is and what the article covers, then one plain-text sentence naming the toolchain that generated it (`ari-hemingway`, `ari-hemingway--structure-scaffold`, `ari-hemingway--share-gdoc`, `ari-diagram-mermaid`). Never link a skill in a Doc. Written last.
- `# Definitions` — one two-column table, `Word | Definition`, then an optional layout diagram.
- `# Subsystems` — one `##` per subsystem, each standalone.
- `# Useful links` — `## Docs` lists every doc URL from the table and the body, per `/ari-hemingway--format-gdoc`. No skill links.

### Skeleton

```
[ari-hemingway scaffold] Topic [🤖 AI generated]

# Summary
This article was generated as an example output of the ari-hemingway writing pipeline: ari-hemingway--structure-scaffold shaped it, ari-hemingway--share-gdoc published it, and ari-diagram-mermaid drew the diagram. One sentence on the topic. One sentence on what this revision contains.

# Definitions

| Word | Definition |
| --- | --- |
| [prefix](https://docs.example/prefix) | The top-level directory of an installation. Everything else lives under it. |
| [keg](https://docs.example/keg) | The directory under the prefix that holds one installed version of one package. |

![Layout: how the definitions fit together](https://mermaid.ink/img/...)

# Subsystems

## Install layout
Standalone explanation in the table's vocabulary.

## Distribution
Names "Install layout" but never describes its internals.

# Useful links
## Docs
- every doc URL used in the table and the body

🤖🌸 Generated with Claude Code
```

## Rules

### Definitions table

- Two columns, `Word | Definition`. The Word cell links to the term's canonical documentation page when one exists; plain text otherwise. Never invent a URL.
- Rows are in dependency order: a definition may mention a table term ONLY if that term is an earlier row. No forward references, so the dependency graph is linear by construction.
- A definition never mentions its own term. At most 2 sentences of at most 25 words. Says what the thing IS first. No "etc", "...", "various", "and so on".
- The table is the shared jargon: subsystem sections use these words without re-explaining them, and use no other jargon.
- Literal tokens (paths, commands, flags, file names) in backticks per `/ari-hemingway--format-gdoc`.
- The table MUST pass the mechanical check before it is shown to the user and again before Output:
  ```zsh
  zsh $HOME/.claude/skills/ari-hemingway--structure-scaffold/bin/check_definitions_order.zsh --file <rows.json>
  ```
  Mentions are matched as whole words including plurals and -ed/-ing forms. Fix every violation; never present a table that fails.

### Scope — only the most important terms

The table must stay human-readable: target 25 to 35 rows, hard maximum 50. The first pass over a real topic yields 150+ candidates; the cut is a judge panel vote (`definitions_refine.js`), and unanimous votes are the default cut. Prefer nouns for things (places, files, objects, states) over command names. A term the reader can infer from plain English does not earn a row.

### Axiomatic definitions

When definitions still cycle after the layered rewrite, one term in the cycle becomes axiomatic: its definition uses no table term at all, only everyday words. An axiomatic definition is accepted only after a dedicated agent has attempted an ASD-STE100 (Simplified Technical English) rewrite of it; it then moves to the top of the table as a root row and the cycle breaks. `definitions_refine.js` does this automatically and reports the axioms; record them in `scratchpad.md`.

### Subsystem sections

- Each section is effectively standalone: a reader who has the definitions table can read it alone.
- A section MAY name another subsystem. It MUST NOT describe another subsystem's internals — that belongs in that subsystem's own section.
- Prose in the table's vocabulary only; any new jargon sends you back to the definitions pass to add a row, then resume.

### Diagrams

One small diagram after the table is welcome when it ties several definitions together (the layout of the parts). Produce it with `/ari-diagram-mermaid`, baking both `MERMAID_FORMAT=ink_url` and `MERMAID_FORMAT=live_url`, and embed it per the Diagrams rule in `/ari-hemingway--format-gdoc`: `[![alt](<ink_url>?width=620)](<live_url>)`, read from the two sidecars. The image MUST fit on one page and MUST link to its mermaid.live source; `/ari-hemingway--share-gdoc` checks both at publish time and fails otherwise. Keep it compact: a tall nested flowchart of 6 to 8 nodes fits; flatten with `direction LR` or split before adding more.

### Multi-agent workflows

The definitions passes are `Workflow` scripts shipped in `workflows/`. Invoking this skill is the user's opt-in to run them. Each pass is one workflow invocation; read its result before deciding the next. `scriptPath` and `input_json` are literal absolute paths — the Workflow tool does not expand `$HOME`. Reviewer agents are told explicitly not to flag brevity or omitted detail — without that instruction they re-bloat every row and reintroduce forward references.

## Investigation folder

Root path: `/tmp/hemingway/scaffold/{topic-slug}/{timestamp}/`. Structure, schemas, derivation rules, and cadence all follow `/ari-hemingway--lib`. Additional files:

```
definitions_pass1.json     # discover result (.result of the workflow task output)
definitions_refined.json   # refine result
definitions_final.json     # rows after hand edits; what check_definitions_order.zsh validates
diagram.mmd, diagram.ink_url.url, diagram.live_url.url
```

Scratchpad fields appended after `Last phase`:
```
- **Grounding**: <one line: where the facts come from — docs URL, local install, code paths>
- **Passes**: discover wf_<id> (<n> terms) → refine wf_<id> (<n> rows, <k> axioms)
- **Subsystems**: <agreed list>
- **Doc URL**: <after publish>
```

## File storage

- `review-rules.md` — the constraints `/ari-hemingway--review-gdoc` enforces on a scaffold draft (loaded by its Sibling reviewer).
- `bin/check_definitions_order.zsh` — the mechanical table check (jq program in `lib/check_definitions_order.jq`). Read-only, exits 1 on violations.
- `workflows/definitions_discover.js` — Workflow script: plan angles (or take `angles`), multi-angle sweep, batched first-pass definitions with verified doc links, two refuters per batch, completeness critic, dependency graph. Args: `{topic, grounding, angles?, must_terms?, subsystems_hint?}`.
- `workflows/definitions_refine.js` — Workflow script: judge-panel selection, layered STE100 rewrite, mechanical ordering check with fix rounds, axiomatic fallback, two factual refuters, recheck. Args: `{topic, grounding, input_json, terms?, judges?, min_votes?, target_rows?, must_terms?, max_sentences?, max_words?, ste100?, axiomatic?}`.

## Workflow

### Gather pointers

Collect the topic, the terms the user already wants defined (`must_terms`), any sources (docs URLs, a local install, code paths), and the audience. Derive `{topic-slug}` and create the investigation folder per `/ari-hemingway--lib` with `--skill-name scaffold`. Write the initial scratchpad (Subject, Mode `research`, Pointers, Grounding).

### Restore context

Follow the `Restore context` procedure in `$HOME/.claude/skills/ari-hemingway--lib/SKILL.md`.

### Resolve permalink SHA

Only when the topic is code in the current worktree: follow `Resolve permalink SHA` in `$HOME/.claude/skills/ari-hemingway--lib/SKILL.md`. For an external topic (a tool, a product, a protocol) skip it; doc URLs replace permalinks.

### Definitions — discover

Run the discover workflow. Pass the topic, a one-paragraph grounding (what the agents may read and run), and the must-have terms; let it plan angles unless the user named them:

```
Workflow({scriptPath: "$HOME/.claude/skills/ari-hemingway--structure-scaffold/workflows/definitions_discover.js",
          args: {topic: "...", grounding: "...", must_terms: ["..."]}})
```

When it completes, save `.result` from the task output file to `definitions_pass1.json` (`jq '.result' <output-file>`). Expect every term to be cyclic on this pass; that is the raw material, not a failure. Record the pass in the scratchpad.

Print: `Discover complete — {n} terms, {k} cyclic. Next: Refine.`

### Definitions — refine

Run the refine workflow on the discover result. Defaults are the strict cut (3 judges, unanimous, STE100 on, axiomatic fallback on):

```
Workflow({scriptPath: "$HOME/.claude/skills/ari-hemingway--structure-scaffold/workflows/definitions_refine.js",
          args: {topic: "...", grounding: "...", input_json: "<folder>/definitions_pass1.json", must_terms: ["..."]}})
```

Save `.result` to `definitions_refined.json`. If `violations` is non-empty, re-run with the offending terms removed or pass an explicit `terms` list. If the table is still long for its audience, re-run with `terms` set to the unanimous votes plus the few terms those rely on (the result's `votes` field has the tallies).

Copy the rows to `definitions_final.json`, apply hand edits (doc links the agents missed, trimmed duplication), and run the check script. Then render the table into `draft.md` and print it in chat for review — the table itself, in one message, no paraphrase — and wait. Apply the user's row cuts and rewordings, re-run the check, and re-present until accepted.

Print: `Refine complete — {n} rows, {k} axioms, 0 violations. Next: Diagram.`

### Diagram

Optional. Pick the 5 to 8 terms whose relationship is spatial or sequential (containment, flow) and draw them per the Diagrams rule. Save the `.mmd` and both `.url` sidecars into the folder; embed the linked, width-capped image after the table.

### Subsystems

Propose the subsystem list (names only, 4 to 8) and wait for the user to accept or trim. Then draft each section standalone, in the table's vocabulary. The refined pass JSON (`definitions_refined.json`, and `definitions_pass1.json` for detail the cut removed) is the primary grounding for subsystem prose: every claim traces to a row there or to a source in `sources.md`. Review each section against three criteria: (a) jargon that is not a table term, (b) any description of another subsystem's internals, (c) claims not grounded in the sources. Use one agent per section when the Agent tool is available; inside a fork, self-review each section against the same three criteria. Fix, then re-review changed sections.

Print: `Subsystems complete — {n} sections, {words} words. Next: Summary.`

### Summary and draft

Write the summary last, from the accepted table and sections. Follow the `Drafting` procedure in `$HOME/.claude/skills/ari-hemingway--lib/SKILL.md` and all `/ari-hemingway--format-gdoc` rules; the whole article is rewritten into `draft.md` as one file.

Print: `Draft complete — {sections} sections, {words} words. Next: Fact-check.`

### Fact-check

Follow the `Fact-check gate` procedure in `$HOME/.claude/skills/ari-hemingway--lib/SKILL.md`. For external topics, "the codebase" is the grounding sources; each doc URL in the table counts as a claim and must resolve.

Print: `Fact-check complete — {n} claims verified, {k} marked [TODO: verify]. Next: Present.`

### Present

Follow the `Present` procedure in `$HOME/.claude/skills/ari-hemingway--lib/SKILL.md`.

### Output

Follow the `Output` procedure in `$HOME/.claude/skills/ari-hemingway--lib/SKILL.md`, then publish with `/ari-hemingway--share-gdoc` (update in place with `--doc` for later revisions) and record the URL in the scratchpad.
