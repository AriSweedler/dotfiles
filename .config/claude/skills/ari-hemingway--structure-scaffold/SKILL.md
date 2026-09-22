---
name: ari-hemingway--structure-scaffold
description: "Produce a scaffold for a complex topic: a summary, a linear table of shared-jargon definitions (each row uses only earlier rows), and one standalone article per subsystem, where the subsystems come from clustering the concept graph. Publishes one Google Doc, or — given a Drive folder — a folder of Docs: a Glossary Doc holding the universal definitions plus one Doc per subsystem carrying its own hoisted definitions. Iterative and strictly checked; definitions are built by multi-agent workflows and verified mechanically before anything else is written. Use to come up to speed on, or explain, a system you don't yet have a vocabulary for. Skeleton mode stops after Cluster and hands the accepted table and subsystem graph to another structure skill."
---

# Scaffold

Produce a scaffold for a complex topic: a summary, a table of shared-jargon definitions, and one standalone article per subsystem. The definitions come first and are checked mechanically; the subsystems come from clustering the concept graph; everything else is written in the table's vocabulary. The output is one Google Doc or, when the user gives a Drive folder and the topic yields two or more articles, a folder of Docs: a Glossary Doc with the universal definitions and one Doc per subsystem with the definitions only it needs. In Skeleton mode, invoked by another structure skill such as `/ari-hemingway--structure-ciechanowski`, the workflow ends after Cluster: the accepted table, the cluster result and the sources are the output, and no article is drafted.

Formatting rules: see `/ari-hemingway--format-gdoc`. Workflow patterns (investigation folder, restore context, drafting, permalink resolution, fact-check, present/output): see `/ari-hemingway--lib`. Publishing: `/ari-hemingway--share-gdoc`. If any rule here appears to contradict `/ari-hemingway--format-gdoc`, the format skill wins.

## Document structure

Two layouts. **Single Doc**: no Drive folder was given, or the topic yields one article. **Folder**: a Drive folder was given and the topic yields two or more articles; one Glossary Doc plus one Doc per subsystem. Every Doc ends with `# Useful links` (`## Docs` lists every doc URL from its own table and body; no skill links) and the footer. Never mention a skill in a body; the footer credits the toolchain. Summaries are written last.

### Single Doc

Title `[🤖 AI generated] <Topic>`, then `# Summary`, `# Definitions` (one two-column table, then any diagrams), `# Subsystems` (one `##` per subsystem, each standalone), `# Useful links`, footer.

```
[🤖 AI generated] Topic

# Summary
One sentence on the topic. One sentence on what this revision contains.

# Definitions

| Word | Definition |
| --- | --- |
| [prefix](https://docs.example/prefix) | The top-level directory of an installation. Everything else lives under it. |
| [keg](https://docs.example/keg) | The directory under the prefix that holds one installed version of one package. |

[![Layout: how the definitions fit together](https://mermaid.ink/img/...?width=620)](https://mermaid.live/view#...)

# Subsystems

## Install layout
Standalone explanation in the table's vocabulary.

## Distribution
Names "Install layout" but never describes its internals.

# Useful links
## Docs
- every doc URL used in the table and the body

🤖🌸 Generated with Claude Code with the ari-hemingway skill
```

### Folder: Glossary Doc

Title `[🤖 AI generated] <Topic> — Glossary`. `# Definitions` holds the universal rows only, then any diagrams (a layout of table terms, for example). `# Sub-explainers` opens with the cluster diagram, then lists every subsystem Doc as a raw `docs.google.com` URL (a smart chip after publish), one per line, in cluster order.

```
[🤖 AI generated] Topic — Glossary

# Summary
One sentence on the topic. One sentence naming the sub-explainers this glossary serves.

# Definitions

| Word | Definition |
| --- | --- |
| [prefix](https://docs.example/prefix) | The top-level directory of an installation. Everything else lives under it. |

# Sub-explainers

[![Subsystems: how the clusters depend on each other](https://mermaid.ink/img/...?width=620)](https://mermaid.live/view#...)

- https://docs.google.com/document/d/<install-layout doc id>
- https://docs.google.com/document/d/<distribution doc id>

# Useful links
## Docs
- every doc URL used in this table

🤖🌸 Generated with Claude Code with the ari-hemingway skill
```

### Folder: Subsystem Doc

Title `[🤖 AI generated] <Topic> — <Subsystem>`. The Summary's second sentence links the Glossary as a raw URL. `# Definitions` is present only when rows hoist into this subsystem; each may lean on a Glossary row, never the reverse. A subsystem with no hoisted rows omits the section and its prose runs on Glossary vocabulary alone. One `#` section per heading the cluster step proposed.

```
[🤖 AI generated] Topic — Install layout

# Summary
One sentence on the subsystem. Vocabulary: https://docs.google.com/document/d/<glossary doc id>

# Definitions

| Word | Definition |
| --- | --- |
| [keg](https://docs.example/keg) | The directory under the prefix that holds one installed version of one package. |

# Cellar
Standalone explanation in the vocabulary of the Glossary plus this table.

# Linking
Names "Distribution" but never describes its internals.

# Useful links
## Docs
- every doc URL used in this table and body

🤖🌸 Generated with Claude Code with the ari-hemingway skill
```

## Rules

### Definitions table

- Two columns, `Word | Definition`. The Word cell links to the term's canonical documentation page when one exists; plain text otherwise. Never invent a URL.
- Rows are in dependency order: a definition may mention a table term ONLY if that term is an earlier row. No forward references, so the dependency graph is linear by construction.
- A definition never mentions its own term. At most 2 sentences of at most 25 words. Says what the thing IS first. No "etc", "...", "various", "and so on".
- The table is the shared jargon: subsystem articles use these words without re-explaining them, and use no other jargon. In the folder layout, an article's jargon is the Glossary rows plus its own rows.
- Literal tokens (paths, commands, flags, file names) in backticks per `/ari-hemingway--format-gdoc`.
- Every table MUST pass the mechanical check before it is shown to the user and again before Output. A subsystem table is checked as the Glossary rows followed by its own rows (`rows/<slug>.json` from the cluster step), so a hoisted row may lean on a Glossary row but never the reverse:
  ```zsh
  zsh $HOME/.claude/skills/ari-hemingway--structure-scaffold/bin/check_definitions_order.zsh --file <rows.json>
  ```
  Mentions are matched as whole words including plurals and -ed/-ing forms. Fix every violation; never present a table that fails.

### Scope — only the most important terms

The table must stay human-readable: target 25 to 35 rows, hard maximum 50. The first pass over a real topic yields 150+ candidates; the cut is a judge panel vote (`definitions_refine.js`), and unanimous votes are the default cut. Prefer nouns for things (places, files, objects, states) over command names. A term the reader can infer from plain English does not earn a row.

### Axiomatic definitions

When definitions still cycle after the layered rewrite, one term in the cycle becomes axiomatic: its definition uses no table term at all, only everyday words. An axiomatic definition is accepted only after a dedicated agent has attempted an ASD-STE100 (Simplified Technical English) rewrite of it; it then moves to the top of the table as a root row and the cycle breaks. `definitions_refine.js` does this automatically and reports the axioms; record them in `scratchpad.md`.

### Clustering

Subsystems come from the discover graph, never from a hand-written list. `bin/cluster_definitions.zsh` builds a graph from every discover term's `depends_on` list, finds communities by greedy modularity (Clauset-Newman-Moore) at the modularity peak with no forced count, re-clusters each community once on its own subgraph to propose the headings inside its article, merges communities under 2% of the nodes into the neighbour they share the most edges with, and names each from the member its cluster-mates depend on most (top three shown). One community is one article; its second-level parts are that article's headings.

A row of the accepted table is universal when at least half of its dependents lie outside its community and it has at least `nodes/15` dependents; the universal set is then closed under mentions, so a Glossary row never leans on a hoisted row. That ratio is the rule; when the articles' prose shares a term the rule left hoisted, `--universal "<term>"` is the escape hatch. The script warns when the universal share leaves 15% to 60%. An article may hoist no rows and run on Glossary vocabulary alone; `--min-rows N` folds communities with fewer than N hoisted rows into their most-connected neighbour. Flags address communities by the names the last run printed.

### Subsystem articles

- Each article is standalone: a reader who has the Glossary (and, in the folder layout, the article's own table) can read it alone.
- An article MAY name another subsystem. It MUST NOT describe another subsystem's internals — that belongs in that subsystem's own article.
- Prose in the tables' vocabulary only; any new jargon sends you back to the definitions pass to add a row, then resume.
- The split is the cluster step's proposal as the user accepted it; re-run the cluster step, never hand-move rows, when the discover set or the table changes.

### Diagrams

Diagrams are optional and unlimited; each names only terms from the Doc's tables. The Glossary carries the cluster-level graph from the cluster step (one node per subsystem, edges weighted by cross-subsystem dependencies, the universal rows as one group) at the head of `# Sub-explainers`, and any Doc may carry a layout diagram of 5 to 8 table terms after its table. Produce every diagram with `/ari-diagram-mermaid`, baking both `MERMAID_FORMAT=ink_url` and `MERMAID_FORMAT=live_url`, and embed it per the Diagrams rule in `/ari-hemingway--format-gdoc`: `[![alt](<ink_url>?width=620)](<live_url>)`, read from the two sidecars. The image MUST fit on one page and MUST link to its mermaid.live source in view form (`/view#`, as `live_url` bakes it); `/ari-hemingway--share-gdoc` checks both at publish time and fails otherwise. Keep it compact: 6 to 8 nodes in `flowchart LR` fit; split before adding more.

### Multi-agent workflows

The definitions passes are `Workflow` scripts shipped in `workflows/`. Invoking this skill is the user's opt-in to run them. Each pass is one workflow invocation; read its result before deciding the next. The Workflow tool refuses a `scriptPath` outside the working directory, so read the script once and pass its full text in `script`; the tool then prints a session-local path that works as `scriptPath` for reruns and resumes. `input_json` is a literal absolute path — the tool does not expand `$HOME`.

The tool runs at most 16 agents at once, so a pass's wall-clock is agent count times agent duration. The passes fill idle slots with eager work that is cheap to throw away: a grounding-only sweep beside the planner, two sweep agents per angle over halves of its sources, and `rewriters` candidates per fix round of which only the table with the fewest mechanical violations survives. Verification is never grouped to save agents: every 6-term define batch gets its own accuracy and structure refuter, because a refuter that has read one batch's sources must not carry them into the next. Reviewer agents are told explicitly not to flag brevity or omitted detail — without that instruction they re-bloat every row and reintroduce forward references.

## Investigation folder

Root path: `/tmp/hemingway/scaffold/{topic-slug}/{timestamp}/`. Structure, schemas, derivation rules, and cadence all follow `/ari-hemingway--lib`. Additional files:

```
definitions_pass1.json     # discover result (.result of the workflow task output)
definitions_refined.json   # refine result
definitions_final.json     # rows after hand edits, in table order; the accepted table
clusters.json              # cluster step result: communities, sections, hoisted and universal rows
rows/glossary.json         # universal rows; rows/<slug>.json = glossary rows then the article's rows
graph.mmd, graph.ink_url.url, graph.live_url.url   # cluster-level diagram (folder layout)
diagram.mmd, diagram.ink_url.url, diagram.live_url.url   # layout diagram (optional, any Doc)
draft.md                   # single Doc, or the Glossary Doc
subsystems/<slug>.md       # one draft per subsystem Doc (folder layout)
output.md, output/<slug>.md   # what /ari-hemingway--share-gdoc publishes
```

Scratchpad fields appended after `Last phase`:
```
- **Grounding**: <one line: where the facts come from — docs URL, local install, code paths>
- **Passes**: discover wf_<id> (<n> terms) → refine wf_<id> (<n> rows, <k> axioms)
- **Clusters**: <n> communities, <k> universal rows of <m>, modularity <q>; aliases: <term=discover term, ...>
- **Subsystems**: <agreed list: name (slug), ...>
- **Folder**: <parent id> → <target folder id> (parent_empty | child_exists | created), or "single Doc"
- **Doc URLs**: Glossary <url>; <subsystem> <url>; ...
```

## File storage

- `review-rules.md` — the constraints `/ari-hemingway--review-gdoc` enforces on a scaffold draft (loaded by its Sibling reviewer).
- `bin/check_definitions_order.zsh` — the mechanical table check (jq program in `lib/check_definitions_order.jq`). Read-only, exits 1 on violations.
- `bin/cluster_definitions.zsh` (+ `cluster_definitions.py`, per `/ari-skill-pythonscripts`) — clusters the discover graph into subsystems, maps the accepted table onto them, writes `clusters.json`, the cluster-level `graph.mmd`, and the per-Doc `rows/*.json`. Flags: `--alias`, `--merge`, `--rename`, `--universal`, `--min-rows`; `--force` overwrites outputs and removes stale `rows/*.json`.
- `bin/drive_subfolder.zsh` — chooses the publish folder: the user's folder when empty, else a child named after the topic (reused or created). `--dry-run` validates with Drive and creates nothing. Drive helpers come from `/ari-hemingway--lib`'s `lib/drive.zsh`.
- `tests/check_mention_matchers.zsh` + `tests/mention_matcher_cases.json` — feeds every case through the jq checker, the JS `mentionRe`, and the Python `mention_re`; exits 1 on any disagreement. Run it after touching any of the three.
- `workflows/definitions_discover.js` — Workflow script: plan angles with their sources (or take `angles`) while a grounding-only sweep runs, two sweeps per angle, batched first-pass definitions with verified doc links, two refuters per batch, completeness critic, dependency graph. Args: `{topic, grounding, angles?: [{key, prompt, sources?}], must_terms?, subsystems_hint?, batch_size?}`.
- `workflows/definitions_refine.js` — Workflow script: judge-panel selection, layered STE100 rewrite by racing rewriters, mechanical ordering check with fix rounds, axiomatic fallback, two factual refuters, recheck. Args: `{topic, grounding, input_json, terms?, judges?, min_votes?, target_rows?, must_terms?, max_sentences?, max_words?, ste100?, axiomatic?, fix_rounds?, rewriters?}`.

## Workflow

### Gather pointers

Collect the topic, the terms the user already wants defined (`must_terms`), any sources (docs URLs, a local install, code paths), the audience, and the Drive folder (id or `drive.google.com/drive/folders` URL) when the user wants a folder of Docs. Collect the mode: `research` (default, produces Docs) or `skeleton` (the caller asked for the table and the subsystem graph only). Derive `{topic-slug}` and create the investigation folder per `/ari-hemingway--lib` with `--skill-name scaffold`. Write the initial scratchpad (Subject, Mode `research` or `skeleton`, Pointers, Grounding, Folder).

### Restore context

Follow the `Restore context` procedure in `$HOME/.claude/skills/ari-hemingway--lib/SKILL.md`.

### Resolve permalink SHA

Only when the topic is code in the current worktree: follow `Resolve permalink SHA` in `$HOME/.claude/skills/ari-hemingway--lib/SKILL.md`. For an external topic (a tool, a product, a protocol) skip it; doc URLs replace permalinks.

### Definitions — discover

Run the discover workflow: read `workflows/definitions_discover.js` once and pass its text as `script`. Pass the topic, a one-paragraph grounding (what the agents may read and run), and the must-have terms; let it plan angles unless the user named them:

```
Workflow({script: <full text of workflows/definitions_discover.js>,
          args: {topic: "...", grounding: "...", must_terms: ["..."]}})
```

When it completes, save `.result` from the task output file to `definitions_pass1.json` (`jq '.result' <output-file>`). Expect every term to be cyclic on this pass; that is the raw material, not a failure. Record the pass in the scratchpad.

Print: `Discover complete — {n} terms, {k} cyclic. Next: Refine.`

### Definitions — refine

Run the refine workflow on the discover result the same way (`script` = the text of `workflows/definitions_refine.js`). Defaults are the strict cut (3 judges, unanimous, STE100 on, axiomatic fallback on):

```
Workflow({script: <full text of workflows/definitions_refine.js>,
          args: {topic: "...", grounding: "...", input_json: "<folder>/definitions_pass1.json", must_terms: ["..."]}})
```

Save `.result` to `definitions_refined.json`. If `violations` is non-empty, re-run with the offending terms removed or pass an explicit `terms` list. If the table is still long for its audience, re-run with `terms` set to the unanimous votes plus the few terms those rely on (the result's `votes` field has the tallies).

Copy the rows to `definitions_final.json`, apply hand edits (doc links the agents missed, trimmed duplication), and run the check script. Then render the table into `draft.md` and print it in chat for review — the table itself, in one message, no paraphrase — and wait. Apply the user's row cuts and rewordings, re-run the check, and re-present until accepted.

Print: `Refine complete — {n} rows, {k} axioms, 0 violations. Next: Cluster.`

### Subsystems — cluster

Emit exactly this one Bash call (add `--alias "<row term>=<discover term>"` for each row the refine pass renamed; a row the script cannot map lands in the Glossary with a WARN):

```zsh
zsh $HOME/.claude/skills/ari-hemingway--structure-scaffold/bin/cluster_definitions.zsh --discover <folder>/definitions_pass1.json --refined <folder>/definitions_final.json --out <folder>/clusters.json --mermaid <folder>/graph.mmd --rows-dir <folder>/rows
```

Present the proposal in one message and wait. The message MUST include, per community, its name candidates, its hoisted rows, and its proposed headings; then the universal rows with the `promoted` list; then every WARN line the script printed (cross-article mentions, unmapped rows, share out of band), each with the flag that resolves it. Example:

```
[0] Install layout (candidates: Install layout / Cellar / keg) — 41 terms
    hoisted: keg, Cellar, opt link        headings: Cellar · Linking
[1] Distribution (candidates: Distribution / bottle / tap) — 33 terms
    hoisted: bottle, tap                  headings: Bottles · Taps
Universal (6 of 11): prefix, formula, Cellar, ... — promoted by closure: Cellar (via prefix)
WARN cross-article mention | term='bottle' article='Distribution' mentions='keg' defined_in='Install layout' → --universal "keg"
```

Apply the user's changes by re-running the SAME command with `--force` and the changes appended, for example `--force --rename "Install layout=Cellar and links" --merge "Taps=Distribution" --universal "keg"`; never hand-move rows. Re-present until accepted, then run the check script on `rows/glossary.json` and every `rows/<slug>.json`. Fewer than two communities, or the user declining the split, means the single-Doc layout. Bake `graph.mmd` per the Diagrams rule and record the partition in the scratchpad.

Print: `Cluster complete — {n} subsystems, {k} universal rows of {m}, {w} warnings, 0 violations. Next: Subsystems.`

In `skeleton` mode the workflow ends here. Set `Last phase` to `Cluster (skeleton)`, then print `Skeleton complete — {folder}: definitions_final.json, clusters.json, rows/. Next: caller.` and stop; the caller reads those files and never edits them. Every later step is `research` mode only.

### Subsystems — draft

Draft each article standalone, in the vocabulary of the Glossary rows plus its own rows, with one `#` section per accepted heading. `clusters.json` names each article's terms; the refined pass JSON (`definitions_refined.json`, and `definitions_pass1.json` for detail the cut removed) is the primary grounding: every claim traces to a row there or to a source in `sources.md`. Review each article against three criteria: (a) jargon that is not in its tables, (b) any description of another subsystem's internals, (c) claims not grounded in the sources. Use one agent per article when the Agent tool is available; inside a fork, self-review each article against the same three criteria. Fix, then re-review changed articles. A term hoisted into one article MUST NOT be reworded away when two or more articles use it as jargon in prose: run the cluster step again with `--universal "<term>"` and regenerate both tables. Folder layout: one file per article in `subsystems/<slug>.md`, with its own table, `# Useful links`, and footer. Single Doc: one `##` per article under `# Subsystems`.

Print: `Subsystems complete — {n} articles, {words} words. Next: Summary.`

### Summary and draft

Write every summary last, from the accepted tables and articles. Follow the `Drafting` procedure in `$HOME/.claude/skills/ari-hemingway--lib/SKILL.md` and all `/ari-hemingway--format-gdoc` rules. Single Doc: the whole article is rewritten into `draft.md` as one file. Folder layout: `draft.md` is the Glossary Doc (its `# Sub-explainers` lists the subsystem names as plain text until Output fills in the URLs) and each `subsystems/<slug>.md` is rewritten whole.

Print: `Draft complete — {docs} docs, {words} words. Next: Fact-check.`

### Fact-check

Follow the `Fact-check gate` procedure in `$HOME/.claude/skills/ari-hemingway--lib/SKILL.md` for every draft. For external topics, "the codebase" is the grounding sources; each doc URL in a table counts as a claim and must resolve. The 20% `[TODO: verify]` gate applies per Doc.

Print: `Fact-check complete — {n} claims verified, {k} marked [TODO: verify]. Next: Present.`

### Present

Follow the `Present` procedure in `$HOME/.claude/skills/ari-hemingway--lib/SKILL.md`, listing every draft path (Glossary first).

### Folder structure

Decide the layout from the count of Docs. One Doc: publish it into the user's folder as it is, even when the folder is not empty; skip the rest of this step. No folder given: single Doc in My Drive; skip the rest of this step. Two or more Docs: emit exactly this one Bash call; it reports the user's folder when it is empty and otherwise the child folder named after the topic that it would reuse or create:

```zsh
zsh $HOME/.claude/skills/ari-hemingway--structure-scaffold/bin/drive_subfolder.zsh --parent <folder id or URL> --name "<Topic>" --dry-run
```

Show `folder_name` and `reason`. When `reason='child_missing'`, wait for the user to approve creating the child folder. Then emit the same call without `--dry-run`. An empty `folder_id` after the real run is an error; stop. Record `folder_id` and `reason` under `Folder` in the scratchpad.

Print: `Folder complete — {folder_id} ({reason}). Next: Output.`

### Output

Follow the `Output` procedure in `$HOME/.claude/skills/ari-hemingway--lib/SKILL.md` for each Doc (`output.md` for the single Doc or the Glossary; `output/<slug>.md` per subsystem). Then publish with `/ari-hemingway--share-gdoc`, passing `--folder <folder_id>` on every creation: one dry-run pass over every Doc, one message listing every title and the target folder, one confirmation, then publish all; a per-Doc gate only when a Doc fails. Folder layout order: the Glossary first; then each subsystem Doc, whose Summary carries the Glossary URL; then rewrite the Glossary's `# Sub-explainers` with the subsystem Docs' raw URLs and update it in place with `--doc`. Record each URL under `Doc URLs` in the scratchpad as soon as its Doc exists; on a failure, fix the draft and re-run Output, creating only the Docs without a URL. Any later revision of any Doc uses `--doc <its URL>`, never `--folder`.
